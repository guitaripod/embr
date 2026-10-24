import Foundation

/// Hides objectionable chat messages before they reach the feed (App Store Guideline 1.2:
/// "a method for filtering objectionable content").
///
/// Two layers combine:
/// - a built-in list of severe slurs and hate terms, matched on whole normalized words so
///   benign words that merely *contain* a term (the "Scunthorpe problem") are never hidden;
/// - the user's own muted keywords/phrases, matched as normalized substrings.
///
/// Normalization folds case, diacritics, and common leetspeak, and a run-collapsing pass
/// catches elongated obfuscation (`niiigger` → the same collapsed form as `nigger`), so the
/// filter resists the usual evasions without a per-message dictionary lookup.
public struct ContentFilter: Sendable, Equatable {
    private let wordTerms: Set<String>
    private let collapsedWordTerms: [String: Int]
    private let substringTerms: [String]

    public init(userTerms: [String] = [], includeDefaultList: Bool = true) {
        var words = Set<String>()
        if includeDefaultList {
            for term in Self.defaultTerms {
                let normalized = Self.normalize(term)
                if normalized.count >= 3 { words.insert(normalized) }
            }
        }
        var substrings: [String] = []
        for term in userTerms {
            let normalized = Self.normalize(term).trimmingCharacters(in: .whitespaces)
            guard normalized.count >= 2 else { continue }
            // Whole-word matching only sees alphanumeric tokens, so a term carrying any
            // separator (space, dash, period, apostrophe…) could never match a token — route
            // it to substring matching instead, which is what the user intends anyway.
            if normalized.contains(where: { !$0.isLetter && !$0.isNumber }) {
                substrings.append(normalized)
            } else {
                words.insert(normalized)
            }
        }
        self.wordTerms = words
        var collapsed: [String: Int] = [:]
        for term in words {
            let key = Self.collapseRuns(term)
            collapsed[key] = min(collapsed[key] ?? .max, term.count)
        }
        self.collapsedWordTerms = collapsed
        self.substringTerms = substrings
    }

    /// True when this filter would hide anything at all. Callers can skip the work entirely
    /// when it is inert.
    public var isEmpty: Bool { wordTerms.isEmpty && substringTerms.isEmpty }

    /// Whether the given message text should be hidden from the feed.
    public func shouldHide(_ text: String) -> Bool {
        guard !isEmpty else { return false }
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return false }

        for phrase in substringTerms where normalized.range(of: phrase) != nil {
            return true
        }
        guard !wordTerms.isEmpty else { return false }
        for token in Self.tokenize(normalized) {
            if wordTerms.contains(String(token)) { return true }
            // Collapsed matching catches elongation ("coooon"), so it only fires when the
            // token is at least as long as the real term — never when a shorter, benign
            // word collapses onto a term's shape (e.g. "con"/"cons" onto "coon"/"coons").
            if let minLength = collapsedWordTerms[Self.collapseRuns(token)], token.count >= minLength {
                return true
            }
        }
        return false
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        var result = ""
        result.reserveCapacity(folded.count)
        for character in folded {
            result.append(leetMap[character] ?? character)
        }
        return result
    }

    private static func tokenize(_ normalized: String) -> [Substring] {
        normalized.split { !$0.isLetter && !$0.isNumber }
    }

    /// Collapses any run of the same character to a single one so elongated spellings match
    /// their base term. Applied to both terms and tokens, so double letters in a term (e.g.
    /// the two Gs in a slur) collapse symmetrically and still match.
    private static func collapseRuns<S: StringProtocol>(_ value: S) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var previous: Character?
        for character in value where character != previous {
            result.append(character)
            previous = character
        }
        return result
    }

    private static let leetMap: [Character: Character] = [
        "0": "o", "1": "i", "!": "i", "|": "i",
        "3": "e", "4": "a", "@": "a", "5": "s",
        "$": "s", "7": "t", "+": "t", "8": "b",
        "9": "g", "6": "g",
    ]

    /// Severe, unambiguous slurs and hate terms. Kept deliberately conservative and
    /// whole-word matched to avoid hiding legitimate speech; users layer their own muted
    /// words on top. Elongation and leetspeak variants are handled by normalization.
    static let defaultTerms: [String] = [
        "nigger", "nigga", "niggers", "faggot", "faggots", "fag", "fags",
        "retard", "retards", "retarded", "chink", "chinks", "spic", "spics",
        "kike", "kikes", "wetback", "wetbacks", "coon", "coons", "gook", "gooks",
        "tranny", "trannies", "dyke", "dykes", "cunt", "cunts",
        "beaner", "beaners", "raghead", "sandnigger", "kanker",
        "kys", "rapist", "pedophile", "pedo", "molester",
    ]
}
