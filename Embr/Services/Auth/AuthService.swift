import Foundation
import Combine
import AuthenticationServices
import EmbrCore

actor AuthService: AuthControlling {
    static let shared = AuthService()

    private let store: TokenStoring
    private let worker: WorkerAuthClient
    private let transport: HTTPTransport
    private let clientID: String
    private let redirectURI: String

    private var credentials: StoredCredentials?
    private var loadedFromStore = false
    private var appToken: (token: String, expiresAt: Date)?
    private var validateTask: Task<Void, Never>?

    private nonisolated let stateSubject = StateSubjectBox()

    nonisolated var statePublisher: AnyPublisher<AuthState, Never> {
        stateSubject.publisher
    }

    init(
        store: TokenStoring = KeychainTokenStore.shared,
        worker: WorkerAuthClient = WorkerAuthClient.shared,
        transport: HTTPTransport = URLSessionTransport.shared
    ) {
        self.store = store
        self.worker = worker
        self.transport = transport
        self.clientID = Configuration.current.twitchClientID
        self.redirectURI = Configuration.current.redirectURI
        Task { await self.bootstrap() }
    }

    func currentUser() async -> AuthenticatedUser? {
        await ensureLoaded()
        return credentials.map(Self.user(from:))
    }

    func logout() async {
        await ensureLoaded()
        let token = credentials?.accessToken
        credentials = nil
        appToken = nil
        validateTask?.cancel()
        validateTask = nil
        await store.clear()
        if let token {
            await revoke(token)
        }
        publish(.anonymous)
        AppLogger.shared.info("logged out", category: .auth)
    }

    func validAccessToken() async throws -> String {
        await ensureLoaded()
        guard let current = credentials else { throw APIError.unauthorized }
        if !current.isExpiring(within: 300, now: Date()) {
            return current.accessToken
        }
        guard let refreshToken = current.refreshToken else {
            throw APIError.unauthorized
        }
        let token = try await worker.refresh(refreshToken: refreshToken)
        let refreshed = StoredCredentials(
            userID: token.userID ?? current.userID,
            login: token.login ?? current.login,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? current.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            scopes: token.scope ?? current.scopes
        )
        credentials = refreshed
        await store.save(refreshed)
        publish(.authenticated(Self.user(from: refreshed)))
        AppLogger.shared.info("refreshed access token", category: .auth)
        return refreshed.accessToken
    }

    func appAccessToken() async throws -> String {
        if let cached = appToken, cached.expiresAt.timeIntervalSinceNow > 300 {
            return cached.token
        }
        let result = try await worker.appToken()
        let expiresAt = Date().addingTimeInterval(TimeInterval(result.expiresIn))
        appToken = (result.token, expiresAt)
        return result.token
    }

    @MainActor
    func login(presentationAnchor: ASPresentationAnchor) async throws -> AuthenticatedUser {
        let request = try await prepareLogin()
        let coordinator = TwitchLoginCoordinator(anchor: presentationAnchor)
        let callbackURL = try await coordinator.authorize(
            authorizeURL: request.authorizeURL,
            callbackScheme: request.scheme
        )
        if let returned = coordinator.state(from: callbackURL), returned != request.state {
            throw APIError.invalidRequest("login state mismatch")
        }
        guard let code = coordinator.code(from: callbackURL) else {
            throw APIError.invalidRequest("login callback missing code")
        }
        return try await completeLogin(code: code, redirectURI: request.redirectURI)
    }

    private struct LoginRequest: Sendable {
        let authorizeURL: URL
        let redirectURI: String
        let scheme: String
        let state: String
    }

    private func prepareLogin() async throws -> LoginRequest {
        let state = UUID().uuidString
        let scheme = Self.scheme(from: redirectURI) ?? "embr"
        let authorizeURL = try await worker.loginURL(redirectURI: redirectURI, state: state)
        return LoginRequest(authorizeURL: authorizeURL, redirectURI: redirectURI, scheme: scheme, state: state)
    }

    private func completeLogin(code: String, redirectURI: String) async throws -> AuthenticatedUser {
        let token = try await worker.exchange(code: code, redirectURI: redirectURI)
        var stored = worker.credentials(from: token)
        if let validation = try? await validate(accessToken: token.accessToken) {
            stored = StoredCredentials(
                userID: validation.userID ?? stored.userID,
                login: validation.login ?? stored.login,
                accessToken: stored.accessToken,
                refreshToken: stored.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(validation.expiresIn)),
                scopes: validation.scopes.isEmpty ? stored.scopes : validation.scopes
            )
        }
        credentials = stored
        await store.save(stored)
        let user = Self.user(from: stored)
        publish(.authenticated(user))
        startPeriodicValidation()
        AppLogger.shared.info("logged in as \(user.login)", category: .auth)
        return user
    }

    private func bootstrap() async {
        await ensureLoaded()
        if let current = credentials {
            publish(.authenticated(Self.user(from: current)))
            startPeriodicValidation()
        }
    }

    private func ensureLoaded() async {
        guard !loadedFromStore else { return }
        loadedFromStore = true
        credentials = await store.load()
    }

    private func startPeriodicValidation() {
        guard validateTask == nil else { return }
        validateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                if Task.isCancelled { return }
                await self?.runValidation()
            }
        }
    }

    private func runValidation() async {
        guard let token = credentials?.accessToken else { return }
        do {
            let validation = try await validate(accessToken: token)
            if let current = credentials {
                let updated = StoredCredentials(
                    userID: validation.userID ?? current.userID,
                    login: validation.login ?? current.login,
                    accessToken: current.accessToken,
                    refreshToken: current.refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(validation.expiresIn)),
                    scopes: validation.scopes.isEmpty ? current.scopes : validation.scopes
                )
                credentials = updated
                await store.save(updated)
            }
        } catch APIError.unauthorized {
            AppLogger.shared.warn("hourly validate rejected token, attempting refresh", category: .auth)
            _ = try? await validAccessToken()
        } catch {
            AppLogger.shared.warn("hourly validate failed: \(error)", category: .auth)
        }
    }

    private func validate(accessToken: String) async throws -> TokenValidation {
        var request = HTTPRequest(method: .get, url: URL(string: "https://id.twitch.tv/oauth2/validate")!)
        request.setHeader("Authorization", "OAuth \(accessToken)")
        let response = try await transport.send(request)
        guard response.isSuccess else {
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
        return try TwitchJSON.decode(TokenValidation.self, from: response.body)
    }

    private func revoke(_ accessToken: String) async {
        var request = HTTPRequest(
            method: .post,
            url: URL(string: "https://id.twitch.tv/oauth2/revoke")!
        )
        request.setHeader("Content-Type", "application/x-www-form-urlencoded")
        let body = "client_id=\(clientID)&token=\(accessToken)"
        request.body = body.data(using: .utf8)
        _ = try? await transport.send(request)
    }

    private func publish(_ state: AuthState) {
        stateSubject.send(state)
    }

    private static func user(from credentials: StoredCredentials) -> AuthenticatedUser {
        AuthenticatedUser(
            id: credentials.userID,
            login: credentials.login,
            displayName: credentials.login,
            scopes: credentials.scopes
        )
    }

    private static func scheme(from redirectURI: String) -> String? {
        URLComponents(string: redirectURI)?.scheme
    }
}

private final class StateSubjectBox: @unchecked Sendable {
    private let subject = CurrentValueSubject<AuthState, Never>(.anonymous)

    var publisher: AnyPublisher<AuthState, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(_ state: AuthState) {
        if Thread.isMainThread {
            subject.send(state)
        } else {
            DispatchQueue.main.async { [subject] in
                subject.send(state)
            }
        }
    }
}
