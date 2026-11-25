import Foundation
import EmbrCore

public struct RunOptions: Sendable {
    public var all: Bool
    public var first: Int?
    public var after: String?
    public var maxPages: Int
    public var raw: Bool
    public var dryRun: Bool
    public var noInput: Bool

    public init(
        all: Bool = false,
        first: Int? = nil,
        after: String? = nil,
        maxPages: Int = 50,
        raw: Bool = false,
        dryRun: Bool = false,
        noInput: Bool = false
    ) {
        self.all = all
        self.first = first
        self.after = after
        self.maxPages = max(1, maxPages)
        self.raw = raw
        self.dryRun = dryRun
        self.noInput = noInput
    }
}

public struct RunContext: Sendable {
    public let client: APIClient
    public let auth: AuthContext?
    public let authService: AuthService
    public let renderer: Renderer
    public let options: RunOptions
    public let environment: [String: String]
    public let resolver: Resolver
    public let profile: String

    public init(
        client: APIClient,
        auth: AuthContext?,
        authService: AuthService,
        renderer: Renderer,
        options: RunOptions,
        environment: [String: String],
        profile: String = "default"
    ) {
        self.client = client
        self.auth = auth
        self.authService = authService
        self.renderer = renderer
        self.options = options
        self.environment = environment
        self.profile = profile
        self.resolver = Resolver(client: client, auth: auth, dryRun: options.dryRun)
    }

    public func requireAuth() throws -> AuthContext {
        guard let auth else {
            throw CLIError.auth("Not signed in.", hint: "Run `embr auth login`.")
        }
        return auth
    }

    public func token() throws -> String {
        try requireAuth().accessToken
    }

    public func factory() throws -> HelixRequestFactory {
        HelixRequestFactory(clientID: try requireAuth().clientID)
    }

    public func userID() async throws -> String {
        let auth = try requireAuth()
        if let userID = auth.userID, !userID.isEmpty {
            return userID
        }
        guard let userID = try await authService.identity(auth).userID, !userID.isEmpty else {
            throw CLIError.auth(
                "This token has no user behind it (an app access token).",
                hint: "Run `embr auth login` or pass a user token for this command."
            )
        }
        return userID
    }

    public func login() async throws -> String {
        let auth = try requireAuth()
        if let login = auth.login, !login.isEmpty {
            return login
        }
        guard let login = try await authService.identity(auth).login, !login.isEmpty else {
            throw CLIError.auth(
                "This token has no user behind it (an app access token).",
                hint: "Run `embr auth login` or pass a user token for this command."
            )
        }
        return login
    }

    public func moderatorID(_ override: String?) async throws -> String {
        if let override, !override.isEmpty {
            return try await resolver.user(override).id
        }
        return try await userID()
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await client.send(request)
        try client.requireSuccess(response)
        return response
    }

    public func decode<T: Decodable>(_ type: T.Type, _ response: HTTPResponse) throws -> T {
        do {
            return try TwitchJSON.decoder.decode(type, from: response.body)
        } catch {
            throw CLIError(.decode, "Could not decode \(type): \(error)")
        }
    }

    public func rawValue(_ response: HTTPResponse) throws -> JSONValue {
        do {
            return try JSONValue.decode(response.body)
        } catch {
            throw CLIError(.decode, "Could not read Twitch's JSON: \(error)")
        }
    }

    public func collect<Model: Sendable>(
        _ request: HTTPRequest,
        decode: @Sendable (Data) throws -> HelixResponse<Model>,
        next: @Sendable (String) -> HTTPRequest
    ) async throws -> (items: [Model], cursor: String?) {
        var items: [Model] = []
        var current = request
        var cursor: String? = options.after
        var pages = 0
        while true {
            let response = try await client.send(current)
            try client.requireSuccess(response)
            let page: HelixResponse<Model>
            do {
                page = try decode(response.body)
            } catch {
                throw CLIError(.decode, "Could not decode Twitch's page: \(error)")
            }
            items.append(contentsOf: page.data)
            cursor = page.pagination?.cursor
            pages += 1
            guard options.all, let nextCursor = cursor, pages < options.maxPages else { break }
            await client.sleepIfExhausted(response)
            current = next(nextCursor)
        }
        return (items, cursor)
    }

