import Foundation
import EmbrCore

public struct AuthContext: Sendable {
    public enum Source: String, Sendable {
        case flag
        case environment
        case config
    }

    public let clientID: String
    public let accessToken: String
    public let refreshToken: String?
    public let scopes: [String]
    public let expiresAt: Date?
    public let userID: String?
    public let login: String?
    public let source: Source
    public let profile: String
    public let refreshURL: String?

    public init(
        clientID: String,
        accessToken: String,
        refreshToken: String?,
        scopes: [String],
        expiresAt: Date?,
        userID: String?,
        login: String?,
        source: Source,
        profile: String,
        refreshURL: String? = nil
    ) {
        self.clientID = clientID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.userID = userID
        self.login = login
        self.source = source
        self.profile = profile
        self.refreshURL = refreshURL
    }

    public var expiresIn: Int? {
        expiresAt.map { Int($0.timeIntervalSinceNow) }
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

public struct TokenIdentity: Sendable, Equatable {
    public let clientID: String
    public let login: String?
    public let userID: String?
    public let scopes: [String]
    public let expiresIn: Int

    public init(clientID: String, login: String?, userID: String?, scopes: [String], expiresIn: Int) {
        self.clientID = clientID
        self.login = login
        self.userID = userID
        self.scopes = scopes
        self.expiresIn = expiresIn
    }
}

private struct ValidateResponse: Decodable, Sendable {
    let clientID: String
    let login: String?
    let userID: String?
    let scopes: [String]
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case login
        case userID = "user_id"
        case scopes
        case expiresIn = "expires_in"
    }
}

public struct AuthStatus: Sendable {
    public let clientID: String?
    public let profile: String
    public let source: String?
    public let login: String?
    public let userID: String?
    public let scopes: [String]
    public let expiresAt: Date?
    public let configPath: String
    public let configPermissions: Int?
    public let configMode: String?
}


public struct ConfigProfileSummary: Encodable, Sendable {
    public let name: String
    public let clientID: String?
    public let hasAccessToken: Bool
    public let hasRefreshToken: Bool
    public let login: String?
    public let scopes: [String]
    public let expiresAt: Date?
    public let refreshURL: String?
}

public struct ConfigSnapshot: Encodable, Sendable {
    public let path: String
    public let exists: Bool
    public let permissions: Int?
    public let mode: String?
    public let profile: String
    public let profiles: [ConfigProfileSummary]
    public let environmentOverrides: [String]
}

public actor AuthService {
    private let store: CredentialsStore
    private let environment: [String: String]
    private let client: APIClient
    private let profile: String
    private let clientIDOverride: String?
    private let tokenOverride: String?
    private let canRefresh: Bool
    private var cached: AuthContext?
    private var identityCache: [String: TokenIdentity] = [:]

    public init(
        store: CredentialsStore,
        environment: [String: String],
        client: APIClient,
        profile: String,
        clientIDOverride: String? = nil,
        tokenOverride: String? = nil,
        canRefresh: Bool = true
    ) {
        self.store = store
        self.environment = environment
        self.client = client
        self.profile = profile
        self.clientIDOverride = clientIDOverride
        self.tokenOverride = tokenOverride
        self.canRefresh = canRefresh
    }

    public func current() async throws -> AuthContext {
        if let cached {
            if cached.isExpired, cached.refreshToken != nil, canRefresh {
                let refreshed = try await performRefresh(cached)
                self.cached = refreshed
                return refreshed
            }
            return cached
        }
        let file = store.load()
        let stored = file.profiles[profile] ?? StoredProfile()
        guard let clientID = resolvedClientID(stored), !clientID.isEmpty else {
            throw CLIError.auth(
                "No Twitch client id is configured.",
                hint: "Set EMBR_CLIENT_ID, pass --client-id, or run `embr auth login --client-id <id>`."
            )
        }

        let envToken = environment["EMBR_ACCESS_TOKEN"] ?? environment["TWITCH_ACCESS_TOKEN"]
        let injected = tokenOverride ?? envToken
        let refreshToken = environment["EMBR_REFRESH_TOKEN"] ?? stored.refreshToken
        let source: AuthContext.Source = tokenOverride != nil ? .flag : (envToken != nil ? .environment : .config)

        var accessToken = injected ?? stored.accessToken
        let expiresAt = injected == nil ? stored.expiresAt : nil
        let scopes = stored.scopes
        let userID = stored.userID
        let login = stored.login
        let refreshURL = environment["EMBR_REFRESH_URL"] ?? stored.refreshURL

        if accessToken == nil, let refreshToken {
            let provisional = AuthContext(
                clientID: clientID,
                accessToken: "",
                refreshToken: refreshToken,
                scopes: stored.scopes,
                expiresAt: stored.expiresAt,
                userID: stored.userID,
                login: stored.login,
                source: source,
                profile: profile,
                refreshURL: refreshURL
            )
            guard canRefresh else {
                throw CLIError.auth("The access token is missing and --dry-run will not refresh one.", hint: "Drop --dry-run, or run `embr auth refresh`.")
            }
            let refreshed = try await performRefresh(provisional)
            cached = refreshed
            return refreshed
        }

        if let token = accessToken {
            let expiring = expiresAt.map { $0.timeIntervalSinceNow < 60 } ?? false
            if expiring, let refreshToken, canRefresh, source != .flag {
                let provisional = AuthContext(
                    clientID: clientID,
                    accessToken: token,
                    refreshToken: refreshToken,
                    scopes: scopes,
                    expiresAt: expiresAt,
                    userID: userID,
                    login: login,
                    source: source,
                    profile: profile,
                    refreshURL: refreshURL
                )
                let refreshed = try await performRefresh(provisional)
                cached = refreshed
                return refreshed
            }
            if expiring, !canRefresh {
                accessToken = token
            } else if expiring, refreshToken == nil {
                throw CLIError.auth("The access token has expired.", hint: "Run `embr auth login` to sign in again.")
            }
            _ = accessToken
            let context = AuthContext(
                clientID: clientID,
                accessToken: token,
                refreshToken: refreshToken,
                scopes: scopes,
                expiresAt: expiresAt,
                userID: userID,
                login: login,
                source: source,
                profile: profile,
                refreshURL: refreshURL
            )
            cached = context
            return context
        }

        throw CLIError.auth("Not signed in.", hint: "Run `embr auth login`.")
    }

    public func identity(_ auth: AuthContext) async throws -> TokenIdentity {
        if let cached = identityCache[auth.accessToken] {
            return cached
        }
        let request = HTTPRequest(
            method: .get,
            url: URL(string: "https://id.twitch.tv/oauth2/validate")!,
            headers: ["Authorization": "OAuth \(auth.accessToken)"]
        )
        let response = try await client.send(request)
        try client.requireSuccess(response)
        let validation: ValidateResponse
        do {
            validation = try TwitchJSON.decoder.decode(ValidateResponse.self, from: response.body)
        } catch {
            throw CLIError(.decode, "Could not read the token validation response.")
        }
        let identity = TokenIdentity(
            clientID: validation.clientID,
            login: validation.login,
            userID: validation.userID,
            scopes: validation.scopes,
            expiresIn: validation.expiresIn
        )
        identityCache[auth.accessToken] = identity
        if auth.source == .config {
            _ = try? store.update(profile) { file in
                var stored = file.profiles[profile] ?? StoredProfile()
                stored.login = identity.login
                stored.userID = identity.userID
                stored.scopes = identity.scopes
                stored.expiresAt = Date().addingTimeInterval(TimeInterval(identity.expiresIn))
                stored.tokenKind = "user"
                file.profiles[profile] = stored
            }
        }
        if let current = cached, current.accessToken == auth.accessToken {
            cached = AuthContext(
                clientID: auth.clientID,
                accessToken: auth.accessToken,
                refreshToken: auth.refreshToken,
                scopes: identity.scopes,
                expiresAt: auth.expiresAt,
                userID: identity.userID,
                login: identity.login,
                source: auth.source,
                profile: auth.profile,
                refreshURL: auth.refreshURL
            )
        }
        return identity
    }

    public func refresh(_ auth: AuthContext) async throws -> AuthContext {
        let refreshed = try await performRefresh(auth)
        cached = refreshed
        return refreshed
    }

    public func startDevice(clientID: String, scopes: [String]) async throws -> DeviceAuthorization.Start {
        let response = try await client.send(DeviceAuthorization.startRequest(clientID: clientID, scopes: scopes))
        guard response.isSuccess else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        do {
            return try DeviceAuthorization.decodeStart(response)
        } catch {
            throw CLIError(.decode, "Could not read the device code response.")
        }
    }

    public func pollDevice(clientID: String, deviceCode: String, scopes: [String]) async throws -> DeviceAuthorization.PollResult {
        let response = try await client.send(DeviceAuthorization.tokenRequest(clientID: clientID, deviceCode: deviceCode, scopes: scopes))
        return DeviceAuthorization.pollResult(response)
    }

    public func accept(
        token: DeviceAuthorization.Token,
        clientID: String,
        requestedScopes: [String]
    ) async throws -> AuthContext {
        let expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        let scopes = token.scope?.isEmpty == false ? token.scope! : requestedScopes
        var validated: TokenIdentity?
        do {
            validated = try await identity(AuthContext(
                clientID: clientID,
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                scopes: scopes,
                expiresAt: expiresAt,
                userID: nil,
                login: nil,
                source: .environment,
                profile: profile
            ))
        } catch {
            validated = nil
        }

        try store.update(profile) { file in
            var stored = file.profiles[profile] ?? StoredProfile()
            stored.clientID = clientID
            stored.accessToken = token.accessToken
            stored.refreshToken = token.refreshToken
            stored.scopes = validated?.scopes ?? scopes
            stored.expiresAt = Date().addingTimeInterval(TimeInterval(validated?.expiresIn ?? token.expiresIn))
            stored.userID = validated?.userID ?? stored.userID
            stored.login = validated?.login ?? stored.login
            stored.tokenKind = "user"
            if let refreshURL = environment["EMBR_REFRESH_URL"] {
                stored.refreshURL = refreshURL
            }
            file.profiles[profile] = stored
        }

        let context = AuthContext(
            clientID: clientID,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            scopes: validated?.scopes ?? scopes,
            expiresAt: expiresAt,
            userID: validated?.userID,
            login: validated?.login,
            source: .config,
            profile: profile,
            refreshURL: environment["EMBR_REFRESH_URL"] ?? store.profile(profile)?.refreshURL
        )
        cached = context
        return context
    }

    public func appToken(clientID: String, clientSecret: String, scopes: [String]) async throws -> OAuthToken {
        let response = try await client.send(AppAccessToken.request(clientID: clientID, clientSecret: clientSecret, scopes: scopes))
        guard response.isSuccess else {
            if response.status == 400 || response.status == 401 {
                throw CLIError(
                    .auth,
                    "Twitch rejected the client credentials.",
                    status: response.status,
                    hint: "Check the client id and the secret in EMBR_CLIENT_SECRET."
                )
            }
            throw CLIError.http(status: response.status, body: response.body)
        }
        do {
            return try AppAccessToken.decode(response)
        } catch {
            throw CLIError(.decode, "Could not read the app token response.")
        }
    }

    public func revoke(_ auth: AuthContext) async throws {
        var components = URLComponents(string: "https://id.twitch.tv/oauth2/revoke")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: auth.clientID),
            URLQueryItem(name: "token", value: auth.accessToken)
        ]
        let body = (components.percentEncodedQuery ?? "").data(using: .utf8)
        let request = HTTPRequest(
            method: .post,
            url: components.url!,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        let response = try await client.send(request)
        if response.status != 200 {
            throw CLIError.http(status: response.status, body: response.body)
        }
    }

