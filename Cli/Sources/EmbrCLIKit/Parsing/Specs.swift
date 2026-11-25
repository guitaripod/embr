import Foundation

public struct OptionSpec: Sendable {
    public enum Kind: String, Sendable {
        case flag
        case value
        case repeated
    }

    public let name: String
    public let kind: Kind
    public let help: String
    public let placeholder: String?
    public let defaultValue: String?
    public let required: Bool
    public let range: ClosedRange<Int>?
    public let choices: [String]?
    public let hidden: Bool

    public init(
        _ name: String,
        kind: Kind = .value,
        help: String,
        placeholder: String? = nil,
        defaultValue: String? = nil,
        required: Bool = false,
        range: ClosedRange<Int>? = nil,
        choices: [String]? = nil,
        hidden: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.help = help
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.required = required
        self.range = range
        self.choices = choices
        self.hidden = hidden
    }

    public static func flag(_ name: String, _ help: String, hidden: Bool = false) -> OptionSpec {
        OptionSpec(name, kind: .flag, help: help, hidden: hidden)
    }

    public static func value(
        _ name: String,
        _ placeholder: String,
        _ help: String,
        defaultValue: String? = nil,
        required: Bool = false,
        range: ClosedRange<Int>? = nil,
        choices: [String]? = nil
    ) -> OptionSpec {
        OptionSpec(
            name,
            kind: .value,
            help: help,
            placeholder: placeholder,
            defaultValue: defaultValue,
            required: required,
            range: range,
            choices: choices
        )
    }

    public static func repeated(
        _ name: String,
        _ placeholder: String,
        _ help: String,
        choices: [String]? = nil
    ) -> OptionSpec {
        OptionSpec(name, kind: .repeated, help: help, placeholder: placeholder, choices: choices)
    }
}

public struct PositionalSpec: Sendable {
    public let name: String
    public let help: String
    public let required: Bool
    public let variadic: Bool

    public init(_ name: String, _ help: String, required: Bool = true, variadic: Bool = false) {
        self.name = name
        self.help = help
        self.required = required
        self.variadic = variadic
    }
}

public struct GroupSpec: Sendable {
    public let path: [String]
    public let summary: String
    public let details: String

    public init(_ path: [String], summary: String, details: String = "") {
        self.path = path
        self.summary = summary
        self.details = details
    }
}

public struct CommandSpec: Sendable {
    public let path: [String]
    public let summary: String
    public let details: String
    public let options: [OptionSpec]
    public let positionals: [PositionalSpec]
    public let examples: [String]
    public let scopes: [String]
    public let mutating: Bool
    public let needsAuth: Bool
    public let run: @Sendable (Invocation, RunContext) async throws -> CommandResult

    public init(
        _ path: [String],
        summary: String,
        details: String = "",
        positionals: [PositionalSpec] = [],
        options: [OptionSpec] = [],
        examples: [String] = [],
        scopes: [String] = [],
        mutating: Bool = false,
        needsAuth: Bool = true,
        run: @escaping @Sendable (Invocation, RunContext) async throws -> CommandResult
    ) {
        self.path = path
        self.summary = summary
        self.details = details
        self.positionals = positionals
        self.options = options
        self.examples = examples
        self.scopes = scopes
        self.mutating = mutating
        self.needsAuth = needsAuth
        self.run = run
    }

    public var name: String { path.joined(separator: " ") }
}

public struct Invocation: Sendable {
    public let spec: CommandSpec
    public let positionals: [String]
    private let flags: [String: [String]]

    public init(spec: CommandSpec, positionals: [String], flags: [String: [String]]) {
        self.spec = spec
        self.positionals = positionals
        self.flags = flags
    }

    public func value(_ name: String) -> String? {
        flags[name]?.last
    }

    public func list(_ name: String) -> [String] {
        flags[name] ?? []
    }

    public func has(_ name: String) -> Bool {
        flags[name] != nil
    }

    public func int(_ name: String) -> Int? {
        value(name).flatMap(Int.init)
    }

    public func int(_ name: String, default fallback: Int) -> Int {
        int(name) ?? fallback
    }

    public func require(_ index: Int, _ name: String) throws -> String {
        guard index < positionals.count else {
            throw CLIError.usage("Missing \(name).", hint: "Run `embr \(spec.name) --help`.")
        }
        return positionals[index]
    }

    public func optional(_ index: Int) -> String? {
        index < positionals.count ? positionals[index] : nil
    }
}

public struct GlobalOptions: Sendable {
    public static let specs: [OptionSpec] = [
        .flag("json", "Machine-readable JSON envelope on stdout."),
        .flag("table", "Human-readable table for list commands."),
        .flag("ndjson", "One JSON object per line; streams use this by default."),
        .flag("raw", "Print Twitch's payload instead of the CLI's shape."),
        .flag("no-color", "Disable ANSI colour."),
        .flag("quiet", "Suppress notes on stderr."),
        .flag("verbose", "Log requests to stderr with secrets redacted."),
        .flag("dry-run", "Print the request that would be sent and exit."),
        .flag("all", "Follow pagination to the last page."),
        .value("first", "N", "Page size for list commands."),
        .value("after", "CURSOR", "Start after this pagination cursor."),
        .value("max-pages", "N", "Stop --all after this many pages.", defaultValue: "50"),
        .value("profile", "NAME", "Credential profile to use.", defaultValue: "default"),
        .value("client-id", "ID", "Twitch client id for this invocation."),
        .value("token", "TOKEN", "Access token for this invocation."),
        .value("timeout", "SECONDS", "Request timeout.", defaultValue: "20"),
        .value("retries", "N", "Retries for idempotent requests after 429/5xx.", defaultValue: "2"),
        .flag("help", "Show help for the command."),
        .flag("version", "Print the version."),
        .flag("no-input", "Never read stdin; fail instead."),
        .flag("trace", "Log response status and rate limits to stderr.")
    ]
}