    public func collectWithTotal<Model: Sendable>(
        _ request: HTTPRequest,
        decode: @Sendable (Data) throws -> HelixResponse<Model>,
        next: @Sendable (String) -> HTTPRequest
    ) async throws -> (items: [Model], cursor: String?, total: Int?) {
        var items: [Model] = []
        var current = request
        var cursor: String? = options.after
        var total: Int?
        var pages = 0
        while true {
            let response = try await client.send(current)
            try client.requireSuccess(response)
            let page: HelixResponse<Model>
            do {
                page = try decode(response.body)
            } catch {
                throw CLIError(.decode, "Could not decode Twitch's page: \(error)")
            }
            if total == nil {
                total = page.total
            }
            items.append(contentsOf: page.data)
            cursor = page.pagination?.cursor
            pages += 1
            guard options.all, let nextCursor = cursor, pages < options.maxPages else { break }
            await client.sleepIfExhausted(response)
            current = next(nextCursor)
        }
        return (items, cursor, total)
    }

    public func readMessage(_ parts: [String]) throws -> String {
        if parts == ["-"] {
            guard !options.noInput else {
                throw CLIError.usage("Refusing to read stdin because --no-input was passed.")
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw CLIError.usage("stdin was empty.")
            }
            return text
        }
        return parts.joined(separator: " ")
    }
}

public actor Resolver {
    private let client: APIClient
    private let auth: AuthContext?
    private let dryRun: Bool
    private var userCache: [String: TwitchUser] = [:]

    public init(client: APIClient, auth: AuthContext?, dryRun: Bool = false) {
        self.client = client
        self.auth = auth
        self.dryRun = dryRun
    }

    public func user(_ input: String) async throws -> TwitchUser {
        let key = input.lowercased()
        if let cached = userCache[key] {
            return cached
        }
        if dryRun, input.allSatisfy(\.isNumber), !input.isEmpty {
            let synthetic = TwitchUser(id: input, login: input, displayName: input)
            userCache[key] = synthetic
            return synthetic
        }
        guard let auth else {
            throw CLIError.auth("Not signed in.", hint: "Run `embr auth login`.")
        }
        let factory = HelixRequestFactory(clientID: auth.clientID)
        let request: HTTPRequest
        if input.allSatisfy(\.isNumber), !input.isEmpty {
            request = factory.usersByIDs([input], token: auth.accessToken)
        } else {
            request = factory.usersByLogins([input], token: auth.accessToken)
        }
        let response = try await client.send(request)
        try client.requireSuccess(response)
        let page: HelixResponse<TwitchUser>
        do {
            page = try HelixDecoder.users(response.body)
        } catch {
            throw CLIError(.decode, "Could not decode the user lookup: \(error)")
        }
        guard let user = page.data.first else {
            throw CLIError.notFound("No Twitch user matches `\(input)`.")
        }
        userCache[key] = user
        userCache[user.id] = user
        userCache[user.login.lowercased()] = user
        return user
    }

    public func userID(_ input: String) async throws -> String {
        try await user(input).id
    }

    public func users(_ inputs: [String]) async throws -> [TwitchUser] {
        guard let auth else {
            throw CLIError.auth("Not signed in.", hint: "Run `embr auth login`.")
        }
        var missing: [String] = []
        for input in inputs where userCache[input.lowercased()] == nil {
            if !missing.contains(where: { $0.lowercased() == input.lowercased() }) {
                missing.append(input)
            }
        }
        let factory = HelixRequestFactory(clientID: auth.clientID)
        let numeric = missing.filter { $0.allSatisfy(\.isNumber) && !$0.isEmpty }
        let logins = missing.filter { !($0.allSatisfy(\.isNumber) && !$0.isEmpty) }
        if !numeric.isEmpty {
            let response = try await client.send(factory.usersByIDs(numeric, token: auth.accessToken))
            try client.requireSuccess(response)
            let page: HelixResponse<TwitchUser>
            do {
                page = try HelixDecoder.users(response.body)
            } catch {
                throw CLIError(.decode, "Could not decode the user lookup: \(error)")
            }
            for user in page.data {
                cache(user)
            }
        }
        if !logins.isEmpty {
            let response = try await client.send(factory.usersByLogins(logins, token: auth.accessToken))
            try client.requireSuccess(response)
            let page: HelixResponse<TwitchUser>
            do {
                page = try HelixDecoder.users(response.body)
            } catch {
                throw CLIError(.decode, "Could not decode the user lookup: \(error)")
            }
            for user in page.data {
                cache(user)
            }
        }
        return try inputs.map { input in
            guard let user = userCache[input.lowercased()] else {
                throw CLIError.notFound("No Twitch user matches `\(input)`.")
            }
            return user
        }
    }

    private func cache(_ user: TwitchUser) {
        userCache[user.id] = user
        userCache[user.login.lowercased()] = user
    }
}
