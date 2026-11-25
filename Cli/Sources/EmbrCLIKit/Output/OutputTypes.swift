import Foundation

public struct AnyEncodable: Encodable, Sendable {
    private let encodeClosure: @Sendable (Encoder) throws -> Void

    public init<T: Encodable & Sendable>(_ value: T) {
        encodeClosure = { encoder in
            try value.encode(to: encoder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

public struct TableData: Sendable {
    public let columns: [String]
    public let rows: [[String]]

    public init(columns: [String], rows: [[String]]) {
        self.columns = columns
        self.rows = rows
    }
}

public struct CommandResult: Sendable {
    public let value: AnyEncodable
    public let items: [AnyEncodable]?
    public let table: TableData?
    public let cursor: String?
    public let total: Int?
    public let count: Int?
    public let status: Int?
    public let silent: Bool

    public init(
        value: AnyEncodable,
        items: [AnyEncodable]? = nil,
        table: TableData? = nil,
        cursor: String? = nil,
        total: Int? = nil,
        count: Int? = nil,
        status: Int? = nil,
        silent: Bool = false
    ) {
        self.value = value
        self.items = items
        self.table = table
        self.cursor = cursor
        self.total = total
        self.count = count
        self.status = status
        self.silent = silent
    }

    public init<T: Encodable & Sendable>(
        _ value: T,
        items: [AnyEncodable]? = nil,
        table: TableData? = nil,
        cursor: String? = nil,
        total: Int? = nil,
        count: Int? = nil,
        status: Int? = nil,
        silent: Bool = false
    ) {
        self.init(
            value: AnyEncodable(value),
            items: items,
            table: table,
            cursor: cursor,
            total: total,
            count: count,
            status: status,
            silent: silent
        )
    }

    public static func empty(status: Int = 204) -> CommandResult {
        CommandResult(value: AnyEncodable(EmptyObject()), count: 0, status: status)
    }
}

public struct EmptyObject: Encodable, Sendable {
    public init() {}
    public func encode(to encoder: Encoder) throws {
        _ = encoder.container(keyedBy: EmptyKeys.self)
    }

    private enum EmptyKeys: CodingKey {}
}
