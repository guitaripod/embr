import Foundation

public enum RenderToken: Sendable, Equatable {
    case text(String)
    case emote(Emote)
    case mention(MentionRef)
    case link(URL, raw: String)
    case cheermote(CheermoteRef)
}

public enum MessageTokenizer {
    public static func tokens(for message: ChatMessage, catalog: EmoteCatalog) -> [RenderToken] {
        var tokens: [RenderToken] = []
        for fragment in message.fragments {
            switch fragment {
            case .emote(let ref):
                tokens.append(.emote(EmoteCDN.twitchEmote(from: ref)))
            case .cheermote(let ref):
                tokens.append(.cheermote(ref))
            case .mention(let ref):
                tokens.append(.mention(ref))
            case .text(let value):
                tokens.append(contentsOf: tokenizeText(value, catalog: catalog))
            }
        }
        return coalesce(tokens)
    }

    private static func tokenizeText(_ value: String, catalog: EmoteCatalog) -> [RenderToken] {
        var tokens: [RenderToken] = []
        var pending = ""

        func flushPending() {
            if !pending.isEmpty {
                tokens.append(.text(pending))
                pending = ""
            }
        }

        let scanner = WordScanner(value)
        while let segment = scanner.next() {
            switch segment {
            case .whitespace(let ws):
                pending += ws
            case .word(let word):
                if let emote = catalog.lookup(word) {
                    flushPending()
                    tokens.append(.emote(emote))
                } else if let url = detectLink(word) {
                    flushPending()
                    tokens.append(.link(url, raw: word))
                } else {
                    pending += word
                }
            }
        }
        flushPending()
        return tokens
    }

    /// A link needs a dot in its host, so the common word without one is turned away before any lowercasing or URL
    /// parsing.
    static func detectLink(_ word: String) -> URL? {
        guard word.utf8.contains(UInt8(ascii: ".")) else { return nil }
        let lowered = word.lowercased()
        let hasScheme = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        let candidate = hasScheme ? word : "https://\(word)"
        guard looksLikeURL(word) else { return nil }
        guard let url = URL(string: candidate), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    private static func looksLikeURL(_ word: String) -> Bool {
        let lowered = word.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { return true }
        guard let dotIndex = word.firstIndex(of: "."), dotIndex != word.startIndex else { return false }
        let afterDot = word.index(after: dotIndex)
        guard afterDot < word.endIndex else { return false }
        return knownTLDs.contains(where: { lowered.contains($0) })
    }

    private static let knownTLDs = [".com", ".tv", ".gg", ".io", ".net", ".org", ".co", ".dev", ".app", ".live", ".me", ".gl"]

    private static func coalesce(_ tokens: [RenderToken]) -> [RenderToken] {
        var result: [RenderToken] = []
        for token in tokens {
            if case .text(let next) = token, case .text(let prev)? = result.last {
                result[result.count - 1] = .text(prev + next)
            } else {
                result.append(token)
            }
        }
        return result
    }
}

enum WordSegment: Equatable {
    case word(String)
    case whitespace(String)
}

/// Splits text into runs of words and whitespace by walking the string in place, without copying it into an array of
/// characters or growing each run a character at a time.
final class WordScanner {
    private let string: String
    private var index: String.Index

    init(_ string: String) {
        self.string = string
        self.index = string.startIndex
    }

    func next() -> WordSegment? {
        guard index < string.endIndex else { return nil }
        let isSpace = string[index].isWhitespace
        let start = index
        while index < string.endIndex, string[index].isWhitespace == isSpace {
            string.formIndex(after: &index)
        }
        let run = String(string[start..<index])
        return isSpace ? .whitespace(run) : .word(run)
    }
}
