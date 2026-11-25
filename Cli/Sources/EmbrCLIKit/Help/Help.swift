import Foundation

public enum Help {
    public static let topics = [
        "auth": "How sign-in, refresh and scope presets work.",
        "output": "JSON envelope, tables, NDJSON, --raw and streaming.",
        "scopes": "Every scope the CLI uses and which commands need it.",
        "agents": "The contract for agent callers.",
        "exit-codes": "What each exit code means.",
        "exclusions": "What Embr does that the CLI deliberately does not."
    ]

    public static func text(_ topic: String) -> String? {
        HelpTopics.text(topic)
    }

    public static func root(_ registry: CommandRegistry) -> String {
        var lines: [String] = []
        lines.append("\(EmbrCLIVersion.name) — Twitch from the terminal, built on EmbrCore.")
        lines.append("")
        lines.append("Usage:")
        lines.append("  embr <group> <command> [arguments] [options]")
        lines.append("  embr help <topic>")
        lines.append("")
        lines.append("Groups:")
        for group in registry.groups where group.path.count == 1 {
            lines.append("  \(pad(group.path[0], 12))\(group.summary)")
        }
        lines.append("")
        lines.append("Commands without a group:")
        for command in registry.commands where command.path.count == 1 {
            lines.append("  \(pad(command.name, 12))\(command.summary)")
        }
        lines.append("")
        lines.append("Global options:")
        for option in GlobalOptions.specs where !option.hidden && option.name != "help" {
            lines.append(optionLine(option))
        }
        lines.append("")
        lines.append("Environment:")
        lines.append("  EMBR_CLIENT_ID or TWITCH_CLIENT_ID   Twitch client id.")
        lines.append("  EMBR_ACCESS_TOKEN or TWITCH_ACCESS_TOKEN")
        lines.append("  EMBR_REFRESH_TOKEN                   Refresh token for unattended runs.")
        lines.append("  EMBR_CLIENT_SECRET                   Only for auth app-token.")
        lines.append("  EMBR_PROFILE                         Credential profile (default: default).")
        lines.append("  NO_COLOR                             Disable colour.")
        lines.append("")
        lines.append("Exit codes: 0 ok, 2 usage, 3 auth, 4 not found, 5 rate limited, 6 network, 7 server, 8 decode.")
        lines.append("")
        lines.append("Examples:")
        lines.append("  embr auth login")
        lines.append("  embr streams top --first 10")
        lines.append("  embr chat watch xqc --json --limit 20")
        lines.append("")
        lines.append("Topics: auth, output, scopes, agents, exit-codes, exclusions.")
        lines.append("For agents: `embr commands --json`, `embr help agents`, and `--json` on every command.")
        return lines.joined(separator: "\n")
    }

    public static func group(_ group: GroupSpec, registry: CommandRegistry) -> String {
        var lines: [String] = []
        lines.append("embr \(group.path.joined(separator: " ")) — \(group.summary)")
        if !group.details.isEmpty {
            lines.append("")
            lines.append(group.details)
        }
        lines.append("")
        lines.append("Usage:")
        lines.append("  embr \(group.path.joined(separator: " ")) <command> [options]")
        lines.append("")
        lines.append("Commands:")
        for child in registry.children(of: group.path) {
            let suffix = child.isGroup ? " (group)" : ""
            lines.append("  \(pad(child.name, 16))\(child.summary)\(suffix)")
        }
        lines.append("")
        lines.append("Run `embr \(group.path.joined(separator: " ")) <command> --help` for one command.")
        return lines.joined(separator: "\n")
    }

