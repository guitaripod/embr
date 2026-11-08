import Foundation
import EmbrCore

/// Studio's sample stream: an invented painter's channel whose chat and alerts follow a three-minute script that
/// reaches every moment Studio has. It is the first thing a new streamer can try, the App Store screenshots and App
/// Review's quick path through the app, and it never touches the network or a Twitch account.
enum StudioSample {
    static let channel = ChannelInfo(
        id: "sample-mossandmirrors",
        broadcasterLogin: "mossandmirrors",
        broadcasterName: "MossAndMirrors",
        gameID: "",
        gameName: "Art",
        title: "Painting a lighthouse in gouache, requests welcome",
        language: "en",
        isLive: true
    )

    static let features = Set(StudioFeature.allCases)

    /// The script's length; it loops after this.
    static let loop: TimeInterval = 180

    struct Chatter: Sendable {
        let name: String
        let color: ChatColor
    }

    static let chatters: [Chatter] = [
        Chatter(name: "fernwick", color: ChatColor(red: 127, green: 209, blue: 255)),
        Chatter(name: "tidepoolsam", color: ChatColor(red: 255, green: 179, blue: 107)),
        Chatter(name: "lumen_owl", color: ChatColor(red: 201, green: 168, blue: 255)),
        Chatter(name: "pebblecat", color: ChatColor(red: 143, green: 240, blue: 199)),
        Chatter(name: "quillandmoss", color: ChatColor(red: 255, green: 154, blue: 168)),
        Chatter(name: "hollowreed", color: ChatColor(red: 255, green: 211, blue: 107)),
        Chatter(name: "kitebright", color: ChatColor(red: 127, green: 209, blue: 255)),
        Chatter(name: "driftwooddan", color: ChatColor(red: 155, green: 211, blue: 168)),
        Chatter(name: "mintleaf_", color: ChatColor(red: 255, green: 179, blue: 107)),
        Chatter(name: "starlingrun", color: ChatColor(red: 255, green: 154, blue: 168)),
    ]

    static let lines: [String] = [
        "the gradient on that sky is unreal 😍",
        "what brush is that, a size 6 round?",
        "reminder: requests go in the !queue",
        "back from dinner, did the lighthouse get its light yet",
        "@MossAndMirrors the reflection in the water 💛",
        "first time here, this is so calming",
        "LETS GO 🔥🔥",
        "can you do a stormy one next time",
        "gouache is so forgiving on the second layer 🎨",
        "the little boat 😂",
        "saving this palette for later",
        "chat is so wholesome tonight 💛",
        "does the paper buckle with that much water?",
        "the foam on the rocks is perfect",
        "how long have you been painting?",
        "@MossAndMirrors can we see the reference photo?",
    ]

