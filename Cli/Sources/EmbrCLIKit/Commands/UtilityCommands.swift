import Foundation
import EmbrCore

enum UtilityCommands {
    static let specs: [CommandSpec] = [
        configPath,
        configShow,
        commands,
        completion,
        doctor
    ]

    static let configPath = CommandSpec(
        ["config", "path"],
        summary: "Print the credentials file path.",
        examples: ["embr config path"],
        needsAuth: false
    ) { _, context in
        let snapshot = await context.authService.configSnapshot()
        return CommandResult(ConfigPathView(path: snapshot.path, exists: snapshot.exists, permissions: snapshot.permissions))
    }

    static let configShow = CommandSpec(
        ["config", "show"],
        summary: "Show profiles, config path and environment overrides (never secrets).",
        examples: ["embr config show --json"],
        needsAuth: false
    ) { _, context in
        return CommandResult(await context.authService.configSnapshot())
    }

    static let commands = CommandSpec(
        ["commands"],
        summary: "Print the machine-readable command catalog.",
        positionals: [PositionalSpec("group", "Limit to a group, e.g. chat emotes.", required: false, variadic: true)],
        examples: ["embr commands --json", "embr commands chat --json"],
        needsAuth: false
    ) { invocation, context in
        let filter = invocation.positionals.isEmpty ? nil : invocation.positionals
        return CommandResult(Catalog.build(CommandCatalog.registry, groupFilter: filter))
    }

    static let completion = CommandSpec(
        ["completion"],
        summary: "Print a shell completion script.",
        positionals: [PositionalSpec("shell", "bash, zsh or fish.")],
        examples: ["embr completion zsh > ~/.zsh/completions/_embr"],
        needsAuth: false
    ) { invocation, context in
        let shell = try invocation.require(0, "shell").lowercased()
        let script: String
        switch shell {
        case "bash": script = Completion.bash(CommandCatalog.registry)
        case "zsh": script = Completion.zsh(CommandCatalog.registry)
        case "fish": script = Completion.fish(CommandCatalog.registry)
        default:
            throw CLIError.usage("Unknown shell `\(shell)`.", hint: "Use bash, zsh or fish.")
        }
        if context.renderer.options.mode == .auto || context.renderer.options.mode == .table {
            context.renderer.writeText(script)
            return CommandResult(CompletionView(shell: shell, script: script), silent: true)
        }
        return CommandResult(CompletionView(shell: shell, script: script))
    }

    static let doctor = CommandSpec(
        ["doctor"],
        summary: "Check the install, credentials, token and Twitch reachability.",
        options: [.flag("network", "Also ping Helix (needs a token).")],
        examples: ["embr doctor --json", "embr doctor --network"],
        needsAuth: false
    ) { invocation, context in
        var checks: [DoctorCheck] = []
        checks.append(DoctorCheck(
            name: "binary",
            status: "ok",
            detail: "\(EmbrCLIVersion.full) on \(platform())"
        ))
        let snapshot = await context.authService.configSnapshot()
        if snapshot.exists {
            let permissions = snapshot.permissions ?? 0
            checks.append(DoctorCheck(
                name: "config",
                status: permissions == 0o600 ? "ok" : "warn",
                detail: "\(snapshot.path) mode \(String(permissions, radix: 8)), \(snapshot.profiles.count) profile(s)"
            ))
        } else {
            checks.append(DoctorCheck(name: "config", status: "warn", detail: "No credentials file at \(snapshot.path)"))
        }
        if let auth = try? await context.authService.current() {
            do {
                let identity = try await context.authService.identity(auth)
                checks.append(DoctorCheck(
                    name: "auth",
                    status: "ok",
                    detail: "\(identity.login) (\(identity.userID)), \(identity.scopes.count) scopes, expires in \(identity.expiresIn)s"
                ))
            } catch {
                checks.append(DoctorCheck(name: "auth", status: "fail", detail: "Token rejected: \((error as? CLIError)?.message ?? String(describing: error))"))
            }
        } else {
            checks.append(DoctorCheck(name: "auth", status: "warn", detail: "Not signed in; run `embr auth login`"))
        }
        if invocation.has("network") {
            do {
                let auth = try await context.authService.current()
                let factory = HelixRequestFactory(clientID: auth.clientID)
                let response = try await context.send(factory.topStreams(first: 1, token: auth.accessToken))
                checks.append(DoctorCheck(name: "helix", status: "ok", detail: "HTTP \(response.status)"))
            } catch {
                checks.append(DoctorCheck(name: "helix", status: "fail", detail: "\((error as? CLIError)?.message ?? String(describing: error))"))
            }
        }
        let failed = checks.contains { $0.status == "fail" }
        return CommandResult(DoctorView(ok: !failed, checks: checks))
    }

