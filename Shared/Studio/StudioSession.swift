import Combine
import Foundation
import EmbrCore
import MidgarCore

/// Where a Studio session's live events come from: the shared EventSub connection, or the sample stream's script.
@MainActor
protocol StudioEventFeeding: AnyObject {
    func signals(channel: ChannelInfo, role: StudioRole, features: Set<StudioFeature>, listener: UUID) -> AsyncStream<EventSubChatHub.StudioSignal>
}

@MainActor
final class LiveStudioFeed: StudioEventFeeding {
    func signals(channel: ChannelInfo, role: StudioRole, features: Set<StudioFeature>, listener: UUID) -> AsyncStream<EventSubChatHub.StudioSignal> {
        EventSubChatHub.shared.joinStudio(channel, role: role, features: features, listener: listener)
    }
}

/// One Studio screen's live state for one channel: chat, the channel's numbers, the ad clock, the alert feed and its
/// banners, hype trains, polls, predictions, goals and the stream's tally. Every screen (Apple TV, iPad, iPhone) draws
/// from this; nothing here knows how it is drawn. Changes go out as whole snapshots, at most a few a second.
@MainActor
final class StudioSession {
    struct Snapshot: Equatable {
        var channel: ChannelInfo
        var role: StudioRole
        var features: Set<StudioFeature>
        var isSample: Bool
        var avatarURL: URL?
        var isAffiliate: Bool
        var isLive: Bool
        var startedAt: Date?
        var viewers: Int?
        var viewerHistory: [Int] = []
        var title: String
        var category: String
        var adClock = AdBreakClock()
        var feed: [StudioFeedItem] = []
        var banner: StudioBanner?
        var hypeTrain: StudioHypeTrain?
        var poll: StudioPoll?
        var prediction: StudioPrediction?
        var goal: StudioGoal?
        var sharedChat: StudioSharedChat?
        var shieldMode = false
        var spamWave = false
        var followerTotal: Int?
        var tally: SessionTally?
        var recap: SessionTally?
        var wentOfflineAt: Date?
        var nextStream: ScheduleSegment?
        var revoked: Set<String> = []
        var awayFor: TimeInterval?
        var now = Date()

        /// Whether a feature is both granted and possible for this role and channel.
        func can(_ feature: StudioFeature) -> Bool {
            guard features.contains(feature) else { return false }
            if feature.isBroadcasterOnly, role != .broadcaster { return false }
            switch feature {
            case .adBreaks, .runAds, .support, .pollsAndPredictions, .channelPoints: return isAffiliate || isSample
            default: return true
            }
        }
    }

    enum ActionError: Error, Equatable {
        case needsPro
        case unavailable
        case noSnoozesLeft
        case refused(String)
    }

    let changes = PassthroughSubject<Snapshot, Never>()
    let sounds = PassthroughSubject<StudioSound, Never>()
    let toasts = PassthroughSubject<String, Never>()
    let chat: ChatViewModel
    private(set) var snapshot: Snapshot

    private let userID: String
    private let api: StudioAPI
    private let feed: StudioEventFeeding
    private let hasPro: () -> Bool
    private let recaps: StudioRecapStore
    private var alerts: AlertQueue
    private var spam = SpamWaveDetector()
    private var listener = UUID()
    private var signalTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastTick = Date()
    private var momentClears: [String: Date] = [:]
    private var suspendedAt: Date?
    private var started = false

    private static let pollInterval: TimeInterval = 60
    private static let resultShown: TimeInterval = 10
    private static let historyLength = 30

    init(
        channel: ChannelInfo,
        role: StudioRole,
        features: Set<StudioFeature>,
        userID: String,
        isSample: Bool,
        chat: ChatViewModel,
        api: StudioAPI,
        feed: StudioEventFeeding,
        preferences: AlertPreferences,
        hasPro: @escaping () -> Bool,
        recaps: StudioRecapStore = StudioRecapStore()
    ) {
        self.userID = userID
        self.api = api
        self.feed = feed
        self.chat = chat
        self.hasPro = hasPro
        self.recaps = recaps
        alerts = AlertQueue(preferences: preferences)
        snapshot = Snapshot(
            channel: channel,
            role: role,
            features: features,
            isSample: isSample,
            isAffiliate: false,
            isLive: false,
            title: channel.title,
            category: channel.gameName
        )
        snapshot.recap = recaps.recap(for: channel.id, now: Date())
    }

