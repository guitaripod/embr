import Foundation

/// Decides which chat messages stand out for this viewer: ones that mention them, contain a word or phrase they chose,
/// or come from someone they chose. A single word matches whole, a phrase matches anywhere, and both ignore case and
/// accents. The viewer's own messages never stand out.
public struct ChatHighlighter: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable {
        case mention
        case word
        case user
    }

    private let ownLogin: String?
    private let mentionLogin: String?
    private let words: Set<String>
    private let phrases: [String]
    private let users: Set<String>

    public init(login: String?, mentions: Bool, words: [String] = [], users: [String] = []) {
        let own = login.map(Self.normalize).flatMap { $0.isEmpty ? nil : $0 }
        self.ownLogin = own
        self.mentionLogin = mentions ? own : nil
        var single = Set<String>()
        var multi: [String] = []
        for raw in words {
            let term = Self.normalize(raw).trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { continue }
            if term.allSatisfy(Self.isWordCharacter) {
                single.insert(term)
            } else {
                multi.append(term)
            }
        }
        self.words = single
        self.phrases = multi
        self.users = Set(users.map(Self.normalize).filter { !$0.isEmpty })
    }

    /// True when nothing can stand out, so callers can skip the work.
    public var isEmpty: Bool {
        mentionLogin == nil && words.isEmpty && phrases.isEmpty && users.isEmpty
    }

    /// Why the message stands out, or nil when it does not. A chosen user wins over a mention, and a mention over a
    /// chosen word.
    public func reason(for message: ChatMessage) -> Reason? {
        guard !isEmpty else { return nil }
        let author = Self.normalize(message.author.login)
        if let ownLogin, author == ownLogin { return nil }
        if users.contains(author) { return .user }
        let text = Self.normalize(message.plainText)
        let tokens = Self.tokens(of: text)
        if let mentionLogin, mentions(mentionLogin, in: message, tokens: tokens) { return .mention }
        if !words.isDisjoint(with: tokens) { return .word }
        if phrases.contains(where: { text.contains($0) }) { return .word }
        return nil
    }

    private func mentions(_ login: String, in message: ChatMessage, tokens: Set<String>) -> Bool {
        for fragment in message.fragments {
            if case .mention(let ref) = fragment, Self.normalize(ref.login) == login || Self.normalize(ref.displayName) == login {
                return true
            }
        }
        return tokens.contains(login)
    }

    /// The whole words of normalized text: runs of letters, digits and underscores, as Twitch logins are spelled.
    private static func tokens(of text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !isWordCharacter($0) }).map(String.init))
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}
