import Foundation

/// Rewrites a live Twitch media playlist on the device for Hyper Low Latency, one reload after another, so Hyper costs
/// the worker nothing while it plays: the player reads Twitch's playlist through this instead of through the proxy.
///
/// Each reload drops `#EXT-X-START`, lists Twitch's two `#EXT-X-TWITCH-PREFETCH` segments (still being encoded,
/// streamed by the CDN as they grow) as ordinary segments, strips stitched ads, and states Twitch's real 2-second
/// target duration instead of its 5. Twitch renames a prefetch segment once it is complete and AVPlayer stops playback
/// when a media sequence number's URI changes between reloads, so the rewriter keeps the first URI it saw for every
/// sequence number and lists that one from then on; the bytes behind both names are the same.
public nonisolated struct HyperPlaylistRewriter: Sendable {
    private var uris: [Int: String] = [:]

    /// How many sequence numbers behind the playlist's first one the rewriter still remembers.
    private static let memory = 64
    private static let minimumTargetDuration = 2

    public init() {}

    /// The playlist to hand AVPlayer for this reload of `playlist`, fetched from `playlistURL`.
    public mutating func rewrite(_ playlist: String, playlistURL: URL) -> String {
        let lines = playlist.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard Self.isLive(lines) else { return Self.absolute(lines, base: playlistURL).joined(separator: "\n") }
        let prepared = prepare(lines, base: playlistURL)
        let stripped = HyperAdStripper.strip(prepared)
        let stated = Self.restateTargetDuration(stripped)
        forget(before: Self.mediaSequence(lines))
        return Self.absolute(stated, base: playlistURL).joined(separator: "\n")
    }

    static func isLive(_ lines: [String]) -> Bool {
        !lines.contains { $0.hasPrefix("#EXT-X-ENDLIST") || $0.hasPrefix("#EXT-X-PLAYLIST-TYPE") }
    }

    /// Lists every segment and prefetch under the URI first seen for its sequence number, turns prefetch lines into
    /// segments that copy the previous segment's title and duration with an extrapolated program date, and drops
    /// `#EXT-X-START`, which during a preroll would start the player at the oldest segment.
    private mutating func prepare(_ lines: [String], base: URL) -> [String] {
        var out: [String] = []
        var sequence = 0
        var lastTitle = "live"
        var lastDuration = 0.0
        var lastDate: Date?
        var awaitingURI = false

        for line in lines {
            if line.hasPrefix("#EXT-X-START") { continue }
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                sequence = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)) ?? 0
                out.append(line)
                continue
            }
            if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                lastDate = Self.date(String(line.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count)))
                out.append(line)
                continue
            }
            if line.hasPrefix("#EXTINF:") {
                lastDuration = Self.duration(of: line)
                lastTitle = Self.title(of: line)
                awaitingURI = true
                out.append(line)
                continue
            }
            if line.hasPrefix("#EXT-X-TWITCH-PREFETCH:") {
                let duration = lastDuration > 0 ? lastDuration : 2
                if let date = lastDate {
                    let next = date.addingTimeInterval(duration)
                    lastDate = next
                    out.append("#EXT-X-PROGRAM-DATE-TIME:" + Self.format(next))
                }
                out.append("#EXTINF:" + String(format: "%.3f", duration) + "," + lastTitle)
                let uri = String(line.dropFirst("#EXT-X-TWITCH-PREFETCH:".count)).trimmingCharacters(in: .whitespaces)
                out.append(stable(sequence, Self.resolve(uri, base: base)))
                sequence += 1
                continue
            }
            if awaitingURI, !line.isEmpty, !line.hasPrefix("#") {
                awaitingURI = false
                out.append(stable(sequence, Self.resolve(line.trimmingCharacters(in: .whitespaces), base: base)))
                sequence += 1
                continue
            }
            out.append(line)
        }
        return out
    }

    private mutating func stable(_ sequence: Int, _ uri: String) -> String {
        if let known = uris[sequence] { return known }
        uris[sequence] = uri
        return uri
    }

    private mutating func forget(before sequence: Int) {
        let floor = sequence - Self.memory
        uris = uris.filter { $0.key >= floor }
    }

    /// The longest remaining segment, rounded as the spec rounds, never below 2 nor above what Twitch declared.
    static func restateTargetDuration(_ lines: [String]) -> [String] {
        var declared: Int?
        var longest = 0
        for line in lines {
            if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                declared = Int(line.dropFirst("#EXT-X-TARGETDURATION:".count).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("#EXTINF:") {
                longest = max(longest, Int(duration(of: line).rounded()))
            }
        }
        guard let declared else { return lines }
        let target = min(declared, max(minimumTargetDuration, longest))
        return lines.map { $0.hasPrefix("#EXT-X-TARGETDURATION:") ? "#EXT-X-TARGETDURATION:\(target)" : $0 }
    }

    /// Makes every URI absolute against the playlist, since the player reads it from a custom scheme that has no base.
    static func absolute(_ lines: [String], base: URL) -> [String] {
        var awaitingURI = false
        return lines.map { line in
            if line.hasPrefix("#EXTINF:") {
                awaitingURI = true
                return line
            }
            if line.hasPrefix("#") {
                return line.contains("URI=\"") ? absoluteAttributes(line, base: base) : line
            }
            guard awaitingURI, !line.isEmpty else { return line }
            awaitingURI = false
            return resolve(line, base: base)
        }
    }

    private static func absoluteAttributes(_ line: String, base: URL) -> String {
        var out = ""
        var rest = Substring(line)
        while let start = rest.range(of: "URI=\"") {
            out += rest[..<start.upperBound]
            let tail = rest[start.upperBound...]
            guard let end = tail.firstIndex(of: "\"") else {
                out += tail
                return out
            }
            out += resolve(String(tail[..<end]), base: base)
            rest = tail[end...]
        }
        return out + rest
    }

    static func resolve(_ uri: String, base: URL) -> String {
        URL(string: uri, relativeTo: base)?.absoluteString ?? uri
    }

    static func mediaSequence(_ lines: [String]) -> Int {
        lines.first { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }
            .flatMap { Int($0.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
    }

    static func duration(of extinf: String) -> Double {
        let value = extinf.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        return Double(value.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } ?? 0
    }

    static func title(of extinf: String) -> String {
        guard let comma = extinf.firstIndex(of: ",") else { return "" }
        return String(extinf[extinf.index(after: comma)...])
    }

    private static func date(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return fractional.date(from: trimmed) ?? whole.date(from: trimmed)
    }

    private static func format(_ date: Date) -> String {
        fractional.string(from: date)
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
