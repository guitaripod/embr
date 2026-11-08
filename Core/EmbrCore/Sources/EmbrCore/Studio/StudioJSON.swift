import Foundation

/// A forgiving reader over one JSON object, for Twitch payloads whose fields are often null, sometimes numbers sent as
/// strings, and whose timestamps come in several precisions.
struct StudioJSON: @unchecked Sendable {
    let object: [String: Any]

    init(_ object: [String: Any]) {
        self.object = object
    }

    init?(data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.object = object
    }

    func string(_ key: String) -> String? {
        switch object[key] {
        case let value as String: value
        case let value as Int: String(value)
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    /// A string that is present and not empty.
    func text(_ key: String) -> String? {
        string(key).flatMap { $0.isEmpty ? nil : $0 }
    }

    func int(_ key: String) -> Int? {
        switch object[key] {
        case let value as Int: value
        case let value as Double: Int(value)
        case let value as NSNumber: value.intValue
        case let value as String: Int(value) ?? Double(value).map { Int($0) }
        default: nil
        }
    }

    func bool(_ key: String) -> Bool? {
        switch object[key] {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        case let value as String: value == "true"
        default: nil
        }
    }

    func child(_ key: String) -> StudioJSON? {
        (object[key] as? [String: Any]).map(StudioJSON.init)
    }

    func children(_ key: String) -> [StudioJSON] {
        (object[key] as? [[String: Any]] ?? []).map(StudioJSON.init)
    }

    func date(_ key: String) -> Date? {
        switch object[key] {
        case let value as Int: Self.date(unix: Double(value))
        case let value as Double: Self.date(unix: value)
        case let value as NSNumber: Self.date(unix: value.doubleValue)
        case let value as String: Self.date(value)
        default: nil
        }
    }

    /// A Twitch timestamp: RFC 3339 with any number of fractional digits, or Unix seconds written as a string.
    static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let seconds = Double(trimmed) { return date(unix: seconds) }
        let normalized = limitFraction(trimmed)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }

    private static func date(unix seconds: Double) -> Date? {
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
    }

    /// Cuts fractional seconds to milliseconds, the precision the system's ISO 8601 parser accepts everywhere.
    private static func limitFraction(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }
        let afterDot = text.index(after: dot)
        let digitsEnd = text[afterDot...].firstIndex { !$0.isNumber } ?? text.endIndex
        let digits = text[afterDot..<digitsEnd]
        guard digits.count > 3 else { return text }
        return String(text[..<afterDot]) + digits.prefix(3) + text[digitsEnd...]
    }
}
