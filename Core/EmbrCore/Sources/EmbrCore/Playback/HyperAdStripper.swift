import Foundation

/// Removes Twitch's stitched ads from a live media playlist while keeping it valid for AVPlayer, as the worker's
/// stripper does for standard playlists.
///
/// The playlist keeps only its newest unbroken run of content segments, so every kept segment keeps Twitch's media
/// sequence number: numbering content across a removed ad would give a sequence number another segment once the ad
/// slides out of the window, which AVPlayer treats as an illegal change (`-12312`). Ads after the run are cut from the
/// end; ads and older content before it are cut from the front, with `#EXT-X-MEDIA-SEQUENCE` advanced to match. The
/// `#EXT-X-MAP` in force for the run is kept, and the discontinuity in front of it dropped. A segment is an ad inside a
/// stitched-ad window (opened by a stitched-ad `#EXT-X-DATERANGE`, closed by the first content title after at least one
/// ad segment) or when its title says Amazon. A playlist without ads, or with nothing but ads, comes back unchanged.
nonisolated enum HyperAdStripper {
    private struct Segment {
        var tags: [String]
        var extinf: String
        var uri: String?
        var isAd: Bool
    }

    private static let adClasses: Set<String> = ["twitch-stitched-ad", "twitch-stream-source", "twitch-trigger", "twitch-ad-quartile"]
    private static let segmentTagPrefixes = [
        "#EXTINF", "#EXT-X-MAP", "#EXT-X-PROGRAM-DATE-TIME", "#EXT-X-BYTERANGE", "#EXT-X-KEY", "#EXT-X-GAP",
        "#EXT-X-BITRATE", "#EXT-X-DATERANGE", "#EXT-X-TWITCH-LIVE-SEQUENCE",
    ]

    static func strip(_ lines: [String]) -> [String] {
        let (header, segments, trailer) = parse(lines)
        guard segments.contains(where: \.isAd), let last = segments.lastIndex(where: { !$0.isAd }) else { return lines }
        var first = last
        while first > 0, !segments[first - 1].isAd { first -= 1 }

        let before = segments[..<first]
        let kept = segments[first...last]
        var out = header
            .filter { !isAdDaterange($0) }
            .map { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") ? "#EXT-X-MEDIA-SEQUENCE:\(HyperPlaylistRewriter.mediaSequence(header) + first)" : $0 }
        if first > 0, !header.contains(where: { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }) {
            let top = (out.firstIndex(of: "#EXTM3U") ?? -1) + 1
            out.insert("#EXT-X-MEDIA-SEQUENCE:\(first)", at: top)
        }

        let earlier = header + before.flatMap(\.tags)
        out += earlier.filter { $0.hasPrefix("#EXT-X-DATERANGE") && !isAdDaterange($0) }
        let firstTags = kept.first?.tags ?? []
        if let map = (earlier + firstTags).last(where: { $0.hasPrefix("#EXT-X-MAP") }),
           !firstTags.contains(where: { $0.hasPrefix("#EXT-X-MAP") }) {
            out.append(map)
        }

        for (offset, segment) in kept.enumerated() {
            for tag in segment.tags {
                if isAdDaterange(tag) { continue }
                if offset == 0, tag == "#EXT-X-DISCONTINUITY" { continue }
                out.append(tag)
            }
            out.append(segment.extinf)
            if let uri = segment.uri { out.append(uri) }
        }

        let reachesEnd = last == segments.count - 1
        out += trailer.filter { line in
            if line.hasPrefix("#EXT-X-TWITCH-PREFETCH") { return reachesEnd }
            return !isSegmentTag(line)
        }
        return out
    }

    private static func parse(_ lines: [String]) -> (header: [String], segments: [Segment], trailer: [String]) {
        var header: [String] = []
        var segments: [Segment] = []
        var pending: [String] = []
        var inAdWindow = false
        var consumedAd = false
        var started = false
        var index = 0

        while index < lines.count {
            let line = lines[index]
            if !started, !isSegmentTag(line) {
                header.append(line)
                index += 1
                continue
            }
            started = true
            if isStitchedAd(line) {
                inAdWindow = true
                consumedAd = false
            }
            if line.hasPrefix("#EXT-X-TWITCH-PREFETCH") {
                inAdWindow = false
            }
            guard line.hasPrefix("#EXTINF") else {
                pending.append(line)
                index += 1
                continue
            }
            let title = HyperPlaylistRewriter.title(of: line)
            if inAdWindow, consumedAd, isContentTitle(title) {
                inAdWindow = false
            }
            let isAd = title.contains("Amazon") || inAdWindow
            if isAd { consumedAd = true }
            var next = index + 1
            while next < lines.count, lines[next].isEmpty { next += 1 }
            let uri = next < lines.count && !lines[next].hasPrefix("#") ? lines[next] : nil
            segments.append(Segment(tags: pending, extinf: line, uri: uri, isAd: isAd))
            pending = []
            index = uri == nil ? index + 1 : next + 1
        }
        return (header, segments, pending)
    }

    private static func isSegmentTag(_ line: String) -> Bool {
        line == "#EXT-X-DISCONTINUITY" || segmentTagPrefixes.contains { line.hasPrefix($0) }
    }

    private static func isContentTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("Amazon")
    }

    private static func isStitchedAd(_ line: String) -> Bool {
        guard line.hasPrefix("#EXT-X-DATERANGE") else { return false }
        if attribute("CLASS", in: line) == "twitch-stitched-ad" { return true }
        return attribute("ID", in: line)?.hasPrefix("stitched-ad-") ?? false
    }

    private static func isAdDaterange(_ line: String) -> Bool {
        guard line.hasPrefix("#EXT-X-DATERANGE") else { return false }
        if isStitchedAd(line) { return true }
        return attribute("CLASS", in: line).map(adClasses.contains) ?? false
    }

    private static func attribute(_ key: String, in line: String) -> String? {
        guard let range = line.range(of: key + "=") else { return nil }
        let rest = line[range.upperBound...]
        if rest.first == "\"" {
            let value = rest.dropFirst()
            return value.firstIndex(of: "\"").map { String(value[..<$0]) }
        }
        return String(rest.prefix { $0 != "," && !$0.isWhitespace })
    }
}
