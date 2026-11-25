import Foundation
import EmbrCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum EmbrCLI {
    public static func main() async {
        let code = await run(arguments: Swift.CommandLine.arguments)
        exit(code)
    }

    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        transport: HTTPTransport? = nil,
        isTTY: Bool? = nil,
        stdout: @escaping @Sendable (Data) -> Void = { FileHandle.standardOutput.write($0) },
        stderr: @escaping @Sendable (Data) -> Void = { FileHandle.standardError.write($0) }
    ) async -> Int32 {
        let tty = isTTY ?? (isatty(STDOUT_FILENO) != 0)
        let argv = Array(arguments.dropFirst())
        let registry = CommandCatalog.registry
        let initialOptions = OutputOptions(
            mode: .auto,
            raw: false,
            quiet: false,
            color: tty && environment["NO_COLOR"] == nil,
            isTTY: tty
        )
        let initialRenderer = Renderer(options: initialOptions, stdout: stdout, stderr: stderr)

        if argv.isEmpty {
            initialRenderer.writeText(Help.root(registry) + "\n")
            return 0
        }

        if argv[0] == "help" {
            return writeHelp(topicOrPath: Array(argv.dropFirst()), registry: registry, renderer: initialRenderer)
        }

        let line: CommandLine
        do {
            line = try registry.parse(argv)
        } catch let error as CLIError {
            initialRenderer.writeError(error, command: "embr")
            return error.exitCode
        } catch {
            initialRenderer.writeError(CLIError(.internalError, String(describing: error)), command: "embr")
            return 1
        }

        if line.versionRequested {
            if line.flags["json"] != nil {
                let options = OutputOptions(mode: .json, isTTY: tty)
                let renderer = Renderer(options: options, stdout: stdout, stderr: stderr)
                try? renderer.write(
                    CommandResult(VersionView(name: EmbrCLIVersion.name, version: EmbrCLIVersion.version)),
                    command: "version"
                )
            } else {
                initialRenderer.writeText(EmbrCLIVersion.full + "\n")
            }
            return 0
        }

        if line.positionals.isEmpty {
            initialRenderer.writeText(Help.root(registry) + "\n")
            return 0
        }

        let resolution: CommandRegistry.Resolution
        do {
            resolution = try registry.resolve(line.positionals)
        } catch let error as CLIError {
            initialRenderer.writeError(error, command: "embr")
            return error.exitCode
        } catch {
            initialRenderer.writeError(CLIError(.internalError, String(describing: error)), command: "embr")
            return 1
        }

        switch resolution {
        case .root:
            initialRenderer.writeText(Help.root(registry) + "\n")
            return 0
        case .group(let group):
            initialRenderer.writeText(Help.group(group, registry: registry) + "\n")
            return 0
        case .command(let spec, let remaining):
            if line.helpRequested {
                initialRenderer.writeText(Help.command(spec) + "\n")
                return 0
            }
            do {
                try registry.validate(spec, flags: line.flags, positionals: remaining)
            } catch let error as CLIError {
                initialRenderer.writeError(error, command: spec.name)
                return error.exitCode
            } catch {
                initialRenderer.writeError(CLIError(.internalError, String(describing: error)), command: spec.name)
                return 1
            }
            return await execute(
                spec: spec,
                invocation: Invocation(spec: spec, positionals: remaining, flags: line.flags),
                environment: environment,
                transport: transport,
                tty: tty,
                stdout: stdout,
                stderr: stderr
            )
        }
    }

    private static func execute(
        spec: CommandSpec,
        invocation: Invocation,
        environment: [String: String],
        transport: HTTPTransport?,
        tty: Bool,
        stdout: @escaping @Sendable (Data) -> Void,
        stderr: @escaping @Sendable (Data) -> Void
    ) async -> Int32 {
        let options = outputOptions(invocation: invocation, environment: environment, tty: tty)
        let renderer = Renderer(options: options, stdout: stdout, stderr: stderr)
        let timeout = TimeInterval(invocation.int("timeout") ?? 20)
        let retries = invocation.int("retries") ?? 2
        let dryRun = invocation.has("dry-run")
        let verbose = invocation.has("verbose")
        let trace = invocation.has("trace")
        let client = APIClient(
            transport: transport ?? URLSessionTransport(timeout: timeout),
            retries: retries,
            dryRun: dryRun,
            verbose: verbose || trace,
            trace: trace,
            log: { renderer.note($0) }
        )
        let store = CredentialsStore(environment: environment)
        let service = AuthService(
            store: store,
            environment: environment,
            client: client,
            profile: invocation.value("profile") ?? environment["EMBR_PROFILE"] ?? "default",
            clientIDOverride: invocation.value("client-id"),
            tokenOverride: invocation.value("token"),
            canRefresh: !dryRun
        )
        let profile = invocation.value("profile") ?? environment["EMBR_PROFILE"] ?? "default"
        let runOptions = RunOptions(
            all: invocation.has("all"),
            first: invocation.int("first"),
            after: invocation.value("after"),
            maxPages: invocation.int("max-pages") ?? 50,
            raw: invocation.has("raw"),
            dryRun: dryRun,
            noInput: invocation.has("no-input")
        )

        do {
            var auth: AuthContext?
            if spec.needsAuth {
                auth = try await service.current()
            }
            let context = RunContext(
                client: client,
                auth: auth,
                authService: service,
                renderer: renderer,
                options: runOptions,
                environment: environment,
                profile: profile
            )
            let result = try await spec.run(invocation, context)
            try renderer.write(result, command: spec.name)
            return 0
        } catch let error as DryRun {
            renderDryRun(error.request, command: spec.name, renderer: renderer)
            return 0
        } catch let error as CLIError {
            renderer.writeError(error, command: spec.name)
            return error.exitCode
        } catch is CancellationError {
            return 130
        } catch {
            renderer.writeError(CLIError(.internalError, String(describing: error)), command: spec.name)
            return 1
        }
    }

    private static func outputOptions(invocation: Invocation, environment: [String: String], tty: Bool) -> OutputOptions {
        let mode: OutputOptions.Mode
        if invocation.has("json") {
            mode = .json
        } else if invocation.has("ndjson") {
            mode = .ndjson
        } else if invocation.has("table") {
            mode = .table
        } else {
            mode = .auto
        }
        return OutputOptions(
            mode: mode,
            raw: invocation.has("raw"),
            quiet: invocation.has("quiet"),
            color: !invocation.has("no-color") && environment["NO_COLOR"] == nil,
            isTTY: tty
        )
    }

    private static func writeHelp(
        topicOrPath: [String],
        registry: CommandRegistry,
        renderer: Renderer
    ) -> Int32 {
        guard let first = topicOrPath.first else {
            renderer.writeText(Help.root(registry) + "\n")
            return 0
        }
        if topicOrPath.count == 1, let topic = Help.text(first) {
            renderer.writeText(topic + "\n")
            return 0
        }
        do {
            switch try registry.resolve(topicOrPath) {
            case .root:
                renderer.writeText(Help.root(registry) + "\n")
            case .group(let group):
                renderer.writeText(Help.group(group, registry: registry) + "\n")
            case .command(let spec, _):
                renderer.writeText(Help.command(spec) + "\n")
            }
            return 0
        } catch let error as CLIError {
            renderer.writeError(error, command: "help")
            return error.exitCode
        } catch {
            renderer.writeError(CLIError(.internalError, String(describing: error)), command: "help")
            return 1
        }
    }

    private static func renderDryRun(_ request: HTTPRequest, command: String, renderer: Renderer) {
        var headers = request.headers
        for name in headers.keys where isSecretName(name) {
            headers[name] = "REDACTED"
        }
        let body = request.body.flatMap(redactedBody)
        let note = dryRunNote(request, command: command)
        let view = DryRunView(
            dryRun: true,
            method: request.method.rawValue,
            url: redactedURL(request.url),
            headers: headers,
            body: body,
            note: note
        )
        try? renderer.write(CommandResult(view), command: "dry-run")
    }

    private static func dryRunNote(_ request: HTTPRequest, command: String) -> String? {
        if request.url.host == "id.twitch.tv", request.url.path == "/oauth2/validate", command != "auth status" {
            return "This only validates the token to learn your user id. Pass numeric ids, or --as <moderator-id>, to reach the final request."
        }
        if request.method == .get, request.url.path.hasSuffix("/users"), command != "users get",
           request.url.query?.contains("login=") == true {
            return "This is the login lookup, not the final request. Pass numeric ids to see the final request."
        }
        return nil
    }

    private static func redactedBody(_ data: Data) -> JSONValue? {
        if let json = try? JSONValue.decode(data) {
            return redact(json)
        }
        let raw = String(decoding: data, as: UTF8.self)
        guard raw.contains("="), !raw.contains("\n") else {
            return .string(raw)
        }
        let fields = raw.split(separator: "&").map { field -> String in
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return String(field) }
            return isSecretName(parts[0]) ? "\(parts[0])=REDACTED" : String(field)
        }
        return .string(fields.joined(separator: "&"))
    }

    private static func redact(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            var redacted: [String: JSONValue] = [:]
            for (key, value) in object {
                redacted[key] = isSecretName(key) ? .string("REDACTED") : redact(value)
            }
            return .object(redacted)
        case .array(let array):
            return .array(array.map(redact))
        default:
            return value
        }
    }

    private static func isSecretName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("authorization")
            || lowered.contains("secret")
            || lowered.contains("token")
            || lowered == "code"
            || lowered.hasSuffix("_code")
    }

    private static func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            isSecretName(item.name) ? URLQueryItem(name: item.name, value: "REDACTED") : item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}

private struct DryRunView: Encodable {
    let dryRun: Bool
    let method: String
    let url: String
    let headers: [String: String]
    let body: JSONValue?
    let note: String?
}

private struct VersionView: Encodable {
    let name: String
    let version: String
}