    func start() {
        guard !started else { return }
        started = true
        chat.start()
        chat.arrivalsSubject
            .sink { [weak self] messages in self?.checkSpam(messages) }
            .store(in: &cancellables)
        if snapshot.isSample { seedSample() }
        listen()
        startTicking()
        startPolling()
        MidgarLog.info("Studio started for \(snapshot.channel.broadcasterLogin) as \(snapshot.role), \(snapshot.features.count) feature(s)\(snapshot.isSample ? ", sample" : "")", category: .studio)
    }

    func stop() {
        guard started else { return }
        started = false
        signalTask?.cancel()
        pollTask?.cancel()
        tickTask?.cancel()
        cancellables.removeAll()
        chat.stop()
        saveTally()
        MidgarLog.info("Studio stopped for \(snapshot.channel.broadcasterLogin)", category: .studio)
    }

    /// The screen left the foreground: the system suspends the app soon, and Twitch drops the subscriptions with the
    /// connection.
    func suspend() {
        suspendedAt = Date()
        saveTally()
    }

    /// Back on screen: chat reconnects, the live state and every moment in progress are read again, and the feed says
    /// how long Studio was away.
    func resume() {
        guard let suspendedAt else { return }
        self.suspendedAt = nil
        let away = Date().timeIntervalSince(suspendedAt)
        chat.wake()
        if away > 20 {
            snapshot.awayFor = away
            listen()
            Task { await refreshEverything() }
        }
        publish()
    }

    func dismissAway() {
        snapshot.awayFor = nil
        publish()
    }

    func dismissBanner() {
        alerts.dismissBanner(at: Date())
        snapshot.banner = alerts.banner
        publish()
    }

    func dismissSpamWarning() {
        snapshot.spamWave = false
        publish()
    }

    func updatePreferences(_ preferences: AlertPreferences) {
        alerts.preferences = preferences
    }

    func snooze() async throws {
        guard snapshot.can(.adBreaks) else { throw ActionError.unavailable }
        guard hasPro() else { throw ActionError.needsPro }
        guard snapshot.adClock.snoozesLeft > 0 else { throw ActionError.noSnoozesLeft }
        do {
            if let schedule = try await api.snoozeNextAd(broadcasterID: snapshot.channel.id, previous: snapshot.adClock.schedule) {
                snapshot.adClock.apply(schedule)
            }
            snapshot.tally?.recordSnooze()
            publish()
            MidgarLog.info("Studio snoozed the next ad", category: .studio)
        } catch APIError.rateLimited {
            throw ActionError.noSnoozesLeft
        } catch {
            MidgarLog.notice("Studio snooze failed: \(error)", category: .studio)
            throw ActionError.refused(Self.describe(error))
        }
    }

    func runAd(length: Int) async throws {
        guard snapshot.can(.runAds) else { throw ActionError.unavailable }
        guard hasPro() else { throw ActionError.needsPro }
        do {
            let result = try await api.startCommercial(broadcasterID: snapshot.channel.id, length: length)
            let now = Date()
            if let result, result.length > 0 {
                snapshot.adClock.apply(StudioAdBreak(startedAt: now, duration: TimeInterval(result.length), isAutomatic: false))
                if result.retryAfter > 0 { snapshot.adClock.refuseManualAd(until: now.addingTimeInterval(result.retryAfter)) }
            }
            publish()
            MidgarLog.info("Studio ran a \(result?.length ?? length) s ad", category: .studio)
            if !snapshot.isSample { Task { await self.refreshAds() } }
        } catch {
            MidgarLog.notice("Studio run ad failed: \(error)", category: .studio)
            throw ActionError.refused(Self.describe(error))
        }
    }

