import Foundation

public enum TwitchJSON {
    /// Configured once and only ever read afterwards, so decoding is safe from any task. Twitch sends the same
    /// timestamp with hundredths of a second on some endpoints and without them on others, which is why both
    /// formatters stay warm instead of being built per value.
    nonisolated(unsafe) private static let isoFormatter = makeFormatter(fractional: false)
    nonisolated(unsafe) private static let isoFractionalFormatter = makeFormatter(fractional: true)

    /// Reads a timestamp the way every Twitch response writes one, for the fields whose empty string means "never"
    /// rather than a date.
    public static func date(from raw: String) -> Date? {
        isoFractionalFormatter.date(from: raw) ?? isoFormatter.date(from: raw)
    }

    /// Configured once in the initializer and never mutated afterwards; `JSONDecoder.decode` is safe to call concurrently.
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(raw)")
            }
            return date
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
