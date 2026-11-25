import Foundation
import Testing
import EmbrCore
@testable import EmbrCLIKit

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest) -> HTTPResponse

    init(handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) {
        self.handler = handler
    }

    var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        return handler(request)
    }
}

final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { data.append(chunk) }
    }

    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }

    var json: Any? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }
}

enum TestRun {
    static func make(directory: URL? = nil) -> URL {
        let url = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("embr-cli-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func run(
        _ arguments: [String],
        transport: FakeTransport,
        configDirectory: URL
    ) async -> (code: Int32, out: Capture, err: Capture) {
        let out = Capture()
        let err = Capture()
        let environment = [
            "EMBR_CONFIG_DIR": configDirectory.path,
            "EMBR_CLIENT_ID": "client-id",
            "EMBR_ACCESS_TOKEN": "access-token"
        ]
        let code = await EmbrCLI.run(
            arguments: ["embr"] + arguments,
            environment: environment,
            transport: transport,
            isTTY: false,
            stdout: { out.append($0) },
            stderr: { err.append($0) }
        )
        return (code, out, err)
    }
}

@Suite("CLI parser", .serialized)
struct ParserTests {
    @Test func parsesOptionsAnywhereAndRepeatedFlags() throws {
        let line = try CommandCatalog.registry.parse([
            "--json", "chat", "send", "--reply-to", "42", "xqc", "hello", "--no-color"
        ])
        #expect(line.flags["json"] == ["true"])
        #expect(line.flags["reply-to"] == ["42"])
        #expect(line.flags["no-color"] == ["true"])
        #expect(line.positionals == ["chat", "send", "xqc", "hello"])
        let resolution = try CommandCatalog.registry.resolve(line.positionals)
        guard case .command(let spec, let remaining) = resolution else {
            Issue.record("expected a command")
            return
        }
        #expect(spec.path == ["chat", "send"])
        #expect(remaining == ["xqc", "hello"])
        try CommandCatalog.registry.validate(spec, flags: line.flags, positionals: remaining)
    }

    @Test func rejectsUnknownOption() {
        #expect(throws: CLIError.self) {
            try CommandCatalog.registry.parse(["--nope", "streams"])
        }
    }

    @Test func handlesDoubleDash() throws {
        let line = try CommandCatalog.registry.parse(["chat", "send", "xqc", "--", "--not-a-flag"])
        #expect(line.positionals == ["chat", "send", "xqc", "--not-a-flag"])
        #expect(line.flags.isEmpty)
    }

    @Test func catalogIsCompleteAndUnique() {
        let paths = CommandCatalog.commands.map(\.path)
        #expect(Set(paths.map { $0.joined(separator: " ") }).count == paths.count)
        for command in CommandCatalog.commands {
            #expect(!command.summary.isEmpty)
            #expect(!command.examples.isEmpty)
        }
        #expect(CommandCatalog.commands.contains { $0.path == ["chat", "watch"] })
        #expect(CommandCatalog.commands.contains { $0.path == ["eventsub", "listen"] })
        #expect(CommandCatalog.commands.contains { $0.path == ["mod", "vips"] })
    }

    @Test func rootHelpNamesGroupsAndExitCodes() {
        let help = Help.root(CommandCatalog.registry)
        #expect(help.contains("streams"))
        #expect(help.contains("chat"))
        #expect(help.contains("Exit codes"))
    }

    @Test func commandHelpHasUsageAndExamples() {
        guard let spec = CommandCatalog.commands.first(where: { $0.path == ["chat", "send"] }) else {
            Issue.record("missing chat send")
            return
        }
        let help = Help.command(spec)
        #expect(help.contains("embr chat send <channel> <message…>"))
        #expect(help.contains("embr chat send xqc hello"))
        #expect(help.contains("user:write:chat"))
    }
}