    func shoutout(toBroadcasterID: String) async throws {
        guard snapshot.can(.moderation) else { throw ActionError.unavailable }
        do {
            try await api.shoutout(fromBroadcasterID: snapshot.channel.id, toBroadcasterID: toBroadcasterID, moderatorID: userID)
        } catch {
            throw ActionError.refused(Self.describe(error))
        }
    }

    func pin(messageID: String) async throws {
        guard snapshot.can(.moderation) else { throw ActionError.unavailable }
        do {
            try await api.pin(broadcasterID: snapshot.channel.id, moderatorID: userID, messageID: messageID)
        } catch {
            throw ActionError.refused(Self.describe(error))
        }
    }

    func changeChatMode(_ change: ChatModeChange) async throws {
        guard snapshot.can(.moderation) else { throw ActionError.unavailable }
        do {
            try await api.changeChatMode(broadcasterID: snapshot.channel.id, moderatorID: userID, change: change)
        } catch {
            throw ActionError.refused(Self.describe(error))
        }
    }

    func setShieldMode(_ active: Bool) async throws {
        guard snapshot.can(.moderation) else { throw ActionError.unavailable }
        do {
            try await api.setShieldMode(broadcasterID: snapshot.channel.id, moderatorID: userID, active: active)
            snapshot.shieldMode = active
            snapshot.spamWave = false
            publish()
        } catch {
            throw ActionError.refused(Self.describe(error))
        }
    }

    #if DEBUG
    func seedAdForScreenshot(nextIn seconds: TimeInterval) {
        let now = Date()
        snapshot.adClock.apply(AdSchedule(nextAdAt: now.addingTimeInterval(seconds), lastAdAt: now.addingTimeInterval(-1500), duration: 90, prerollFreeSeconds: 0, snoozeCount: 2, snoozeRefreshAt: now.addingTimeInterval(1200), fetchedAt: now))
        publish()
    }

