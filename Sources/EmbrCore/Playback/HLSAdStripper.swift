import Foundation

public enum HLSAdStripper {
    public static func strip(_ mediaPlaylist: String) -> String {
        let usesCRLF = mediaPlaylist.contains("\r\n")
        let rawLines = mediaPlaylist
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let adWindows = stitchedAdWindows(rawLines)

        var output: [String] = []
        var index = 0
        while index < rawLines.count {
            let line = rawLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isStitchedAdDateRange(trimmed) {
                index += 1
                continue
            }

            if trimmed.hasPrefix("#EXTINF:") {
                let title = extInfTitle(trimmed)
                let belongsToAd = title.localizedCaseInsensitiveContains("Amazon")
                    || isWithinAdWindow(lineIndex: index, windows: adWindows)
                if belongsToAd {
                    index = skipAdSegment(from: index, in: rawLines, output: &output)
                    continue
                }
            }

            output.append(line)
            index += 1
        }

        let separator = usesCRLF ? "\r\n" : "\n"
        return output.joined(separator: separator)
    }

    private static func skipAdSegment(from extInfIndex: Int, in lines: [String], output: inout [String]) -> Int {
        if let last = output.last,
           last.trimmingCharacters(in: .whitespaces).hasPrefix("#EXT-X-DISCONTINUITY") {
            output.removeLast()
        }
        var cursor = extInfIndex + 1
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if trimmed.hasPrefix("#EXT-X-TWITCH-PREFETCH:") {
                break
            }
            if trimmed.hasPrefix("#") {
                cursor += 1
                continue
            }
            cursor += 1
            break
        }
        return cursor
    }

    private static func stitchedAdWindows(_ lines: [String]) -> [(start: Int, end: Int)] {
        var windows: [(start: Int, end: Int)] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard isStitchedAdDateRange(trimmed) else { continue }
            let attributes = parseAttributes(after: "#EXT-X-DATERANGE:", in: trimmed)
            let duration = attributes["DURATION"].flatMap(Double.init)
                ?? attributes["PLANNED-DURATION"].flatMap(Double.init)
                ?? 0
            windows.append((start: index, end: endIndex(forDuration: duration, fromDateRangeAt: index, in: lines)))
        }
        return windows
    }

    private static func endIndex(forDuration duration: Double, fromDateRangeAt start: Int, in lines: [String]) -> Int {
        guard duration > 0 else { return start }
        var accumulated = 0.0
        var cursor = start + 1
        var lastSegmentLine = start
        while cursor < lines.count, accumulated < duration {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXTINF:") {
                accumulated += extInfDuration(trimmed)
                lastSegmentLine = cursor
            } else if isStitchedAdDateRange(trimmed) {
                break
            }
            cursor += 1
        }
        return lastSegmentLine
    }

    private static func isWithinAdWindow(lineIndex: Int, windows: [(start: Int, end: Int)]) -> Bool {
        windows.contains { lineIndex > $0.start && lineIndex <= $0.end }
    }

    private static func isStitchedAdDateRange(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("#EXT-X-DATERANGE:") else { return false }
        let attributes = parseAttributes(after: "#EXT-X-DATERANGE:", in: trimmed)
        if attributes["CLASS"] == "twitch-stitched-ad" { return true }
        if let id = attributes["ID"], id.hasPrefix("stitched-ad-") { return true }
        return false
    }

    private static func extInfTitle(_ line: String) -> String {
        let value = line.dropFirst("#EXTINF:".count)
        let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return "" }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }

    private static func extInfDuration(_ line: String) -> Double {
        let value = line.dropFirst("#EXTINF:".count)
        let durationPart = value.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        return Double(durationPart.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func parseAttributes(after prefix: String, in line: String) -> [String: String] {
        guard line.hasPrefix(prefix) else { return [:] }
        let raw = String(line.dropFirst(prefix.count))
        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var insideQuotes = false
        for character in raw {
            if readingKey {
                if character == "=" {
                    readingKey = false
                    value = ""
                } else {
                    key.append(character)
                }
                continue
            }
            if character == "\"" {
                insideQuotes.toggle()
                continue
            }
            if character == "," && !insideQuotes {
                result[key.trimmingCharacters(in: .whitespaces)] = value
                key = ""
                value = ""
                readingKey = true
                continue
            }
            value.append(character)
        }
        if !key.isEmpty {
            result[key.trimmingCharacters(in: .whitespaces)] = value
        }
        return result
    }
}
