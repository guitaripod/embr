import Foundation

public struct CommandLine: Sendable {
    public let flags: [String: [String]]
    public let positionals: [String]

    public init(flags: [String: [String]], positionals: [String]) {
        self.flags = flags
        self.positionals = positionals
    }

    public var helpRequested: Bool { flags["help"] != nil }
    public var versionRequested: Bool { flags["version"] != nil }
}

public struct CommandRegistry: Sendable {
    public enum Resolution: Sendable {
        case root
        case group(GroupSpec)
        case command(CommandSpec, remaining: [String])
    }

    public let groups: [GroupSpec]
    public let commands: [CommandSpec]
    public let globalOptions: [OptionSpec]
    private let optionKinds: [String: OptionSpec.Kind]

    public init(groups: [GroupSpec], commands: [CommandSpec], globalOptions: [OptionSpec] = GlobalOptions.specs) {
        self.groups = groups
        self.commands = commands
        self.globalOptions = globalOptions

        var kinds: [String: OptionSpec.Kind] = [:]
        for option in globalOptions + commands.flatMap(\.options) {
            if let existing = kinds[option.name] {
                let takesValue = { (kind: OptionSpec.Kind) in kind != .flag }
                if takesValue(existing) != takesValue(option.kind) {
                    preconditionFailure("Option --\(option.name) is declared both as a flag and as a value.")
                }
            } else {
                kinds[option.name] = option.kind
            }
        }
        optionKinds = kinds
    }

    public func resolve(_ positionals: [String]) throws -> Resolution {
        var path: [String] = []
        var index = 0
        while index < positionals.count {
            let candidate = path + [positionals[index]]
            if commands.contains(where: { $0.path == candidate }) {
                return .command(try command(at: candidate), remaining: Array(positionals[(index + 1)...]))
            }
            if groups.contains(where: { $0.path == candidate }) {
                path = candidate
                index += 1
                continue
            }
            if let group = groups.first(where: { $0.path == path }) {
                let children = childNames(of: group.path)
                throw CLIError.usage(
                    "Unknown subcommand `\(positionals[index])` for `\(path.joined(separator: " "))`.",
                    hint: children.isEmpty ? nil : "Available: \(children.joined(separator: ", "))."
                )
            }
            throw CLIError.usage(
                "Unknown command `\(candidate.joined(separator: " "))`.",
                hint: "Run `embr --help` to list commands."
            )
        }
        if let group = groups.first(where: { $0.path == path }) {
            return .group(group)
        }
        return .root
    }

    public func command(at path: [String]) throws -> CommandSpec {
        guard let command = commands.first(where: { $0.path == path }) else {
            throw CLIError.usage("Unknown command `\(path.joined(separator: " "))`.")
        }
        return command
    }

    public func group(at path: [String]) -> GroupSpec? {
        groups.first { $0.path == path }
    }

    public func childNames(of path: [String]) -> [String] {
        let prefix = path.count + 1
        var names = Set<String>()
        for group in groups where group.path.count == prefix && group.path.starts(with: path) {
            names.insert(group.path[prefix - 1])
        }
        for command in commands where command.path.count == prefix && command.path.starts(with: path) {
            names.insert(command.path[prefix - 1])
        }
        return names.sorted()
    }

    public func children(of path: [String]) -> [(name: String, summary: String, isGroup: Bool)] {
        let prefix = path.count + 1
        var result: [(String, String, Bool)] = []
        for group in groups where group.path.count == prefix && group.path.starts(with: path) {
            result.append((group.path[prefix - 1], group.summary, true))
        }
        for command in commands where command.path.count == prefix && command.path.starts(with: path) {
            result.append((command.path[prefix - 1], command.summary, false))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    public func option(named name: String) -> OptionSpec? {
        globalOptions.first { $0.name == name } ?? commands.lazy.flatMap(\.options).first { $0.name == name }
    }

    public func parse(_ argv: [String]) throws -> CommandLine {
        var flags: [String: [String]] = [:]
        var positionals: [String] = []
        var index = 0
        var optionsEnabled = true

        while index < argv.count {
            let token = argv[index]
            if optionsEnabled && token == "--" {
                optionsEnabled = false
                index += 1
                continue
            }
            if optionsEnabled && token == "-h" {
                flags["help", default: []].append("true")
                index += 1
                continue
            }
            if optionsEnabled && token.hasPrefix("--") {
                let stripped = String(token.dropFirst(2))
                let parts = stripped.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                guard let kind = optionKinds[name] else {
                    throw CLIError.usage("Unknown option `--\(name)`.", hint: "Run `embr --help`.")
                }
                if kind == .flag {
                    if parts.count > 1 {
                        throw CLIError.usage("`--\(name)` does not take a value.")
                    }
                    flags[name, default: []].append("true")
                    index += 1
                    continue
                }
                if parts.count > 1 {
                    flags[name, default: []].append(String(parts[1]))
                    index += 1
                    continue
                }
                guard index + 1 < argv.count else {
                    throw CLIError.usage("`--\(name)` needs a value.")
                }
                let value = argv[index + 1]
                if value.hasPrefix("--") {
                    throw CLIError.usage("`--\(name)` needs a value.")
                }
                flags[name, default: []].append(value)
                index += 2
                continue
            }
            positionals.append(token)
            index += 1
        }
        return CommandLine(flags: flags, positionals: positionals)
    }

    public func validate(_ command: CommandSpec, flags: [String: [String]], positionals: [String]) throws {
        let allowed = Set(globalOptions.map(\.name) + command.options.map(\.name))
        for name in flags.keys where !allowed.contains(name) {
            throw CLIError.usage("`--\(name)` is not an option of `\(command.name)`.", hint: "Run `embr \(command.name) --help`.")
        }
        for option in command.options + globalOptions where option.required {
            if flags[option.name] == nil {
                throw CLIError.usage("`--\(option.name)` is required for `\(command.name)`.")
            }
        }
        for option in command.options + globalOptions {
            guard let values = flags[option.name] else { continue }
            for value in values {
                if let choices = option.choices, !choices.contains(value) {
                    throw CLIError.usage("`--\(option.name)` must be one of: \(choices.joined(separator: ", ")).")
                }
                if let range = option.range, let number = Int(value), !range.contains(number) {
                    throw CLIError.usage("`--\(option.name)` must be between \(range.lowerBound) and \(range.upperBound).")
                }
                if option.range != nil && Int(value) == nil {
                    throw CLIError.usage("`--\(option.name)` must be a number.")
                }
            }
        }

        let requiredCount = command.positionals.filter(\.required).count
        if positionals.count < requiredCount {
            let missing = command.positionals[positionals.count...].first(where: \.required)?.name ?? "argument"
            throw CLIError.usage("Missing \(missing).", hint: "Run `embr \(command.name) --help`.")
        }
        let variadic = command.positionals.last?.variadic ?? false
        if !variadic && positionals.count > command.positionals.count {
            throw CLIError.usage("Too many arguments for `\(command.name)`.", hint: "Run `embr \(command.name) --help`.")
        }
        if let mode = conflictingMode(flags) {
            throw CLIError.usage("Use only one of --json, --table and --ndjson, not all with --\(mode).")
        }
    }

    private func conflictingMode(_ flags: [String: [String]]) -> String? {
        let modes = ["json", "table", "ndjson"].filter { flags[$0] != nil }
        return modes.count > 1 ? modes.last : nil
    }
}
