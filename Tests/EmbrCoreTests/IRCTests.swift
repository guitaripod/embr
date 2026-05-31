import Foundation
import Testing
@testable import EmbrCore

@Suite("IRC parsing")
struct IRCParserTests {
    @Test func parsesTagsPrefixCommandAndTrailing() {
        let line = "@id=abc;display-name=Foo :foo!foo@foo.tmi.twitch.tv PRIVMSG #bar :hello world"
        let msg = IRCMessage.parse(line)
        #expect(msg != nil)
        #expect(msg?.tags["id"] == "abc")
        #expect(msg?.tags["display-name"] == "Foo")
        #expect(msg?.prefix == "foo!foo@foo.tmi.twitch.tv")
        #expect(msg?.command == "PRIVMSG")
        #expect(msg?.parameters == ["#bar", "hello world"])
        #expect(msg?.nickname == "foo")
    }

    @Test func parsesCommandWithoutTagsOrPrefix() {
        let msg = IRCMessage.parse("PING :tmi.twitch.tv")
        #expect(msg?.command == "PING")
        #expect(msg?.prefix == nil)
        #expect(msg?.parameters == ["tmi.twitch.tv"])
    }

    @Test func splitsTagValueOnFirstEquals() {
        let msg = IRCMessage.parse("@emote-sets=0,1=2 :tmi.twitch.tv GLOBALUSERSTATE")
        #expect(msg?.tags["emote-sets"] == "0,1=2")
    }

    @Test func unescapesTagValues() {
        let line = "@system-msg=Foo\\sBar\\:baz\\\\end\\rA\\nB PRIVMSG #c :x"
        let msg = IRCMessage.parse(line)
        #expect(msg?.tags["system-msg"] == "Foo Bar;baz\\end\rA\nB")
    }

    @Test func trailingParamPreservesColonsAndSpaces() {
        let msg = IRCMessage.parse("PRIVMSG #c :a : b : c")
        #expect(msg?.parameters == ["#c", "a : b : c"])
    }

    @Test func returnsNilForEmptyLine() {
        #expect(IRCMessage.parse("") == nil)
        #expect(IRCMessage.parse("\r\n") == nil)
    }
}