    private static func platform() -> String {
        #if os(macOS)
        return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #elseif os(Linux)
        return "Linux \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        return "unknown platform"
        #endif
    }
}

private struct ConfigPathView: Encodable {
    let path: String
    let exists: Bool
    let permissions: Int?
}

private struct CompletionView: Encodable {
    let shell: String
    let script: String
}

private struct DoctorView: Encodable {
    let ok: Bool
    let checks: [DoctorCheck]
}

private struct DoctorCheck: Encodable {
    let name: String
    let status: String
    let detail: String
}

enum Completion {
    static func bash(_ registry: CommandRegistry) -> String {
        var lines: [String] = []
        lines.append("# embr bash completion")
        lines.append("_embr_complete() {")
        lines.append("  local cur prev")
        lines.append("  cur=\"${COMP_WORDS[COMP_CWORD]}\"")
        lines.append("  prev=\"${COMP_WORDS[COMP_CWORD-1]}\"")
        lines.append("  local top=\"\(registry.groups.filter { $0.path.count == 1 }.map { $0.path[0] }.sorted().joined(separator: " ")) \(registry.commands.filter { $0.path.count == 1 }.map { $0.path[0] }.sorted().joined(separator: " "))\"")
        lines.append("  case \"${COMP_WORDS[1]}\" in")
        for group in registry.groups where group.path.count >= 1 {
            let path = group.path.joined(separator: " ")
            let children = registry.children(of: group.path).map(\.name).joined(separator: " ")
            guard !children.isEmpty else { continue }
            lines.append("    \(group.path[0])) COMPREPLY=( $(compgen -W \"\(children)\" -- \"$cur\") ); return ;;")
            if group.path.count > 1 {
                lines.append("    # \(path)")
            }
        }
        lines.append("  esac")
        lines.append("  COMPREPLY=( $(compgen -W \"$top\" -- \"$cur\") )")
        lines.append("}")
        lines.append("complete -F _embr_complete embr")
        return lines.joined(separator: "\n") + "\n"
    }

    static func zsh(_ registry: CommandRegistry) -> String {
        let top = registry.groups.filter { $0.path.count == 1 }.map { $0.path[0] }.sorted()
            + registry.commands.filter { $0.path.count == 1 }.map { $0.path[0] }.sorted()
        return """
        #compdef embr
        _embr() {
          local -a commands
          commands=(\(top.map { "'\($0)'" }.joined(separator: " ")))
          _describe 'command' commands
        }
        compdef _embr embr
        """ + "\n"
    }

    static func fish(_ registry: CommandRegistry) -> String {
        var lines: [String] = ["# embr fish completion"]
        for group in registry.groups.filter({ $0.path.count == 1 }) {
            lines.append("complete -c embr -n '__fish_use_subcommand' -a '\(group.path[0])' -d '\(escape(group.summary))'")
            for child in registry.children(of: group.path) where child.isGroup == false {
                let path = group.path + [child.name]
                lines.append("complete -c embr -n '__fish_seen_subcommand_from \(group.path[0])' -a '\(child.name)' -d '\(escape(child.summary))'")
                _ = path
            }
        }
        for command in registry.commands where command.path.count == 1 {
            lines.append("complete -c embr -n '__fish_use_subcommand' -a '\(command.path[0])' -d '\(escape(command.summary))'")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }
}
