import Foundation

public enum TwitchJSON {
    nonisolated(unsafe) public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let iso = makeFormatter(fractional: false)
        let isoFractional = makeFormatter(fractional: true)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = isoFractional.date(from: raw) ?? iso.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw APIError.decoding(String(describing: error))
        }
    }
}