@Suite("IRC mapping")
struct IRCMapperTests {
    @Test func mapsPrivmsgWithEmotesBadgesColorReply() {
        let line = "@badge-info=subscriber/12;badges=moderator/1,subscriber/12;color=#1E90FF;display-name=Cool_User;emotes=25:0-4,11-15;id=msg-1;reply-parent-display-name=Other;reply-parent-msg-body=hi\\sthere;reply-parent-msg-id=parent-9;reply-parent-user-id=999;reply-parent-user-login=other;room-id=room-1;tmi-sent-ts=1700000000000;user-id=42 :cool_user!cool_user@cool_user.tmi.twitch.tv PRIVMSG #broadcaster :Kappa heyo Kappa now"
        let msg = IRCMessage.parse(line)
        #expect(msg != nil)
        let chat = IRCMapper.chatMessage(from: msg!, channelID: "room-1")
        #expect(chat != nil)
        guard let chat else { return }

        #expect(chat.id == "msg-1")
        #expect(chat.channelID == "room-1")
        #expect(chat.author.id == "42")
        #expect(chat.author.login == "cool_user")
        #expect(chat.author.displayName == "Cool_User")
        #expect(chat.author.color == ChatColor(hex: "#1E90FF"))
        #expect(chat.timestamp == Date(timeIntervalSince1970: 1700000000))

        #expect(chat.fragments == [
            .emote(TwitchEmoteRef(id: "25", text: "Kappa")),
            .text(" heyo "),
            .emote(TwitchEmoteRef(id: "25", text: "Kappa")),
            .text(" now"),
        ])

        #expect(chat.badges == [
            MessageBadge(setID: "moderator", id: "1"),
            MessageBadge(setID: "subscriber", id: "12"),
        ])

        #expect(chat.reply == ReplyContext(
            parentMessageID: "parent-9",
            parentUserID: "999",
            parentLogin: "other",
            parentDisplayName: "Other",
            parentText: "hi there"
        ))
        #expect(chat.isAction == false)
    }

    @Test func emoteFragmentsOrderedByTagRangesAcrossSlashGroups() {
        let line = "@emotes=86:6-15/25:0-4;id=m;user-id=1;tmi-sent-ts=0 :u!u@u.tmi.twitch.tv PRIVMSG #c :Kappa BibleThump tail"
        let msg = IRCMessage.parse(line)!
        let chat = IRCMapper.chatMessage(from: msg, channelID: "c")!
        #expect(chat.fragments == [
            .emote(TwitchEmoteRef(id: "25", text: "Kappa")),
            .text(" "),
            .emote(TwitchEmoteRef(id: "86", text: "BibleThump")),
            .text(" tail"),
        ])
    }

    @Test func plainTextMessageHasSingleTextFragment() {
        let line = "@id=m;user-id=1;tmi-sent-ts=0 :u!u@u.tmi.twitch.tv PRIVMSG #c :just words"
        let msg = IRCMessage.parse(line)!
        let chat = IRCMapper.chatMessage(from: msg, channelID: "c")!
        #expect(chat.fragments == [.text("just words")])
    }

    @Test func stripsMeAction() {
        let line = "@id=m;user-id=1;tmi-sent-ts=0 :u!u@u.tmi.twitch.tv PRIVMSG #c :\u{1}ACTION waves at chat\u{1}"
        let msg = IRCMessage.parse(line)!
        let chat = IRCMapper.chatMessage(from: msg, channelID: "c")!
        #expect(chat.isAction == true)
        #expect(chat.fragments == [.text("waves at chat")])
    }

    @Test func usernoticeMapsNoticeWithUnescapedSystemMsg() {
        let line = "@badges=staff/1;id=n;login=ronni;msg-id=resub;system-msg=ronni\\shas\\ssubscribed\\sfor\\s6\\smonths!;tmi-sent-ts=1507246572675;user-id=1337 :tmi.twitch.tv USERNOTICE #dallas :Great stream"
        let msg = IRCMessage.parse(line)!
        let chat = IRCMapper.chatMessage(from: msg, channelID: "dallas")!
        #expect(chat.notice?.kind == .resub)
        #expect(chat.notice?.systemMessage == "ronni has subscribed for 6 months!")
        #expect(chat.author.login == "ronni")
        #expect(chat.fragments == [.text("Great stream")])
    }

    @Test func ignoresNonChatCommands() {
        let msg = IRCMessage.parse(":tmi.twitch.tv ROOMSTATE #c")!
        #expect(IRCMapper.chatMessage(from: msg, channelID: "c") == nil)
    }
}

@Suite("Recent messages backfill")
struct RecentMessagesParserTests {
    private static let lines = [
        "@id=1;user-id=10;display-name=Alice;tmi-sent-ts=0 :alice!alice@alice.tmi.twitch.tv PRIVMSG #c :first",
        ":tmi.twitch.tv ROOMSTATE #c",
        "@id=2;user-id=11;display-name=Bob;tmi-sent-ts=0 :bob!bob@bob.tmi.twitch.tv PRIVMSG #c :second",
        "@id=n;login=ronni;msg-id=sub;system-msg=ronni\\ssubscribed;tmi-sent-ts=0;user-id=12 :tmi.twitch.tv USERNOTICE #c :woo",
        "PING :tmi.twitch.tv",
    ]

    @Test func parsesLinesSkippingNonChat() {
        let messages = RecentMessagesParser.messages(fromLines: Self.lines, channelID: "c")
        #expect(messages.count == 3)
        #expect(messages.map(\.id) == ["1", "2", "n"])
        #expect(messages[0].author.displayName == "Alice")
        #expect(messages[2].notice?.kind == .sub)
    }

    @Test func parsesRecentMessagesJSON() throws {
        let json = """
        {"messages":["@id=1;user-id=10;tmi-sent-ts=0 :a!a@a.tmi.twitch.tv PRIVMSG #c :one","@id=2;user-id=11;tmi-sent-ts=0 :b!b@b.tmi.twitch.tv PRIVMSG #c :two"]}
        """
        let data = Data(json.utf8)
        let messages = RecentMessagesParser.messages(fromJSON: data, channelID: "c")
        #expect(messages.count == 2)
        #expect(messages.map(\.plainText) == ["one", "two"])
    }

    @Test func malformedJSONReturnsEmpty() {
        let messages = RecentMessagesParser.messages(fromJSON: Data("not json".utf8), channelID: "c")
        #expect(messages.isEmpty)
    }
}