    public static func command(_ command: CommandSpec) -> String {
        var lines: [String] = []
        lines.append("embr \(command.name)")
        lines.append("")
        lines.append(command.summary)
        if !command.details.isEmpty {
            lines.append("")
            lines.append(command.details)
        }
        lines.append("")
        lines.append("Usage:")
        lines.append("  embr \(usage(command))")
        if !command.positionals.isEmpty {
            lines.append("")
            lines.append("Arguments:")
            for positional in command.positionals {
                let suffix = positional.variadic ? "…" : ""
                lines.append("  \(pad(positional.name + suffix, 18))\(positional.help)")
            }
        }
        if !command.options.isEmpty {
            lines.append("")
            lines.append("Options:")
            for option in command.options where !option.hidden {
                lines.append(optionLine(option))
            }
        }
        lines.append("")
        lines.append("Global options:")
        for option in GlobalOptions.specs where !option.hidden && option.name != "help" {
            lines.append(optionLine(option))
        }
        if !command.scopes.isEmpty {
            lines.append("")
            lines.append("Requires scopes: \(command.scopes.joined(separator: ", "))")
        }
        if command.mutating {
            lines.append("")
            lines.append("Mutating. Use --dry-run to print the request without sending it.")
        }
        if !command.examples.isEmpty {
            lines.append("")
            lines.append("Examples:")
            for example in command.examples {
                lines.append("  \(example)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func usage(_ command: CommandSpec) -> String {
        var parts = [command.name]
        for positional in command.positionals {
            let name = positional.variadic ? "<\(positional.name)…>" : "<\(positional.name)>"
            parts.append(positional.required ? name : "[\(name)]")
        }
        parts.append("[options]")
        return parts.joined(separator: " ")
    }

    private static func optionLine(_ option: OptionSpec) -> String {
        var label = "--\(option.name)"
        if let placeholder = option.placeholder, option.kind != .flag {
            label += " \(placeholder)"
        }
        var help = option.help
        if let defaultValue = option.defaultValue {
            help += " (default: \(defaultValue))"
        }
        if let range = option.range {
            help += " (\(range.lowerBound)…\(range.upperBound))"
        }
        if option.required {
            help += " [required]"
        }
        return "  \(pad(label, 30))\(help)"
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value + " " : value.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

public struct Catalog: Encodable, Sendable {
    public let version: String
    public let groups: [Group]
    public let commands: [Command]
    public let globalOptions: [Option]

    public struct Group: Encodable, Sendable {
        public let name: String
        public let summary: String
        public let details: String
    }

    public struct Command: Encodable, Sendable {
        public let name: String
        public let summary: String
        public let details: String
        public let usage: String
        public let arguments: [Argument]
        public let options: [Option]
        public let requiredScopes: [String]
        public let mutating: Bool
        public let examples: [String]
    }

    public struct Argument: Encodable, Sendable {
        public let name: String
        public let help: String
        public let required: Bool
        public let variadic: Bool
    }

    public struct Option: Encodable, Sendable {
        public let name: String
        public let kind: String
        public let help: String
        public let placeholder: String?
        public let defaultValue: String?
        public let required: Bool
        public let range: [Int]?
        public let choices: [String]?
    }

    public static func build(_ registry: CommandRegistry, groupFilter: [String]? = nil) -> Catalog {
        let groups = registry.groups
            .filter { group in
                guard let groupFilter else { return true }
                return group.path.starts(with: groupFilter)
            }
            .map { Group(name: $0.path.joined(separator: " "), summary: $0.summary, details: $0.details) }
        let commands = registry.commands
            .filter { command in
                guard let groupFilter else { return true }
                return command.path.starts(with: groupFilter)
            }
            .map { command in
                Command(
                    name: command.name,
                    summary: command.summary,
                    details: command.details,
                    usage: Help.usage(command),
                    arguments: command.positionals.map {
                        Argument(name: $0.name, help: $0.help, required: $0.required, variadic: $0.variadic)
                    },
                    options: command.options.map(option),
                    requiredScopes: command.scopes,
                    mutating: command.mutating,
                    examples: command.examples
                )
            }
        return Catalog(
            version: EmbrCLIVersion.version,
            groups: groups,
            commands: commands,
            globalOptions: GlobalOptions.specs.filter { !$0.hidden }.map(option)
        )
    }

    private static func option(_ option: OptionSpec) -> Option {
        Option(
            name: option.name,
            kind: option.kind.rawValue,
            help: option.help,
            placeholder: option.placeholder,
            defaultValue: option.defaultValue,
            required: option.required,
            range: option.range.map { [$0.lowerBound, $0.upperBound] },
            choices: option.choices
        )
    }
}
