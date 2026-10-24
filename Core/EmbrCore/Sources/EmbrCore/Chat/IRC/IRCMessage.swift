import Foundation

public struct IRCMessage: Sendable, Equatable {
    public let tags: [String: String]
    public let prefix: String?
    public let command: String
    public let parameters: [String]

    public init(tags: [String: String], prefix: String?, command: String, parameters: [String]) {
        self.tags = tags
        self.prefix = prefix
        self.command = command
        self.parameters = parameters
    }

    public var nickname: String? {
        guard let prefix else { return nil }
        guard let bang = prefix.firstIndex(of: "!") else { return prefix }
        return String(prefix[prefix.startIndex..<bang])
    }

    public static func parse(_ line: String) -> IRCMessage? {
        var trimmed = Substring(line)
        while let last = trimmed.unicodeScalars.last, last == "\r" || last == "\n" {
            trimmed = Substring(trimmed.unicodeScalars.dropLast())
        }
        var rest = trimmed
        guard !rest.isEmpty else { return nil }

        var tags: [String: String] = [:]
        if rest.first == "@" {
            rest = rest.dropFirst()
            guard let space = rest.firstIndex(of: " ") else { return nil }
            let tagSection = rest[rest.startIndex..<space]
            tags = parseTags(tagSection)
            rest = rest[rest.index(after: space)...]
            rest = dropLeadingSpaces(rest)
        }

        var prefix: String?
        if rest.first == ":" {
            rest = rest.dropFirst()
            guard let space = rest.firstIndex(of: " ") else { return nil }
            prefix = String(rest[rest.startIndex..<space])
            rest = rest[rest.index(after: space)...]
            rest = dropLeadingSpaces(rest)
        }

        guard !rest.isEmpty else { return nil }

        var parameters: [String] = []
        let command: String
        if let space = rest.firstIndex(of: " ") {
            command = String(rest[rest.startIndex..<space])
            rest = rest[rest.index(after: space)...]
        } else {
            command = String(rest)
            rest = rest[rest.endIndex...]
        }
        guard !command.isEmpty else { return nil }

        while !rest.isEmpty {
            rest = dropLeadingSpaces(rest)
            if rest.isEmpty { break }
            if rest.first == ":" {
                parameters.append(String(rest.dropFirst()))
                break
            }
            if let space = rest.firstIndex(of: " ") {
                parameters.append(String(rest[rest.startIndex..<space]))
                rest = rest[rest.index(after: space)...]
            } else {
                parameters.append(String(rest))
                break
            }
        }

        return IRCMessage(tags: tags, prefix: prefix, command: command, parameters: parameters)
    }

    private static func dropLeadingSpaces(_ input: Substring) -> Substring {
        var result = input
        while result.first == " " { result = result.dropFirst() }
        return result
    }

    private static func parseTags(_ section: Substring) -> [String: String] {
        var result: [String: String] = [:]
        for pair in section.split(separator: ";", omittingEmptySubsequences: true) {
            if let equals = pair.firstIndex(of: "=") {
                let key = String(pair[pair.startIndex..<equals])
                let raw = pair[pair.index(after: equals)...]
                result[key] = unescapeTagValue(raw)
            } else {
                result[String(pair)] = ""
            }
        }
        return result
    }

    private static func unescapeTagValue(_ value: Substring) -> String {
        guard value.contains("\\") else { return String(value) }
        var output = ""
        output.reserveCapacity(value.count)
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            if character != "\\" {
                output.append(character)
                continue
            }
            guard let next = iterator.next() else { break }
            switch next {
            case "s": output.append(" ")
            case ":": output.append(";")
            case "\\": output.append("\\")
            case "r": output.append("\r")
            case "n": output.append("\n")
            default: output.append(next)
            }
        }
        return output
    }
}
