import Foundation
import os

public enum LogCategory: String, Sendable, CaseIterable {
    case app, auth, api, eventsub, chat, emote, playback, persistence, ui
}

public enum LogLevel: String, Sendable {
    case debug, info, warn, error
}

public final class AppLogger: Sendable {
    public static let shared = AppLogger()

    private let loggers: [LogCategory: Logger]
    private let fileQueue = DispatchQueue(label: "app.embr.logger.file")
    private let fileURL: URL?
    private let maxBytes = 2 * 1024 * 1024

    private init() {
        var built: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            built[category] = Logger(subsystem: "com.guitaripod.embr", category: category.rawValue)
        }
        self.loggers = built

        let logs = try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Logs", isDirectory: true)
        if let logs {
            try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            self.fileURL = logs.appendingPathComponent("embr.log")
        } else {
            self.fileURL = nil
        }
    }

    public func log(_ level: LogLevel, _ message: @autoclosure () -> String, category: LogCategory) {
        let text = message()
        let logger = loggers[category] ?? Logger()
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .warn: logger.warning("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        }
        writeToFile(level: level, category: category, text: text)
    }

    /// Current and rotated log files that exist on disk, for a "Share logs" action.
    public func logFileURLs() -> [URL] {
        guard let fileURL else { return [] }
        let previous = fileURL.deletingLastPathComponent().appendingPathComponent("embr.previous.log")
        return [fileURL, previous].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func debug(_ message: @autoclosure () -> String, category: LogCategory) { log(.debug, message(), category: category) }
    public func info(_ message: @autoclosure () -> String, category: LogCategory) { log(.info, message(), category: category) }
    public func warn(_ message: @autoclosure () -> String, category: LogCategory) { log(.warn, message(), category: category) }
    public func error(_ message: @autoclosure () -> String, category: LogCategory) { log(.error, message(), category: category) }

    private func writeToFile(level: LogLevel, category: LogCategory, text: String) {
        guard let fileURL else { return }
        let line = "\(Self.timestamp()) [\(ProcessInfo.processInfo.processIdentifier)] [\(level.rawValue)] [\(category.rawValue)] \(text)\n"
        fileQueue.async {
            self.rotateIfNeeded(at: fileURL)
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private func rotateIfNeeded(at fileURL: URL) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        let previous = fileURL.deletingLastPathComponent().appendingPathComponent("embr.previous.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