    /// The script: when each moment happens, in seconds from the start of a loop.
    static func script(loopStart: Date) -> [(TimeInterval, StudioEvent)] {
        let at = { (offset: TimeInterval) in loopStart.addingTimeInterval(offset) }
        func follow(_ name: String, _ offset: TimeInterval) -> (TimeInterval, StudioEvent) {
            (offset, .follow(StudioFollow(userID: "sample-\(name)-\(Int(loopStart.timeIntervalSince1970))", userName: name, followedAt: at(offset))))
        }
        let stamp = Int(loopStart.timeIntervalSince1970)
        return [
            follow("hollowreed", 4),
            (10, .subscription(StudioSubscription(id: "s1-\(stamp)", userID: "sample-fernwick", userName: "fernwick", kind: .resub(months: 14), tier: .one, isPrime: false, message: "still the comfiest stream"))),
            (18, .cheer(StudioCheer(id: "c1-\(stamp)", userID: "sample-quill", userName: "quillandmoss", bits: 500, message: "Cheer500 for the lighthouse fund"))),
            follow("starlingrun", 24),
            follow("mintleaf_", 27),
            (34, .giftBomb(StudioGiftBomb(id: "g1-\(stamp)", gifterID: "sample-copperlark", gifterName: "copperlark", count: 10, tier: .one))),
            (50, .poll(StudioPoll(id: "p-\(stamp)", title: "Next painting?", choices: pollChoices(0), endsAt: at(110), phase: .open))),
            (62, .poll(StudioPoll(id: "p-\(stamp)", title: "Next painting?", choices: pollChoices(1), endsAt: at(110), phase: .open))),
            (66, .redemption(StudioRedemption(id: "r1-\(stamp)", userID: "sample-pebble", userName: "pebblecat", rewardTitle: "Pick the next colour", cost: 2000, input: "teal"))),
            (80, .poll(StudioPoll(id: "p-\(stamp)", title: "Next painting?", choices: pollChoices(2), endsAt: at(110), phase: .open))),
            (98, .poll(StudioPoll(id: "p-\(stamp)", title: "Next painting?", choices: pollChoices(3), endsAt: at(110), phase: .ended))),
            (112, .raid(StudioRaid(raiderID: "sample-nightjar", raiderName: "Nightjar", raiderLogin: "nightjar", viewers: 312, profileImageURL: nil))),
            (128, .hypeTrain(hype(stamp: stamp, level: 1, progress: 420, total: 420, expires: at(128 + 300), phase: .running))),
            (136, .hypeTrain(hype(stamp: stamp, level: 2, progress: 180, total: 1180, expires: at(136 + 300), phase: .running))),
            (146, .hypeTrain(hype(stamp: stamp, level: 3, progress: 680, total: 2680, expires: at(146 + 300), phase: .running))),
            (158, .hypeTrain(hype(stamp: stamp, level: 3, progress: 680, total: 2680, expires: nil, phase: .ended))),
            follow("tidepoolsam", 164),
            (170, .subscription(StudioSubscription(id: "s2-\(stamp)", userID: "sample-kite", userName: "kitebright", kind: .new, tier: .one, isPrime: true, message: ""))),
        ]
    }

    private static func pollChoices(_ step: Int) -> [StudioChoice] {
        let votes = [[0, 0, 0], [21, 12, 4], [44, 25, 9], [58, 31, 11]][min(step, 3)]
        return [
            StudioChoice(id: "a", title: "Stormy harbour", votes: votes[0]),
            StudioChoice(id: "b", title: "Northern lights", votes: votes[1]),
            StudioChoice(id: "c", title: "Foggy forest", votes: votes[2]),
        ]
    }

    private static func hype(stamp: Int, level: Int, progress: Int, total: Int, expires: Date?, phase: StudioHypeTrain.Phase) -> StudioHypeTrain {
        StudioHypeTrain(
            id: "h-\(stamp)",
            phase: phase,
            level: level,
            progress: progress,
            goal: 1000,
            total: total,
            expiresAt: expires,
            topContributors: [
                StudioContributor(userName: "copperlark", kind: .subscription, total: 5000),
                StudioContributor(userName: "quillandmoss", kind: .bits, total: 500),
            ],
            isGolden: false
        )
    }

    /// The ad schedule the sample opens with: a mid-roll in 4 minutes 32 seconds and two snoozes left.
    static func schedule(now: Date) -> AdSchedule {
        AdSchedule(
            nextAdAt: now.addingTimeInterval(272),
            lastAdAt: now.addingTimeInterval(-1500),
            duration: 90,
            prerollFreeSeconds: 0,
            snoozeCount: 2,
            snoozeRefreshAt: now.addingTimeInterval(1200),
            fetchedAt: now
        )
    }
}

/// The sample's live events: its script, played on a loop.
@MainActor
final class SampleStudioFeed: StudioEventFeeding {
    func signals(channel: ChannelInfo, role: StudioRole, features: Set<StudioFeature>, listener: UUID) -> AsyncStream<EventSubChatHub.StudioSignal> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let loopStart = Date()
                    for (offset, event) in StudioSample.script(loopStart: loopStart) {
                        let wait = loopStart.addingTimeInterval(offset).timeIntervalSinceNow
                        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                        guard !Task.isCancelled else { return }
                        continuation.yield(.event(event))
                    }
                    let rest = loopStart.addingTimeInterval(StudioSample.loop).timeIntervalSinceNow
                    if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The sample's chat: invented chatters saying gentle things about a painting, about one message a second.
final class StudioSampleChatSource: ChatSource {
    private let channel: ChannelInfo

