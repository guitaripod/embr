import Foundation
import EmbrCore

enum AuthCommands {
    static let specs: [CommandSpec] = [
        login,
        poll,
        status,
        refresh,
        logout,
        appToken
    ]

    static let login = CommandSpec(
        ["auth", "login"],
        summary: "Sign in with Twitch's device code flow and store the tokens.",
        details: """
        Prints a code and a twitch.tv/activate link, then polls until the code is approved or expires.
        Tokens are written to the embr config file (mode 0600) under --profile. Run with --no-wait
        to get the code as JSON and poll from another process with `embr auth poll`.
        """,
        options: [
            .value("scopes", "LIST", "Scope presets or explicit scopes, comma separated.", defaultValue: "all"),
            .flag("no-wait", "Print the device code and exit instead of polling.")
        ],
        examples: [
            "embr auth login",
            "embr auth login --scopes chat,mod",
            "embr auth login --no-wait --json"
        ],
        needsAuth: false
    ) { invocation, context in
        let service = context.authService
        guard let clientID = await service.configuredClientID() else {
            throw CLIError.auth(
                "No Twitch client id is configured.",
                hint: "Pass --client-id, set EMBR_CLIENT_ID, or store one with `embr auth login --client-id <id>`."
            )
        }
        let scopes = try ScopePreset.expand(invocation.value("scopes") ?? "all")
        let start = try await service.startDevice(clientID: clientID, scopes: scopes)

        if invocation.has("no-wait") {
            return CommandResult(
                DeviceView(
                    profile: context.profile,
                    clientID: clientID,
                    userCode: start.userCode,
                    verificationURI: start.verificationURI.absoluteString,
                    deviceCode: start.deviceCode,
                    interval: start.interval,
                    expiresIn: start.expiresIn
                )
            )
        }

        context.renderer.note("Open \(start.verificationURI.absoluteString) and enter \(DeviceAuthorization.displayCode(start.userCode)).")
        let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        var interval = start.pollInterval
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            let result = try await service.pollDevice(clientID: clientID, deviceCode: start.deviceCode, scopes: scopes)
            switch result {
            case .authorized(let token):
                let auth = try await service.accept(token: token, clientID: clientID, requestedScopes: scopes)
                return CommandResult(LoginView(auth: auth))
            case .pending:
                continue
            case .slowDown:
                interval += 5
            case .expired:
                throw CLIError.auth("The device code expired.", hint: "Run `embr auth login` again.")
            case .denied:
                throw CLIError.auth("The sign-in was denied on Twitch.")
            case .failed(let message):
                throw CLIError.auth("Twitch rejected the device code: \(message)")
            }
        }
        throw CLIError.auth("The device code expired before it was approved.", hint: "Run `embr auth login` again.")
    }

    static let poll = CommandSpec(
        ["auth", "poll"],
        summary: "Poll a device code once (for scripted sign-in).",
        options: [
            .value("device-code", "CODE", "The device code from `auth login --no-wait`.", required: true),
            .value("scopes", "LIST", "The same scopes used to start the device login.", defaultValue: "all")
        ],
        examples: [
            "embr auth poll --device-code <code> --json"
        ],
        needsAuth: false
    ) { invocation, context in
        let service = context.authService
        guard let clientID = await service.configuredClientID() else {
            throw CLIError.auth("No Twitch client id is configured.", hint: "Pass --client-id or set EMBR_CLIENT_ID.")
        }
        let scopes = try ScopePreset.expand(invocation.value("scopes") ?? "all")
        let result = try await service.pollDevice(
            clientID: clientID,
            deviceCode: invocation.value("device-code") ?? "",
            scopes: scopes
        )
        switch result {
        case .authorized(let token):
            let auth = try await service.accept(token: token, clientID: clientID, requestedScopes: scopes)
            return CommandResult(PollView(status: "authorized", auth: auth))
        case .pending:
            return CommandResult(PollView(status: "pending", auth: nil))
        case .slowDown:
            return CommandResult(PollView(status: "slow_down", auth: nil))
        case .expired:
            throw CLIError.auth("The device code expired.", hint: "Run `embr auth login` again.")
        case .denied:
            throw CLIError.auth("The sign-in was denied on Twitch.")
        case .failed(let message):
            throw CLIError.auth("Twitch rejected the device code: \(message)")
        }
    }

    static let status = CommandSpec(
        ["auth", "status"],
        summary: "Show the signed-in identity, scopes, expiry and config path.",
        details: "Never prints the access or refresh token. With no token it reports authenticated:false.",
        examples: [
            "embr auth status",
            "embr auth status --json"
        ],
        needsAuth: false
    ) { _, context in
        let status = await context.authService.status()
        var authenticated = status.source != nil
        var login = status.login
        var userID = status.userID
        var scopes = status.scopes
        var expiresAt = status.expiresAt
        var reason: String?

        if authenticated, let auth = try? await context.authService.current() {
            do {
                let identity = try await context.authService.identity(auth)
                login = identity.login
                userID = identity.userID
                scopes = identity.scopes
                expiresAt = Date().addingTimeInterval(TimeInterval(identity.expiresIn))
            } catch {
                authenticated = false
                reason = (error as? CLIError)?.message ?? String(describing: error)
            }
        } else if authenticated {
            authenticated = false
            reason = "The token could not be resolved."
        }

        return CommandResult(StatusView(
            authenticated: authenticated,
            profile: status.profile,
            source: status.source,
            login: login,
            userID: userID,
            scopes: scopes,
            expiresAt: expiresAt,
            configPath: status.configPath,
            configPermissions: status.configPermissions,
            reason: reason
        ))
    }

    static let refresh = CommandSpec(
        ["auth", "refresh"],
        summary: "Refresh the access token now.",
        examples: ["embr auth refresh --json"],
        scopes: ["any refresh token"],
        needsAuth: false
    ) { _, context in
        let service = context.authService
        let auth: AuthContext
        do {
            auth = try await service.current()
        } catch let error as CLIError where error.kind == .auth {
            throw CLIError.auth("No token to refresh.", hint: "Run `embr auth login`.")
        }
        let refreshed = try await service.refresh(auth)
        return CommandResult(RefreshView(
            profile: refreshed.profile,
            scopes: refreshed.scopes,
            expiresAt: refreshed.expiresAt
        ))
    }

    static let logout = CommandSpec(
        ["auth", "logout"],
        summary: "Revoke the current token and remove the profile's credentials.",
        options: [
            .flag("keep-token", "Remove the local credentials without revoking the token at Twitch.")
        ],
        examples: ["embr auth logout"],
        scopes: ["any user token"],
        mutating: true,
        needsAuth: false
    ) { invocation, context in
        let service = context.authService
        if !invocation.has("keep-token"), let auth = try? await service.current() {
            try? await service.revoke(auth)
        }
        try await service.clear()
        return CommandResult(LoggedOutView(profile: context.profile, cleared: true))
    }

    static let appToken = CommandSpec(
        ["auth", "app-token"],
        summary: "Get an app access token from the client credentials grant.",
        details: """
        Reads the client secret from the environment variable named by --client-secret-env
        (default EMBR_CLIENT_SECRET) or from stdin with --client-secret-stdin, never from argv.
        The token is printed once and is not stored; use --write to put it in a 0600 file instead.
        """,
        options: [
            .value("client-secret-env", "VAR", "Environment variable holding the client secret.", defaultValue: "EMBR_CLIENT_SECRET"),
            .flag("client-secret-stdin", "Read the client secret from stdin."),
            .value("scopes", "LIST", "Scopes the app already has delegated.", defaultValue: ""),
            .value("write", "FILE", "Write the token to this file with mode 0600 instead of stdout.")
        ],
        examples: [
            "EMBR_CLIENT_ID=… EMBR_CLIENT_SECRET=… embr auth app-token --json",
            "embr auth app-token --client-secret-stdin --write ~/.config/embr/app-token"
        ],
        needsAuth: false
    ) { invocation, context in
        let service = context.authService
        guard let clientID = await service.configuredClientID() else {
            throw CLIError.auth("No Twitch client id is configured.", hint: "Pass --client-id or set EMBR_CLIENT_ID.")
        }
        let secret: String
        if invocation.has("client-secret-stdin") {
            guard !context.options.noInput else {
                throw CLIError.usage("Refusing to read stdin because --no-input was passed.")
            }
            secret = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let name = invocation.value("client-secret-env") ?? "EMBR_CLIENT_SECRET"
            guard let value = context.environment[name], !value.isEmpty else {
                throw CLIError.auth(
                    "The client secret is not available.",
                    hint: "Set \(name) or pass --client-secret-stdin."
                )
            }
            secret = value
        }
        guard !secret.isEmpty else {
            throw CLIError.auth("The client secret is empty.")
        }
        let scopes = try ScopePreset.expand(invocation.value("scopes") ?? "")
        let token = try await service.appToken(clientID: clientID, clientSecret: secret, scopes: scopes)

        if let path = invocation.value("write") {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(token.accessToken.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return CommandResult(AppTokenView(
                accessToken: nil,
                expiresIn: token.expiresIn,
                tokenType: token.tokenType,
                scope: token.scope,
                written: url.path
            ))
        }

        context.renderer.note("This prints a secret. Do not log it.")
        return CommandResult(AppTokenView(
            accessToken: token.accessToken,
            expiresIn: token.expiresIn,
            tokenType: token.tokenType,
            scope: token.scope,
            written: nil
        ))
    }
}