    func showOfflineForScreenshot() {
        let now = Date()
        var recap = SessionTally(startedAt: now.addingTimeInterval(-(3 * 3600 + 27 * 60) - 7200))
        recap.followers = 38
        recap.subscriptions = 9
        recap.giftedSubscriptions = 13
        recap.bits = 1_840
        recap.adBreaks = 3
        recap.adSeconds = 450
        recap.record(viewers: 214)
        recap.end(at: now.addingTimeInterval(-7200))
        snapshot.isSample = false
        snapshot.isLive = false
        snapshot.recap = recap
        snapshot.nextStream = ScheduleSegment(id: "shot", startTime: Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: now.addingTimeInterval(86_400)) ?? now, endTime: nil, title: "Watercolour night: harbour at dusk", categoryName: "Art", isRecurring: true, canceledUntil: nil)
        publish()
    }
    #endif

    private func listen() {
        signalTask?.cancel()
        listener = UUID()
        let stream = feed.signals(channel: snapshot.channel, role: snapshot.role, features: snapshot.features, listener: listener)
        signalTask = Task { [weak self] in
            for await signal in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(signal)
            }
        }
    }

    private func handle(_ signal: EventSubChatHub.StudioSignal) {
        switch signal {
        case .event(let event):
            apply(event, at: Date())
        case .revoked(let type, let reason):
            snapshot.revoked.insert(type)
            MidgarLog.notice("Studio subscription \(type) revoked: \(reason)", category: .studio)
            publish()
        }
    }

    /// Applies one event. Public to the sample stream, which drives the session without Twitch.
    func apply(_ event: StudioEvent, at now: Date) {
        let outcome = alerts.ingest(event, at: now)
        if outcome.feedChanged {
            snapshot.feed = alerts.feed
            snapshot.banner = alerts.banner
            if snapshot.isLive { snapshot.tally?.record(event) }
        }
        if let sound = outcome.sound { sounds.send(sound) }
        switch event {
        case .streamOnline(let startedAt):
            goLive(startedAt: startedAt)
        case .streamOffline:
            goOffline(at: now)
        case .adBreakBegan(let adBreak):
            snapshot.adClock.apply(adBreak)
            snapshot.tally?.record(event)
            if !snapshot.isSample { Task { await self.refreshAds() } }
        case .channelUpdated(let title, let category):
            snapshot.title = title
            snapshot.category = category
        case .hypeTrain(let train):
            if let previous = snapshot.hypeTrain, train.level > previous.level, alerts.preferences.sounds.contains(.hypeTrain) {
                sounds.send(.hypeTrain)
            } else if snapshot.hypeTrain == nil, train.phase == .running, alerts.preferences.sounds.contains(.hypeTrain) {
                sounds.send(.hypeTrain)
            }
            snapshot.hypeTrain = train
            if train.phase == .ended { momentClears["hype"] = now.addingTimeInterval(Self.resultShown) }
        case .poll(let poll):
            snapshot.poll = poll
            if poll.phase == .ended { momentClears["poll"] = now.addingTimeInterval(Self.resultShown) }
        case .prediction(let prediction):
            snapshot.prediction = prediction
            switch prediction.phase {
            case .resolved, .canceled: momentClears["prediction"] = now.addingTimeInterval(Self.resultShown)
            default: break
            }
        case .goal(let goal):
            if goal.ended, goal.achieved, alerts.preferences.sounds.contains(.goal) { sounds.send(.goal) }
            snapshot.goal = goal
            if goal.ended { momentClears["goal"] = now.addingTimeInterval(Self.resultShown) }
        case .sharedChat(let shared):
            snapshot.sharedChat = shared
        case .shieldMode(let active):
            snapshot.shieldMode = active
            if active { snapshot.spamWave = false }
        default:
            break
        }
        publish()
    }

    private func goLive(startedAt: Date) {
        let wasLive = snapshot.isLive
        snapshot.isLive = true
        snapshot.startedAt = startedAt
        snapshot.wentOfflineAt = nil
        if snapshot.tally?.startedAt != startedAt {
            snapshot.tally = recaps.liveTally(for: snapshot.channel.id, startedAt: startedAt) ?? SessionTally(startedAt: startedAt)
        }
        if !wasLive {
            MidgarLog.info("Studio: \(snapshot.channel.broadcasterLogin) is live", category: .studio)
            if !snapshot.isSample { Task { await self.refreshEverything() } }
        }
    }

    private func goOffline(at now: Date) {
        guard snapshot.isLive else { return }
        snapshot.isLive = false
        snapshot.wentOfflineAt = now
        snapshot.viewers = nil
        snapshot.adClock.reset()
        if var tally = snapshot.tally {
            tally.end(at: now)
            snapshot.recap = tally
            recaps.save(recap: tally, for: snapshot.channel.id)
        }
        snapshot.tally = nil
        snapshot.hypeTrain = nil
        snapshot.poll = nil
        snapshot.prediction = nil
        MidgarLog.info("Studio: \(snapshot.channel.broadcasterLogin) went offline", category: .studio)
        if !snapshot.isSample { Task { await self.refreshSchedule() } }
    }

    private func checkSpam(_ messages: [ChatMessage]) {
        guard snapshot.isLive, !snapshot.shieldMode, snapshot.can(.moderation) else { return }
        let now = Date()
        var detected = false
        for message in messages where message.notice == nil {
            let text = message.plainText
            if spam.ingest(text: text, user: message.author.id.isEmpty ? message.author.login : message.author.id, at: now) {
                detected = true
            }
        }
        guard detected else { return }
        snapshot.spamWave = true
        if alerts.preferences.sounds.contains(.alarm) { sounds.send(.alarm) }
        MidgarLog.notice("Studio: spam wave in \(snapshot.channel.broadcasterLogin)", category: .studio)
        publish()
    }

    /// The sample stream opens two hours into a live painting stream, with an ad due and a goal half done.
    private func seedSample() {
        let now = Date()
        snapshot.isAffiliate = true
        goLive(startedAt: now.addingTimeInterval(-(2 * 3600 + 14 * 60)))
        snapshot.tally = SessionTally(startedAt: snapshot.startedAt ?? now)
        snapshot.viewerHistory = [151, 158, 163, 160, 171, 176, 174, 183, 188, 184, 192, 197, 194, 201, 206]
        snapshot.viewers = snapshot.viewerHistory.last
        snapshot.followerTotal = 1_284
        snapshot.adClock.apply(StudioSample.schedule(now: now))
        snapshot.goal = StudioGoal(id: "sample-goal", kind: "follow", description: "", current: 1_284, target: 1_300, ended: false, achieved: false)
        snapshot.recap = nil
    }

    /// Moves the sample's viewer count a little every so often, as a real channel's would.
    private func driftSampleViewers(_ now: Date) {
        guard snapshot.isSample, Int(now.timeIntervalSince1970) % 6 == 0, let viewers = snapshot.viewers else { return }
        let step = [3, -2, 5, 1, -1, 4, 2, -3][Int(now.timeIntervalSince1970 / 6) % 8]
        let next = max(120, viewers + step)
        snapshot.viewers = next
        snapshot.viewerHistory = Array((snapshot.viewerHistory + [next]).suffix(Self.historyLength))
        snapshot.tally?.record(viewers: next)
        if snapshot.adClock.schedule?.nextAdAt.map({ $0 < now.addingTimeInterval(-200) }) ?? true {
            snapshot.adClock.apply(StudioSample.schedule(now: now))
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        lastTick = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        if let warning = snapshot.adClock.warning(between: lastTick, and: now), alerts.preferences.sounds.contains(.adWarning) {
            sounds.send(.adWarning)
            if warning == .oneMinute { MidgarLog.info("Studio: ad break in a minute", category: .studio) }
        }
        lastTick = now
        if alerts.tick(at: now) { snapshot.banner = alerts.banner }
        for (moment, at) in momentClears where now >= at {
            momentClears[moment] = nil
            switch moment {
            case "hype": snapshot.hypeTrain = nil
            case "poll": snapshot.poll = nil
            case "prediction": snapshot.prediction = nil
            case "goal": snapshot.goal = nil
            default: break
            }
        }
        driftSampleViewers(now)
        snapshot.now = now
        publish()
    }

    private func startPolling() {
        pollTask?.cancel()
        guard !snapshot.isSample else { return }
        pollTask = Task { [weak self] in
            await self?.refreshEverything()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await self.refreshStream()
                if self.snapshot.isLive {
                    await self.refreshAds()
                    self.saveTally()
                }
            }
        }
    }

    private func refreshEverything() async {
        await refreshChannelOwner()
        await refreshStream()
        guard snapshot.isLive else {
            await refreshSchedule()
            return
        }
        await refreshAds()
        await refreshMoments()
        await refreshFollowers()
    }

    private func refreshChannelOwner() async {
        guard let user = try? await api.user(id: snapshot.channel.id) else { return }
        snapshot.avatarURL = user.profileImageURL
        snapshot.isAffiliate = user.broadcasterType == "affiliate" || user.broadcasterType == "partner"
        publish()
    }

    private func refreshStream() async {
        do {
            let stream = try await api.liveStream(broadcasterID: snapshot.channel.id)
            if let stream {
                goLive(startedAt: stream.startedAt)
                snapshot.viewers = stream.viewerCount
                snapshot.viewerHistory = Array((snapshot.viewerHistory + [stream.viewerCount]).suffix(Self.historyLength))
                snapshot.title = stream.title
                snapshot.category = stream.gameName
                snapshot.tally?.record(viewers: stream.viewerCount)
            } else if snapshot.isLive {
                goOffline(at: Date())
            }
            publish()
        } catch {
            MidgarLog.notice("Studio stream read failed: \(error)", category: .studio)
        }
    }

    private func refreshAds() async {
        guard snapshot.isLive, snapshot.role == .broadcaster, snapshot.features.contains(.adBreaks), snapshot.isAffiliate else { return }
        do {
            if let schedule = try await api.adSchedule(broadcasterID: snapshot.channel.id) {
                snapshot.adClock.apply(schedule)
                publish()
            }
        } catch {
            MidgarLog.notice("Studio ad schedule read failed: \(error)", category: .studio)
        }
    }

    private func refreshMoments() async {
        guard snapshot.role == .broadcaster else { return }
        let id = snapshot.channel.id
        if snapshot.features.contains(.hypeTrainsAndGoals) {
            snapshot.hypeTrain = (try? await api.hypeTrain(broadcasterID: id)) ?? snapshot.hypeTrain
            snapshot.goal = (try? await api.goals(broadcasterID: id))?.first ?? snapshot.goal
        }
        if snapshot.features.contains(.pollsAndPredictions), snapshot.isAffiliate {
            snapshot.poll = (try? await api.activePoll(broadcasterID: id)) ?? snapshot.poll
            snapshot.prediction = (try? await api.activePrediction(broadcasterID: id)) ?? snapshot.prediction
        }
        if snapshot.features.contains(.moderation), let active = try? await api.shieldModeActive(broadcasterID: id, moderatorID: userID) {
            snapshot.shieldMode = active
        }
        publish()
    }

    private func refreshFollowers() async {
        guard snapshot.features.contains(.followers), let followers = try? await api.followers(broadcasterID: snapshot.channel.id) else { return }
        snapshot.followerTotal = followers.total
        if let away = snapshot.awayFor {
            let since = Date().addingTimeInterval(-away)
            for follow in followers.recent.reversed() where follow.followedAt > since {
                apply(.follow(follow), at: follow.followedAt)
            }
        }
        publish()
    }

    private func refreshSchedule() async {
        guard let segments = try? await api.schedule(broadcasterID: snapshot.channel.id) else { return }
        snapshot.nextStream = segments.filter { $0.canceledUntil == nil && $0.startTime > Date() }.min { $0.startTime < $1.startTime }
        publish()
    }

    private func saveTally() {
        guard let tally = snapshot.tally else { return }
        recaps.save(liveTally: tally, for: snapshot.channel.id)
    }

    private func publish() {
        changes.send(snapshot)
    }

    private static func describe(_ error: Error) -> String {
        switch error as? APIError {
        case .unauthorized?, .forbidden?: String(localized: "Twitch didn't allow it. Check Studio's permissions in Settings.", comment: "Studio error")
        case .rateLimited?: String(localized: "Twitch asked to wait a moment. Try again shortly.", comment: "Studio error")
        default: String(localized: "Twitch couldn't do that right now.", comment: "Studio error")
        }
    }
}