    public func clear(profile named: String? = nil) throws {
        try store.remove(named ?? profile)
        if (named ?? profile) == profile {
            cached = nil
        }
    }

    public func status() async -> AuthStatus {
        let file = store.load()
        let stored = file.profiles[profile] ?? StoredProfile()
        let clientID = resolvedClientID(stored)
        let envToken = environment["EMBR_ACCESS_TOKEN"] ?? environment["TWITCH_ACCESS_TOKEN"]
        let source: String?
        if tokenOverride != nil {
            source = "flag"
        } else if envToken != nil {
            source = "environment"
        } else if stored.accessToken != nil {
            source = "config"
        } else {
            source = nil
        }
        return AuthStatus(
            clientID: clientID,
            profile: profile,
            source: source,
            login: stored.login,
            userID: stored.userID,
            scopes: stored.scopes,
            expiresAt: stored.expiresAt,
            configPath: store.url.path,
            configPermissions: store.permissions(),
            configMode: store.permissions().map { String(format: "%03o", $0) }
        )
    }


    public func configSnapshot() -> ConfigSnapshot {
        let file = store.load()
        let overrides = [
            environment["EMBR_CLIENT_ID"] != nil || environment["TWITCH_CLIENT_ID"] != nil ? "EMBR_CLIENT_ID" : nil,
            environment["EMBR_ACCESS_TOKEN"] != nil || environment["TWITCH_ACCESS_TOKEN"] != nil ? "EMBR_ACCESS_TOKEN" : nil,
            environment["EMBR_REFRESH_TOKEN"] != nil ? "EMBR_REFRESH_TOKEN" : nil,
            environment["EMBR_CLIENT_SECRET"] != nil ? "EMBR_CLIENT_SECRET" : nil
        ].compactMap { $0 }
        return ConfigSnapshot(
            path: store.url.path,
            exists: store.exists,
            permissions: store.permissions(),
            mode: store.permissions().map { String(format: "%03o", $0) },
            profile: profile,
            profiles: file.profiles.keys.sorted().map { name in
                let stored = file.profiles[name] ?? StoredProfile()
                return ConfigProfileSummary(
                    name: name,
                    clientID: stored.clientID,
                    hasAccessToken: stored.accessToken != nil,
                    hasRefreshToken: stored.refreshToken != nil,
                    login: stored.login,
                    scopes: stored.scopes,
                    expiresAt: stored.expiresAt,
                    refreshURL: stored.refreshURL
                )
            },
            environmentOverrides: overrides
        )
    }

