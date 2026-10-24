#if DEBUG
import Foundation
import EmbrCore

/// Scripted chat for the invented channels: a believable crowd of fictional chatters, a few
/// replies, a gifted sub, a raid and an announcement, the same every launch.
enum DemoChat {
    private struct Chatter {
        let login: String
        let name: String
        let color: String
        let badges: [String]
    }

    private static let chatters: [Chatter] = [
        Chatter(login: "marnie_k", name: "Marnie_K", color: "#FF6B8B", badges: ["subscriber"]),
        Chatter(login: "tobias_ward", name: "tobias_ward", color: "#5AA9FF", badges: ["moderator"]),
        Chatter(login: "yuki_nine", name: "yuki_nine", color: "#7BDCB5", badges: ["subscriber", "vip"]),
        Chatter(login: "grumblebee", name: "GrumbleBee", color: "#FFC857", badges: []),
        Chatter(login: "lena_f", name: "Lena_F", color: "#B06BFF", badges: ["subscriber"]),
        Chatter(login: "capn_biscuit", name: "CapnBiscuit", color: "#FF8A3D", badges: ["vip"]),
        Chatter(login: "ravi_p", name: "ravi_p", color: "#2EE6D6", badges: []),
        Chatter(login: "olive_and_ink", name: "OliveAndInk", color: "#9ACD32", badges: ["subscriber"]),
        Chatter(login: "dmitri_o", name: "Dmitri_O", color: "#FF4D4D", badges: ["moderator", "subscriber"]),
        Chatter(login: "sunny_bay", name: "SunnyBay", color: "#FFD23F", badges: []),
        Chatter(login: "kwame_plays", name: "KwamePlays", color: "#4DA6FF", badges: ["subscriber"]),
        Chatter(login: "noodlecat77", name: "noodlecat77", color: "#FF7AC6", badges: []),
        Chatter(login: "hilda_b", name: "Hilda_B", color: "#6BD6FF", badges: ["subscriber"]),
        Chatter(login: "pepper_jack", name: "PepperJack", color: "#E8506F", badges: []),
        Chatter(login: "inari_s", name: "inari_s", color: "#A0E060", badges: ["vip"]),
        Chatter(login: "bluebell_x", name: "bluebell_x", color: "#8AB4FF", badges: ["subscriber"]),
        Chatter(login: "mattias_r", name: "mattias_r", color: "#FFB454", badges: []),
        Chatter(login: "zoe_quartz", name: "Zoe_Quartz", color: "#C792EA", badges: ["subscriber"]),
        Chatter(login: "fennel_fox", name: "fennel_fox", color: "#FF9E64", badges: []),
        Chatter(login: "ahmed_t", name: "Ahmed_T", color: "#7EE787", badges: ["subscriber"])
    ]

    private static let general = [
        "hello everyone pogfox", "just got here, what did I miss?", "this is so good heartbeat", "clapfox clapfox clapfox",
        "lurking with tea cozycup", "first time catching you live!", "gg gg gg", "no way that just happened",
        "the music is perfect tonight", "o7", "chat is on fire today hypefox", "my cat is watching this with me",
        "can you zoom in a bit?", "love the new overlay", "been here since the first stream owlwave", "sadmoth that was so close",
        "popcornpanda", "ok that was clean", "what's the song?", "saving this clip for later",
        "hi from Lisbon!", "greetings from rainy Helsinki", "noodlelove noodlelove", "refreshing the page just to see more of this"
    ]

    private static let flavor: [String: [String]] = [
        "arena": ["that dodge was frame perfect", "the second boss pattern is brutal", "try the shield loadout next", "one more hit and it's over sadmoth", "the timing on that parry hypefox"],
        "space": ["don't forget fuel before the jump", "trade route to the outer ring looks profitable", "that freighter is overloaded lol", "the nebula looks incredible in this one"],
        "farm": ["the turnips are looking great", "rain means free watering cozycup", "put the beehives near the orchard", "south field is going to be gorgeous"],
        "road": ["brake earlier into that hairpin", "the grip on gravel is wild", "that was a perfect line", "slipstream him on the straight"],
        "dungeon": ["floor 40 is a trap room careful", "grab the key first!", "that slime is faster than it looks", "you have one potion left"],
        "studio": ["that loop is gorgeous", "can you add a bass line?", "key change at the bridge please", "this is going on my study playlist"],
        "board": ["Nf3 was better there", "he blundered the rook", "classic Sicilian ideas", "this endgame is so instructive"],
        "room": ["tell the story about the ferry again", "your setup looks so cozy", "how was your week?", "that's hilarious owlwave"],
        "canvas": ["the colour mixing is so smooth", "love the warm highlights", "what brush is that?", "the sky is stunning"],
        "peaks": ["the view from up there!", "wait is that a hidden path?", "build the bridge on the left side", "golden hour hits different"]
    ]