/// Stream tallies on this device: the one in progress, so a relaunch mid-stream keeps counting, and the last finished
/// one for the recap. Both go once they are a day past their stream.
struct StudioRecapStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recap(for channelID: String, now: Date) -> SessionTally? {
        guard let tally = read("studio.recap.\(channelID)") else { return nil }
        guard !tally.isExpired(at: now) else {
            defaults.removeObject(forKey: "studio.recap.\(channelID)")
            return nil
        }
        return tally
    }

    func liveTally(for channelID: String, startedAt: Date) -> SessionTally? {
        guard let tally = read("studio.live.\(channelID)"), abs(tally.startedAt.timeIntervalSince(startedAt)) < 5 else { return nil }
        return tally
    }

    func save(liveTally: SessionTally, for channelID: String) {
        write(liveTally, key: "studio.live.\(channelID)")
    }

    func save(recap: SessionTally, for channelID: String) {
        write(recap, key: "studio.recap.\(channelID)")
        defaults.removeObject(forKey: "studio.live.\(channelID)")
    }

    private func read(_ key: String) -> SessionTally? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionTally.self, from: data)
    }

    private func write(_ tally: SessionTally, key: String) {
        guard let data = try? JSONEncoder().encode(tally) else { return }
        defaults.set(data, forKey: key)
    }
}