    init(channel: ChannelInfo) {
        self.channel = channel
    }

    func start() -> AsyncStream<ChatEvent> {
        let channel = channel
        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(.connection(.connected))
                var sequence = 0
                while !Task.isCancelled {
                    let chatter = StudioSample.chatters[(sequence * 7 + sequence / 3) % StudioSample.chatters.count]
                    let line = StudioSample.lines[(sequence * 5 + 3) % StudioSample.lines.count]
                    continuation.yield(.message(ChatMessage(
                        id: "sample-\(sequence)-\(Int(Date().timeIntervalSince1970))",
                        channelID: channel.id,
                        timestamp: Date(),
                        author: ChatUser(id: "sample-\(chatter.name)", login: chatter.name, displayName: chatter.name, color: chatter.color),
                        fragments: [.text(line)],
                        badges: []
                    )))
                    sequence += 1
                    let pause = 0.8 + Double((sequence * 37) % 9) / 10
                    try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {}

    func send(_ text: String, replyParentID: String?) async throws -> SendResult {
        SendResult(messageID: UUID().uuidString, isSent: true, dropReason: nil)
    }
}

/// Twitch as the sample stream sees it: snoozes and ads always work, everything else answers like a quiet channel.
final class SampleStudioAPI: StudioAPI {
    func adSchedule(broadcasterID: String) async throws -> AdSchedule? { StudioSample.schedule(now: Date()) }

    func snoozeNextAd(broadcasterID: String, previous: AdSchedule?) async throws -> AdSchedule? {
        let now = Date()
        guard let previous, previous.snoozeCount > 0 else { throw APIError.rateLimited(resetAt: nil) }
        return AdSchedule(
            nextAdAt: (previous.nextAdAt ?? now).addingTimeInterval(300),
            lastAdAt: previous.lastAdAt,
            duration: previous.duration,
            prerollFreeSeconds: previous.prerollFreeSeconds,
            snoozeCount: previous.snoozeCount - 1,
            snoozeRefreshAt: previous.snoozeRefreshAt,
            fetchedAt: now
        )
    }

    func startCommercial(broadcasterID: String, length: Int) async throws -> CommercialResult? {
        CommercialResult(length: length, retryAfter: 480, message: "")
    }

    func hypeTrain(broadcasterID: String) async throws -> StudioHypeTrain? { nil }
    func activePoll(broadcasterID: String) async throws -> StudioPoll? { nil }
    func activePrediction(broadcasterID: String) async throws -> StudioPrediction? { nil }
    func goals(broadcasterID: String) async throws -> [StudioGoal] { [] }
    func followers(broadcasterID: String) async throws -> (total: Int, recent: [StudioFollow]) { (1_284, []) }
    func liveStream(broadcasterID: String) async throws -> LiveStream? { nil }
    func user(id: String) async throws -> TwitchUser? { nil }
    func schedule(broadcasterID: String) async throws -> [ScheduleSegment] { [] }
    func moderatedChannels(userID: String) async throws -> [ModeratedChannel] { [] }
    func shoutout(fromBroadcasterID: String, toBroadcasterID: String, moderatorID: String) async throws {}
    func pin(broadcasterID: String, moderatorID: String, messageID: String) async throws {}
    func changeChatMode(broadcasterID: String, moderatorID: String, change: ChatModeChange) async throws {}
    func setShieldMode(broadcasterID: String, moderatorID: String, active: Bool) async throws {}
    func shieldModeActive(broadcasterID: String, moderatorID: String) async throws -> Bool? { false }
}
