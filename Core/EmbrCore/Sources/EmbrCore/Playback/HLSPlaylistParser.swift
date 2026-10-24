import Foundation

public enum HLSPlaylistParser {
    public static func masterVariants(_ text: String) -> [HLSVariant] {
        let lines = normalizedLines(text)
        let mediaNames = mediaVideoNames(lines)
        var variants: [HLSVariant] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attributes = parseAttributes(after: "#EXT-X-STREAM-INF:", in: line)
                guard let uri = nextURI(from: lines, after: index) else {
                    index += 1
                    continue
                }
                let groupID = attributes["VIDEO"]
                let videoName = groupID.flatMap { mediaNames[$0] }
                variants.append(
                    HLSVariant(
                        url: uri,
                        bandwidth: attributes["BANDWIDTH"].flatMap(Int.init),
                        resolution: attributes["RESOLUTION"],
                        frameRate: attributes["FRAME-RATE"].flatMap(Double.init),
                        videoName: videoName,
                        groupID: groupID
                    )
                )
            }
            index += 1
        }
        return variants
    }

    public static func qualities(_ text: String) -> [StreamQuality] {
        masterVariants(text).compactMap { variant -> StreamQuality? in
            guard let url = URL(string: variant.url) else { return nil }
            let name = qualityName(for: variant)
            return StreamQuality(
                name: name,
                url: url,
                bandwidth: variant.bandwidth,
                resolution: variant.resolution,
                frameRate: variant.frameRate,
                isAudioOnly: isAudioOnly(variant)
            )
        }
    }

    public static func segments(_ mediaPlaylist: String) -> [HLSSegment] {
        let lines = normalizedLines(mediaPlaylist)
        var segments: [HLSSegment] = []
        var pendingTags: [String] = []
        var pendingDuration: Double?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("#EXT-X-TWITCH-PREFETCH:") {
                let uri = String(line.dropFirst("#EXT-X-TWITCH-PREFETCH:".count)).trimmingCharacters(in: .whitespaces)
                segments.append(HLSSegment(uri: uri, duration: 0, isPrefetch: true, attachedTags: pendingTags))
                pendingTags = []
                pendingDuration = nil
            } else if line.hasPrefix("#EXTINF:") {
                pendingDuration = parseExtInfDuration(line)
            } else if line.hasPrefix("#EXT-X-DATERANGE:") || line.hasPrefix("#EXT-X-DISCONTINUITY") {
                pendingTags.append(line)
            } else if line.hasPrefix("#") {
                if pendingDuration != nil {
                    pendingTags.append(line)
                }
            } else if !line.isEmpty {
                segments.append(
                    HLSSegment(
                        uri: line,
                        duration: pendingDuration ?? 0,
                        isPrefetch: false,
                        attachedTags: pendingTags
                    )
                )
                pendingTags = []
                pendingDuration = nil
            }
            index += 1
        }
        return segments
    }

    private static func qualityName(for variant: HLSVariant) -> String {
        if let videoName = variant.videoName, !videoName.isEmpty {
            return videoName
        }
        if isAudioOnly(variant) {
            return "audio_only"
        }
        let height = variant.resolution
            .flatMap { $0.split(separator: "x").last }
            .map(String.init)
        if let height {
            if let fps = variant.frameRate, fps > 0 {
                return "\(height)p\(Int(fps.rounded()))"
            }
            return "\(height)p"
        }
        return variant.groupID ?? "source"
    }

    private static func isAudioOnly(_ variant: HLSVariant) -> Bool {
        let group = variant.groupID?.lowercased() ?? ""
        let name = variant.videoName?.lowercased() ?? ""
        return group.contains("audio_only") || name.contains("audio_only")
    }

    private static func mediaVideoNames(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines where line.hasPrefix("#EXT-X-MEDIA:") {
            let attributes = parseAttributes(after: "#EXT-X-MEDIA:", in: line)
            guard attributes["TYPE"]?.uppercased() == "VIDEO" else { continue }
            guard let groupID = attributes["GROUP-ID"] else { continue }
            if let name = attributes["NAME"] {
                result[groupID] = name
            }
        }
        return result
    }

    private static func nextURI(from lines: [String], after index: Int) -> String? {
        var cursor = index + 1
        while cursor < lines.count {
            let candidate = lines[cursor]
            if candidate.isEmpty || candidate.hasPrefix("#") {
                cursor += 1
                continue
            }
            return candidate
        }
        return nil
    }

    private static func parseExtInfDuration(_ line: String) -> Double {
        let value = line.dropFirst("#EXTINF:".count)
        let durationPart = value.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        return Double(durationPart.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
