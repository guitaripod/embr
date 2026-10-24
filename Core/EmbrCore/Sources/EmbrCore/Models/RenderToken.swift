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

    static func detectLink(_ word: String) -> URL? {
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
        let knownTLDs = [".com", ".tv", ".gg", ".io", ".net", ".org", ".co", ".dev", ".app", ".live", ".me", ".gl"]
        return knownTLDs.contains(where: { lowered.contains($0) })
    }

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

final class WordScanner {
    private let scalars: [Character]
    private var index = 0

    init(_ string: String) {
        self.scalars = Array(string)
    }

    func next() -> WordSegment? {
        guard index < scalars.count else { return nil }
        let isSpace = scalars[index].isWhitespace
        var buffer = ""
        while index < scalars.count, scalars[index].isWhitespace == isSpace {
            buffer.append(scalars[index])
            index += 1
        }
        return isSpace ? .whitespace(buffer) : .word(buffer)
    }
}
