import Foundation
import Testing
@testable import EmbrCore

@Suite struct ChatHighlighterTests {
    private func message(_ text: String, from login: String = "someone", fragments: [ChatFragment]? = nil) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            channelID: "1",
            timestamp: Date(),
            author: ChatUser(id: "u-\(login)", login: login, displayName: login),
            fragments: fragments ?? [.text(text)]
        )
    }

    @Test func mentionsByMentionFragment() {
        let highlighter = ChatHighlighter(login: "emberfan", mentions: true)
        let ref = MentionRef(userID: "9", login: "emberfan", displayName: "EmberFan")
        #expect(highlighter.reason(for: message("", fragments: [.text("hey "), .mention(ref)])) == .mention)
    }

    @Test func mentionsByAtNameOrBareNameButNotInsideAnotherName() {
        let highlighter = ChatHighlighter(login: "EmberFan", mentions: true)
        #expect(highlighter.reason(for: message("@emberfan nice play")) == .mention)
        #expect(highlighter.reason(for: message("emberfan you there?")) == .mention)
        #expect(highlighter.reason(for: message("emberfan2 is someone else")) == nil)
        #expect(highlighter.reason(for: message("xemberfan")) == nil)
    }

    @Test func mentionsCanBeTurnedOff() {
        let highlighter = ChatHighlighter(login: "emberfan", mentions: false)
        #expect(highlighter.reason(for: message("@emberfan hi")) == nil)
        #expect(highlighter.isEmpty)
    }

    @Test func ownMessagesNeverStandOut() {
        let highlighter = ChatHighlighter(login: "emberfan", mentions: true, words: ["gg"], users: ["emberfan"])
        #expect(highlighter.reason(for: message("gg @emberfan", from: "EmberFan")) == nil)
    }

    @Test func wordsMatchWholeIgnoringCaseAndAccents() {
        let highlighter = ChatHighlighter(login: nil, mentions: true, words: ["GG", "café"])
        #expect(highlighter.reason(for: message("gg wp")) == .word)
        #expect(highlighter.reason(for: message("GG!")) == .word)
        #expect(highlighter.reason(for: message("eggs for breakfast")) == nil)
        #expect(highlighter.reason(for: message("meet at the CAFE")) == .word)
    }

    @Test func phrasesMatchAnywhere() {
        let highlighter = ChatHighlighter(login: nil, mentions: false, words: ["good game", "!drop"])
        #expect(highlighter.reason(for: message("that was a Good Game everyone")) == .word)
        #expect(highlighter.reason(for: message("type !drops to claim")) == .word)
        #expect(highlighter.reason(for: message("good luck")) == nil)
    }

    @Test func chosenUsersWinOverMentionsAndWords() {
        let highlighter = ChatHighlighter(login: "emberfan", mentions: true, words: ["gg"], users: ["Streamer_Bob"])
        #expect(highlighter.reason(for: message("gg @emberfan", from: "streamer_bob")) == .user)
        #expect(highlighter.reason(for: message("gg @emberfan", from: "other")) == .mention)
        #expect(highlighter.reason(for: message("gg", from: "other")) == .word)
    }

    @Test func blankTermsAreIgnored() {
        let highlighter = ChatHighlighter(login: nil, mentions: true, words: ["", "   "], users: [""])
        #expect(highlighter.isEmpty)
        #expect(highlighter.reason(for: message("anything")) == nil)
    }
}
