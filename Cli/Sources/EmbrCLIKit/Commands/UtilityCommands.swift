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
        return CommandResult(ConfigPathView(
            path: snapshot.path,
            exists: snapshot.exists,
            permissions: snapshot.permissions,
            mode: snapshot.permissions.map { String(format: "%03o", $0) }
        ))
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
        if let expiry = snapshot.profiles.first(where: { $0.name == snapshot.profile })?.expiresAt,
           expiry.timeIntervalSinceNow < 86_400 {
            let hours = max(Int(expiry.timeIntervalSinceNow / 3600), 0)
            let refresh = await context.authService.refreshStrategy()
            switch refresh {
            case "worker":
                checks.append(DoctorCheck(name: "token-refresh", status: "ok", detail: "Access token expires in \(hours)h; refreshes through Embr's worker."))
            case "secret":
                checks.append(DoctorCheck(name: "token-refresh", status: "ok", detail: "Access token expires in \(hours)h; refreshes with EMBR_CLIENT_SECRET."))
            default:
                checks.append(DoctorCheck(name: "token-refresh", status: "warn", detail: "Access token expires in \(hours)h; no refresh path, so run `embr auth login` when it lapses."))
            }
        }
        if let auth = try? await context.authService.current() {
            do {
                let identity = try await context.authService.identity(auth)
                let who = [identity.login, identity.userID].compactMap { $0 }.joined(separator: " / ")
                checks.append(DoctorCheck(
                    name: "auth",
                    status: "ok",
                    detail: "\(who.isEmpty ? "app token" : who), \(identity.scopes.count) scopes, expires in \(identity.expiresIn)s"
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
    let mode: String?
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
        lines.append("  local cur path word i")
        lines.append("  cur=\"${COMP_WORDS[COMP_CWORD]}\"")
        lines.append("  path=\"\"")
        lines.append("  for ((i=1; i<COMP_CWORD; i++)); do")
        lines.append("    word=\"${COMP_WORDS[i]}\"")
        lines.append("    case \"$word\" in --*) continue ;; esac")
        lines.append("    path=\"${path:+$path }$word\"")
        lines.append("  done")
        lines.append("  case \"$path\" in")
        lines.append("    \"\") COMPREPLY=( $(compgen -W \"\(topLevel(registry))\" -- \"$cur\") ) ;;")
        for group in groupsWithChildren(registry) {
            lines.append("    \"\(group.path.joined(separator: " "))\") COMPREPLY=( $(compgen -W \"\(names(of: group.path, registry))\" -- \"$cur\") ) ;;")
        }
        lines.append("    *) COMPREPLY=() ;;")
        lines.append("  esac")
        lines.append("  return 0")
        lines.append("}")
        lines.append("complete -F _embr_complete embr")
        return lines.joined(separator: "\n") + "\n"
    }

    static func zsh(_ registry: CommandRegistry) -> String {
        var lines: [String] = []
        lines.append("#compdef embr")
        lines.append("_embr() {")
        lines.append("  local path=\"${(j: :)words[2,CURRENT-1]}\"")
        lines.append("  local -a items")
        lines.append("  case \"$path\" in")
        lines.append("    \"\") items=(\(topLevel(registry).split(separator: " ").map { "'\($0)'" }.joined(separator: " "))) ;;")
        for group in groupsWithChildren(registry) {
            let items = names(of: group.path, registry).split(separator: " ").map { "'\($0)'" }.joined(separator: " ")
            lines.append("    \"\(group.path.joined(separator: " "))\") items=(\(items)) ;;")
        }
        lines.append("    *) items=() ;;")
        lines.append("  esac")
        lines.append("  compadd -a items")
        lines.append("}")
        lines.append("compdef _embr embr")
        return lines.joined(separator: "\n") + "\n"
    }

    static func fish(_ registry: CommandRegistry) -> String {
        var lines: [String] = ["# embr fish completion"]
        for child in registry.children(of: []) {
            lines.append("complete -c embr -f -n '__fish_use_subcommand' -a '\(child.name)' -d '\(escape(child.summary))'")
        }
        for group in groupsWithChildren(registry) {
            let condition = group.path.map { "__fish_seen_subcommand_from \($0)" }.joined(separator: "; and ")
            for child in registry.children(of: group.path) {
                lines.append("complete -c embr -f -n '\(condition)' -a '\(child.name)' -d '\(escape(child.summary))'")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func groupsWithChildren(_ registry: CommandRegistry) -> [GroupSpec] {
        registry.groups
            .filter { !registry.children(of: $0.path).isEmpty }
            .sorted { $0.path.joined(separator: " ") < $1.path.joined(separator: " ") }
    }

    private static func topLevel(_ registry: CommandRegistry) -> String {
        let groups = registry.groups.filter { $0.path.count == 1 }.map { $0.path[0] }
        let commands = registry.commands.filter { $0.path.count == 1 }.map { $0.path[0] }
        return (groups + commands).sorted().joined(separator: " ")
    }

    private static func names(of path: [String], _ registry: CommandRegistry) -> String {
        registry.children(of: path).map(\.name).sorted().joined(separator: " ")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "\\'")
    }
}