    private static func flavorKey(_ motif: DemoMotif) -> String {
        switch motif {
        case .arena: return "arena"
        case .space: return "space"
        case .farm: return "farm"
        case .road: return "road"
        case .dungeon: return "dungeon"
        case .studio: return "studio"
        case .board: return "board"
        case .room: return "room"
        case .canvas: return "canvas"
        case .peaks: return "peaks"
        }
    }

    private static func user(_ chatter: Chatter, index: Int) -> ChatUser {
        ChatUser(id: "8\(String(format: "%04d", index))", login: chatter.login, displayName: chatter.name, color: ChatColor(hex: chatter.color))
    }

    static func messages(for channel: ChannelInfo, count: Int = 64) -> [ChatMessage] {
        var random = DemoRandom(seed: "chat-" + channel.broadcasterLogin)
        let motif = DemoWorld.game(id: channel.gameID)?.motif ?? .room
        let lines = (flavor[flavorKey(motif)] ?? []) + general
        let now = Date()
        var result: [ChatMessage] = []
        for index in 0..<count {
            let position = Int(random.next() % UInt64(chatters.count))
            let chatter = chatters[position]
            let line = lines[Int(random.next() % UInt64(lines.count))]
            let stamp = now.addingTimeInterval(-TimeInterval(count - index) * 4.5)
            let badges = chatter.badges.map { MessageBadge(setID: $0, id: "1") }
            var fragments = [ChatFragment.text(line)]
            var reply: ReplyContext?
            var notice: ChannelNotice?
            var type = MessageType.regular
            var isAction = false
            if index == count - 14, let parent = result.last {
                reply = ReplyContext(
                    parentMessageID: parent.id, parentUserID: parent.author.id, parentLogin: parent.author.login,
                    parentDisplayName: parent.author.displayName, parentText: parent.plainText
                )
                fragments = [.text("agreed, that was the best part")]
            }
            if index == count - 9 {
                notice = ChannelNotice(kind: .resub, systemMessage: "\(chatter.name) subscribed with Prime. They've subscribed for 14 months!")
                fragments = [.text("14 months and still here heartbeat")]
            }
            if index == count - 20 {
                notice = ChannelNotice(kind: .raid, systemMessage: "18 raiders from SunnyBay have joined!")
                fragments = []
            }
            if index == count - 5 {
                isAction = true
                fragments = [.text("slides into chat with snacks")]
            }
            if index == count - 3 {
                type = .channelPointsHighlighted
                fragments = [.text("Highlighted: hydrate, you legend cozycup")]
            }
            result.append(ChatMessage(
                id: "demo-\(channel.broadcasterLogin)-\(index)",
                channelID: channel.id,
                timestamp: stamp,
                author: user(chatter, index: position),
                fragments: fragments,
                badges: badges,
                messageType: type,
                isAction: isAction,
                reply: reply,
                notice: notice
            ))
        }
        return result
    }
}

/// The chat connection for an invented channel: connects at once and replays the scripted history.
final class DemoChatSource: ChatSource {
    private let channel: ChannelInfo

    init(channel: ChannelInfo) {
        self.channel = channel
    }

    func start() -> AsyncStream<ChatEvent> {
        let channel = self.channel
        return AsyncStream { continuation in
            continuation.yield(.connection(.connected))
            continuation.yield(.roomState(RoomState()))
            for message in DemoChat.messages(for: channel) {
                continuation.yield(.message(message))
            }
        }
    }

    func stop() async {}

    func send(_ text: String, replyParentID: String?) async throws -> SendResult {
        SendResult(messageID: "demo-sent", isSent: true)
    }
}
#endif