private struct DeviceView: Encodable {
    let profile: String
    let clientID: String
    let userCode: String
    let verificationURI: String
    let deviceCode: String
    let interval: Int
    let expiresIn: Int
}

private struct LoginView: Encodable {
    let profile: String
    let login: String?
    let userID: String?
    let scopes: [String]
    let expiresAt: Date?

    init(auth: AuthContext) {
        profile = auth.profile
        login = auth.login
        userID = auth.userID
        scopes = auth.scopes
        expiresAt = auth.expiresAt
    }
}

private struct PollView: Encodable {
    let status: String
    let login: String?
    let userID: String?
    let scopes: [String]?
    let expiresAt: Date?

    init(status: String, auth: AuthContext?) {
        self.status = status
        login = auth?.login
        userID = auth?.userID
        scopes = auth?.scopes
        expiresAt = auth?.expiresAt
    }
}

private struct StatusView: Encodable {
    let authenticated: Bool
    let profile: String
    let source: String?
    let login: String?
    let userID: String?
    let scopes: [String]
    let expiresAt: Date?
    let configPath: String
    let configPermissions: Int?
    let reason: String?
}

private struct RefreshView: Encodable {
    let profile: String
    let scopes: [String]
    let expiresAt: Date?
}

private struct LoggedOutView: Encodable {
    let profile: String
    let cleared: Bool
}

private struct AppTokenView: Encodable {
    let accessToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: [String]
    let written: String?
}
