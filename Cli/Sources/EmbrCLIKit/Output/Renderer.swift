import Foundation

public struct OutputOptions: Sendable {
    public enum Mode: String, Sendable {
        case auto
        case json
        case table
        case ndjson
    }

    public var mode: Mode
    public var raw: Bool
    public var quiet: Bool
    public var color: Bool
    public var isTTY: Bool

    public init(mode: Mode = .auto, raw: Bool = false, quiet: Bool = false, color: Bool = true, isTTY: Bool = false) {
        self.mode = mode
        self.raw = raw
        self.quiet = quiet
        self.color = color
        self.isTTY = isTTY
    }
}

public final class Renderer: @unchecked Sendable {
    private let stdout: @Sendable (Data) -> Void
    private let stderr: @Sendable (Data) -> Void
    public let options: OutputOptions

    public init(
        options: OutputOptions,
        stdout: @escaping @Sendable (Data) -> Void = { FileHandle.standardOutput.write($0) },
        stderr: @escaping @Sendable (Data) -> Void = { FileHandle.standardError.write($0) }
    ) {
        self.options = options
        self.stdout = stdout
        self.stderr = stderr
    }

    public func write(_ result: CommandResult, command: String) throws {
        guard !result.silent else { return }
        switch options.mode {
        case .ndjson:
            try writeNDJSON(result, command: command)
        case .json:
            try writeEnvelope(result, command: command, pretty: false)
        case .table:
            try writeTableOrEnvelope(result, command: command)
        case .auto:
            if options.isTTY, let table = result.table {
                writeTable(table)
            } else {
                try writeEnvelope(result, command: command, pretty: options.isTTY)
            }
        }
    }

    public func writeError(_ error: CLIError, command: String) {
        if options.isTTY && !options.quiet {
            var text = "embr: \(error.message)\n"
            if let hint = error.hint {
                text += "hint: \(hint)\n"
            }
            stderr(Data(text.utf8))
        }
        let body = ErrorEnvelope(
            ok: false,
            command: command,
            error: .init(
                kind: error.kind.rawValue,
                message: error.message,
                status: error.status,
                hint: error.hint
            )
        )
        if let data = try? Self.encode(body, pretty: false) {
            stderr(data + Data("\n".utf8))
        }
    }

    public func writeLine<T: Encodable & Sendable>(_ value: T) {
        guard let data = try? Self.encode(value, pretty: false) else { return }
        stdout(data + Data("\n".utf8))
    }

    public func writeText(_ text: String) {
        stdout(Data(text.utf8))
    }

    public func note(_ text: String) {
        guard !options.quiet else { return }
        stderr(Data((text + "\n").utf8))
    }

    private func writeNDJSON(_ result: CommandResult, command: String) throws {
        if let items = result.items {
            for item in items {
                let data = try Self.encode(item, pretty: false)
                stdout(data + Data("\n".utf8))
            }
            return
        }
        let data = try Self.encode(result.value, pretty: false)
        stdout(data + Data("\n".utf8))
    }

    private func writeEnvelope(_ result: CommandResult, command: String, pretty: Bool) throws {
        let envelope = Envelope(
            ok: true,
            command: command,
            data: result.value,
            pagination: result.cursor.map { .init(cursor: $0) },
            meta: (result.count == nil && result.total == nil) ? nil : .init(count: result.count, total: result.total)
        )
        let data = try Self.encode(envelope, pretty: pretty)
        stdout(data + Data("\n".utf8))
    }

    private func writeTableOrEnvelope(_ result: CommandResult, command: String) throws {
        if let table = result.table {
            writeTable(table)
        } else {
            try writeEnvelope(result, command: command, pretty: true)
        }
    }

    private func writeTable(_ table: TableData) {
        let widths = Self.widths(for: table)
        var lines: [String] = []
        lines.append(Self.row(table.columns.map { $0.uppercased() }, widths: widths))
        for row in table.rows {
            lines.append(Self.row(row, widths: widths))
        }
        let text = lines.joined(separator: "\n") + "\n"
        stdout(Data(text.utf8))
    }

    private static func widths(for table: TableData) -> [Int] {
        var widths = table.columns.map { $0.count }
        for row in table.rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], min(cell.count, 48))
            }
        }
        return widths
    }

    private static func row(_ cells: [String], widths: [Int]) -> String {
        cells.enumerated().map { index, cell in
            let value = index < widths.count ? truncate(cell, to: widths[index]) : cell
            return index == cells.count - 1 ? value : value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
    }

    private static func truncate(_ value: String, to width: Int) -> String {
        guard value.count > width else { return value }
        guard width > 1 else { return String(value.prefix(width)) }
        return String(value.prefix(width - 1)) + "…"
    }

    private static func encode<T: Encodable>(_ value: T, pretty: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}

private struct Envelope: Encodable {
    let ok: Bool
    let command: String
    let data: AnyEncodable
    let pagination: Pagination?
    let meta: Meta?

    struct Pagination: Encodable {
        let cursor: String
    }

    struct Meta: Encodable {
        let count: Int?
        let total: Int?
    }
}

private struct ErrorEnvelope: Encodable {
    struct Payload: Encodable {
        let kind: String
        let message: String
        let status: Int?
        let hint: String?
    }

    let ok: Bool
    let command: String
    let error: Payload
}