    public var profileName: String { profile }

    public var configPath: String { store.url.path }

    public func configuredClientID() -> String? {
        resolvedClientID(store.load().profiles[profile] ?? StoredProfile())
    }

    private func resolvedClientID(_ stored: StoredProfile) -> String? {
        let value = clientIDOverride
            ?? environment["EMBR_CLIENT_ID"]
            ?? environment["TWITCH_CLIENT_ID"]
            ?? stored.clientID
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func performRefresh(_ auth: AuthContext) async throws -> AuthContext {
        guard let refreshToken = auth.refreshToken else {
            throw CLIError.auth("The token expired and there is no refresh token.", hint: "Run `embr auth login`.")
        }
        if let refreshURL = auth.refreshURL, let worker = workerRefreshURL(refreshURL) {
            do {
                let token = try await refreshThroughWorker(worker, refreshToken: refreshToken)
                return try persist(token, auth: auth)
            } catch let error as CLIError where error.kind == .auth {
                throw error
            } catch {
                if environment["EMBR_CLIENT_SECRET"] == nil {
                    throw error
                }
            }
        }
        let token = try await refreshDirect(auth, refreshToken: refreshToken)
        return try persist(token, auth: auth)
    }

    private func refreshThroughWorker(_ url: URL, refreshToken: String) async throws -> OAuthToken {
        let body = try? JSONEncoder().encode(["refreshToken": refreshToken])
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/json"],
            body: body
        )
        let response = try await client.send(request)
        if response.status == 400 || response.status == 401 {
            throw CLIError(
                .auth,
                "Twitch rejected the refresh token.",
                status: response.status,
                hint: "Run `embr auth login` to sign in again."
            )
        }
        guard response.isSuccess else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        struct WorkerToken: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int
            let scope: [String]?
        }
        let decoded: WorkerToken
        do {
            decoded = try JSONDecoder().decode(WorkerToken.self, from: response.body)
        } catch {
            throw CLIError(.decode, "Could not read the worker's refreshed token.")
        }
        return OAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresIn: decoded.expiresIn,
            scope: decoded.scope ?? []
        )
    }

    private func refreshDirect(_ auth: AuthContext, refreshToken: String) async throws -> OAuthToken {
        let secret = environment["EMBR_CLIENT_SECRET"]
        let request = TokenRefresh.request(clientID: auth.clientID, clientSecret: secret, refreshToken: refreshToken)
        let response = try await client.send(request)
        guard response.isSuccess else {
            if response.status == 400 || response.status == 401 {
                throw CLIError(
                    .auth,
                    "Twitch rejected the refresh request.",
                    status: response.status,
                    hint: "If this app is confidential, set EMBR_CLIENT_SECRET; otherwise run `embr auth login` to sign in again."
                )
            }
            throw CLIError.http(status: response.status, body: response.body)
        }
        do {
            return try TokenRefresh.decode(response)
        } catch {
            throw CLIError(.decode, "Could not read the refreshed token.")
        }
    }

    private func persist(_ token: OAuthToken, auth: AuthContext) throws -> AuthContext {
        let expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        let scopes = token.scope.isEmpty ? auth.scopes : token.scope
        let updated = AuthContext(
            clientID: auth.clientID,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? auth.refreshToken,
            scopes: scopes,
            expiresAt: expiresAt,
            userID: auth.userID,
            login: auth.login,
            source: auth.source,
            profile: auth.profile,
            refreshURL: auth.refreshURL
        )
        if auth.source == .config {
            _ = try? store.update(profile) { file in
                var stored = file.profiles[profile] ?? StoredProfile()
                stored.clientID = auth.clientID
                stored.accessToken = updated.accessToken
                stored.refreshToken = updated.refreshToken
                stored.scopes = updated.scopes
                stored.expiresAt = updated.expiresAt
                stored.tokenKind = "user"
                file.profiles[profile] = stored
            }
        }
        return updated
    }

    public func refreshStrategy() -> String {
        let stored = store.load().profiles[profile] ?? StoredProfile()
        let refreshURL = environment["EMBR_REFRESH_URL"] ?? stored.refreshURL
        if let refreshURL, workerRefreshURL(refreshURL) != nil { return "worker" }
        return environment["EMBR_CLIENT_SECRET"] != nil ? "secret" : "none"
    }

    public func setRefreshURL(_ value: String?) throws {
        try store.update(profile) { file in
            var stored = file.profiles[profile] ?? StoredProfile()
            stored.refreshURL = value
            file.profiles[profile] = stored
        }
        cached = nil
    }

    private func workerRefreshURL(_ raw: String) -> URL? {
        if environment["EMBR_DISABLE_WORKER_REFRESH"] == "1" {
            return nil
        }
        return URL(string: raw)
    }
}
