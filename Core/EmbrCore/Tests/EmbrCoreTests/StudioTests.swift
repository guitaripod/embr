import Foundation
import Testing
@testable import EmbrCore

struct StudioDecoderTests {
    private func decode(_ type: String, _ json: String) -> [StudioEvent] {
        StudioEventDecoder.events(subscriptionType: type, eventData: Data(json.utf8), receivedAt: Date(timeIntervalSince1970: 1000))
    }

    @Test func aResubCarriesItsMonthsTierAndMessage() {
        let events = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","chatter_user_id":"7","chatter_user_name":"Fernwick","chatter_user_login":"fernwick",
         "chatter_is_anonymous":false,"message_id":"m1","message":{"text":"still the comfiest stream","fragments":[]},
         "notice_type":"resub","resub":{"cumulative_months":14,"duration_months":1,"sub_tier":"2000","is_prime":false,"is_gift":false},
         "source_broadcaster_user_id":null}
        """)
        guard case .subscription(let sub)? = events.first else {
            Issue.record("expected a subscription, got \(events)")
            return
        }
        #expect(sub.kind == .resub(months: 14))
        #expect(sub.tier == .two)
        #expect(sub.userName == "Fernwick")
        #expect(sub.message == "still the comfiest stream")
    }

    @Test func aGiftBombIsOneAlertAndItsGiftsAreNone() {
        let bomb = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","chatter_user_id":"9","chatter_user_name":"CopperLark","chatter_is_anonymous":false,
         "message_id":"m2","message":{"text":"","fragments":[]},"notice_type":"community_sub_gift",
         "community_sub_gift":{"id":"cg1","total":10,"sub_tier":"1000"}}
        """)
        #expect(bomb == [.giftBomb(StudioGiftBomb(id: "cg1", gifterID: "9", gifterName: "CopperLark", count: 10, tier: .one))])
        let part = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","chatter_user_id":"9","chatter_user_name":"CopperLark","message_id":"m3",
         "message":{"text":"","fragments":[]},"notice_type":"sub_gift",
         "sub_gift":{"recipient_user_name":"Mint","sub_tier":"1000","community_gift_id":"cg1"}}
        """)
        #expect(part.isEmpty)
        let single = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","chatter_user_id":"9","chatter_user_name":"CopperLark","message_id":"m4",
         "message":{"text":"","fragments":[]},"notice_type":"sub_gift",
         "sub_gift":{"recipient_user_name":"Mint","sub_tier":"3000","community_gift_id":null}}
        """)
        guard case .subscription(let gift)? = single.first else {
            Issue.record("expected a gift")
            return
        }
        #expect(gift.kind == .gift(recipientName: "Mint"))
        #expect(gift.tier == .three)
    }

    @Test func anAnonymousGiftBombHasNoGifter() {
        let events = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","chatter_user_id":"274598607","chatter_user_name":"AnAnonymousGifter","chatter_is_anonymous":true,
         "message_id":"m5","message":{"text":"","fragments":[]},"notice_type":"community_sub_gift",
         "community_sub_gift":{"id":"cg2","total":5,"sub_tier":"1000"}}
        """)
        #expect(events == [.giftBomb(StudioGiftBomb(id: "cg2", gifterID: nil, gifterName: nil, count: 5, tier: .one))])
    }

    @Test func aRaidCarriesTheRaiderAndPartySize() {
        let events = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","chatter_user_id":"5","chatter_user_name":"Nightjar","message_id":"m6",
         "message":{"text":"","fragments":[]},"notice_type":"raid",
         "raid":{"user_id":"5","user_name":"Nightjar","user_login":"nightjar","viewer_count":312,
                 "profile_image_url":"https://static-cdn.jtvnw.net/x.png"}}
        """)
        #expect(events == [.raid(StudioRaid(raiderID: "5", raiderName: "Nightjar", raiderLogin: "nightjar", viewers: 312, profileImageURL: URL(string: "https://static-cdn.jtvnw.net/x.png")))])
    }

    @Test func noticesFromAnotherChannelInSharedChatAreLeftOut() {
        let events = decode("channel.chat.notification", """
        {"broadcaster_user_id":"1","source_broadcaster_user_id":"2","chatter_user_id":"7","chatter_user_name":"X",
         "message_id":"m7","message":{"text":"","fragments":[]},"notice_type":"shared_chat_sub",
         "sub":{"sub_tier":"1000","is_prime":false}}
        """)
        #expect(events.isEmpty)
    }

    @Test func aCheerComesFromItsChatMessage() {
        let events = decode("channel.chat.message", """
        {"broadcaster_user_id":"1","chatter_user_id":"8","chatter_user_name":"Quill","chatter_user_login":"quill",
         "message_id":"c1","message":{"text":"Cheer500 for the lighthouse fund","fragments":[]},"cheer":{"bits":500}}
        """)
        #expect(events == [.cheer(StudioCheer(id: "c1", userID: "8", userName: "Quill", bits: 500, message: "Cheer500 for the lighthouse fund"))])
        #expect(decode("channel.chat.message", #"{"broadcaster_user_id":"1","message_id":"c2","message":{"text":"hi"},"cheer":null}"#).isEmpty)
    }

    @Test func bitsUseReportsPowerUpsButNotCheers() {
        let power = decode("channel.bits.use", """
        {"user_id":"3","user_name":"Pebble","bits":100,"type":"custom_power_up","custom_power_up":{"title":"Pick the next colour","reward_id":"r"}}
        """)
        #expect(power == [.powerUp(StudioPowerUp(userID: "3", userName: "Pebble", bits: 100, title: "Pick the next colour"))])
        let builtIn = decode("channel.bits.use", #"{"user_id":"3","user_name":"Pebble","bits":50,"type":"power_up","power_up":{"type":"gigantify_an_emote"}}"#)
        #expect(builtIn == [.powerUp(StudioPowerUp(userID: "3", userName: "Pebble", bits: 50, title: "Gigantify an Emote"))])
        #expect(decode("channel.bits.use", #"{"user_id":"3","bits":100,"type":"cheer"}"#).isEmpty)
    }

    @Test func followsHypeTrainsPollsPredictionsGoalsAndAds() {
        let follow = decode("channel.follow", #"{"user_id":"4","user_name":"Hollowreed","followed_at":"2026-11-08T20:00:00.123456789Z"}"#)
        guard case .follow(let f)? = follow.first else {
            Issue.record("expected a follow")
            return
        }
        #expect(f.userName == "Hollowreed")
        #expect(abs(f.followedAt.timeIntervalSince1970 - 1_794_168_000.123) < 0.01)

        let train = decode("channel.hype_train.progress", """
        {"id":"h1","level":3,"total":1700,"progress":680,"goal":1000,"type":"golden_kappa","expires_at":"2026-11-08T20:05:00Z",
         "top_contributions":[{"user_name":"CopperLark","type":"subscription","total":5000},{"user_name":"Quill","type":"bits","total":500}]}
        """)
        guard case .hypeTrain(let h)? = train.first else {
            Issue.record("expected a hype train")
            return
        }
        #expect(h.level == 3 && h.fraction == 0.68 && h.isGolden && h.topContributors.count == 2)

        let poll = decode("channel.poll.end", """
        {"id":"p1","title":"Next painting?","choices":[{"id":"a","title":"Stormy harbour","votes":58},{"id":"b","title":"Northern lights","votes":31}],"status":"completed"}
        """)
        guard case .poll(let p)? = poll.first else {
            Issue.record("expected a poll")
            return
        }
        #expect(p.phase == .ended && p.totalVotes == 89 && p.winner?.id == "a")

        let prediction = decode("channel.prediction.end", """
        {"id":"q1","title":"No-hit?","outcomes":[{"id":"y","title":"Yes","channel_points":1200},{"id":"n","title":"No","channel_points":800}],"status":"resolved","winning_outcome_id":"y"}
        """)
        #expect(prediction.first == .prediction(StudioPrediction(id: "q1", title: "No-hit?", outcomes: [StudioChoice(id: "y", title: "Yes", votes: 1200), StudioChoice(id: "n", title: "No", votes: 800)], locksAt: nil, phase: .resolved(winningOutcomeID: "y"))))

        let goal = decode("channel.goal.end", #"{"id":"g","type":"follow","description":"","current_amount":100,"target_amount":100,"is_achieved":true}"#)
        #expect(goal == [.goal(StudioGoal(id: "g", kind: "follow", description: "", current: 100, target: 100, ended: true, achieved: true))])

        let ad = decode("channel.ad_break.begin", #"{"duration_seconds":"90","started_at":"2026-11-08T21:40:00Z","is_automatic":true}"#)
        guard case .adBreakBegan(let a)? = ad.first else {
            Issue.record("expected an ad break")
            return
        }
        #expect(a.duration == 90 && a.isAutomatic)
    }

    @Test func sharedChatListsTheOtherChannels() {
        let events = decode("channel.shared_chat.begin", """
        {"session_id":"s","broadcaster_user_id":"1","participants":[{"broadcaster_user_id":"1","broadcaster_user_name":"Me"},{"broadcaster_user_id":"2","broadcaster_user_name":"Friend"}]}
        """)
        #expect(events == [.sharedChat(StudioSharedChat(sessionID: "s", participants: ["Friend"]))])
        #expect(decode("channel.shared_chat.end", #"{"session_id":"s"}"#) == [.sharedChat(nil)])
    }
}

struct StudioFeatureTests {
    @Test func chatIsAlwaysAskedForAndScopesAreUnique() {
        let scopes = StudioFeature.scopes(for: [.adBreaks, .runAds])
        #expect(scopes.contains("user:read:chat"))
        #expect(scopes.contains("channel:manage:ads") && scopes.contains("channel:edit:commercial"))
        #expect(scopes.count == Set(scopes).count)
        #expect(!scopes.contains("bits:read"))
    }

    @Test func grantedFeaturesNeedEveryScope() {
        let granted = StudioFeature.granted(by: ["user:read:chat", "user:write:chat", "user:read:blocked_users", "user:manage:blocked_users", "channel:read:ads"])
        #expect(granted == [.chat])
        let both = StudioFeature.granted(by: StudioFeature.scopes(for: [.adBreaks]))
        #expect(both == [.chat, .adBreaks])
    }

    @Test func aModeratorPlanHasNoBroadcasterOnlySubscriptions() {
        let all = Set(StudioFeature.allCases)
        let moderator = StudioSubscriptionPlan.requests(role: .moderator, features: all, broadcasterID: "1", userID: "2", sessionID: "s").map(\.type)
        #expect(moderator.contains("channel.follow"))
        #expect(!moderator.contains("channel.ad_break.begin") && !moderator.contains("channel.poll.begin") && !moderator.contains("channel.bits.use"))
        let broadcaster = StudioSubscriptionPlan.requests(role: .broadcaster, features: all, broadcasterID: "1", userID: "1", sessionID: "s")
        #expect(broadcaster.contains { $0.type == "channel.hype_train.begin" && $0.version == "2" })
        #expect(broadcaster.contains { $0.type == "channel.follow" && $0.condition["moderator_user_id"] == "1" })
        #expect(broadcaster.count < 300)
        let none = StudioSubscriptionPlan.requests(role: .broadcaster, features: [.chat], broadcasterID: "1", userID: "1", sessionID: "s").map(\.type)
        #expect(Set(none) == ["stream.online", "stream.offline", "channel.update", "channel.shared_chat.begin", "channel.shared_chat.update", "channel.shared_chat.end"])
    }
}

struct AdBreakClockTests {
    private let now = Date(timeIntervalSince1970: 10_000)

    private func schedule(nextIn: TimeInterval?, lastAgo: TimeInterval? = nil, snoozes: Int = 2, preroll: TimeInterval = 0) -> AdSchedule {
        AdSchedule(
            nextAdAt: nextIn.map { now.addingTimeInterval($0) },
            lastAdAt: lastAgo.map { now.addingTimeInterval(-$0) },
            duration: 90,
            prerollFreeSeconds: preroll,
            snoozeCount: snoozes,
            snoozeRefreshAt: now.addingTimeInterval(600),
            fetchedAt: now
        )
    }

    @Test func theClockMovesThroughItsStates() {
        var clock = AdBreakClock()
        #expect(clock.state(at: now) == .unknown)
        clock.apply(schedule(nextIn: 272))
        #expect(clock.state(at: now) == .scheduled(at: now.addingTimeInterval(272), duration: 90))
        #expect(clock.state(at: now.addingTimeInterval(230)) == .imminent(at: now.addingTimeInterval(272), duration: 90))
        #expect(clock.state(at: now.addingTimeInterval(300)) == .running(endsAt: now.addingTimeInterval(362), duration: 90))
        #expect(clock.state(at: now.addingTimeInterval(400)) == .noneScheduled(prerollFreeUntil: nil))
    }

    @Test func aBreakThatBeganRunsForItsLength() {
        var clock = AdBreakClock(schedule: schedule(nextIn: nil, preroll: 600))
        #expect(clock.state(at: now) == .noneScheduled(prerollFreeUntil: now.addingTimeInterval(600)))
        clock.apply(StudioAdBreak(startedAt: now, duration: 60, isAutomatic: false))
        #expect(clock.state(at: now.addingTimeInterval(30)) == .running(endsAt: now.addingTimeInterval(60), duration: 60))
        #expect(!clock.canSnooze(at: now.addingTimeInterval(30)))
        #expect(!clock.canRunAd(at: now.addingTimeInterval(30)))
    }

    @Test func runAdWaitsEightMinutesAfterTheLastAdAndForTwitchsRetry() {
        var clock = AdBreakClock(schedule: schedule(nextIn: 900, lastAgo: 120))
        #expect(clock.runAdUnlocksAt(now: now) == now.addingTimeInterval(360))
        #expect(!clock.canRunAd(at: now))
        #expect(clock.canRunAd(at: now.addingTimeInterval(361)))
        clock.refuseManualAd(until: now.addingTimeInterval(500))
        #expect(clock.runAdUnlocksAt(now: now.addingTimeInterval(400)) == now.addingTimeInterval(500))
    }

    @Test func snoozingNeedsASnoozeAndAnUpcomingAd() {
        #expect(AdBreakClock(schedule: schedule(nextIn: 200)).canSnooze(at: now))
        #expect(!AdBreakClock(schedule: schedule(nextIn: 200, snoozes: 0)).canSnooze(at: now))
        #expect(!AdBreakClock(schedule: schedule(nextIn: nil)).canSnooze(at: now))
    }

    @Test func warningsSoundOnceAtAMinuteAndAtTenSeconds() {
        let clock = AdBreakClock(schedule: schedule(nextIn: 100))
        #expect(clock.warning(between: now, and: now.addingTimeInterval(30)) == nil)
        #expect(clock.warning(between: now.addingTimeInterval(39), and: now.addingTimeInterval(41)) == .oneMinute)
        #expect(clock.warning(between: now.addingTimeInterval(89), and: now.addingTimeInterval(91)) == .tenSeconds)
        #expect(clock.warning(between: now.addingTimeInterval(91), and: now.addingTimeInterval(92)) == nil)
    }
}

struct AlertQueueTests {
    private let now = Date(timeIntervalSince1970: 50_000)

    private func follow(_ name: String) -> StudioEvent {
        .follow(StudioFollow(userID: name, userName: name, followedAt: now))
    }

    @Test func followsCloseTogetherShareOneLine() {
        var queue = AlertQueue()
        _ = queue.ingest(follow("a"), at: now)
        let second = queue.ingest(follow("b"), at: now.addingTimeInterval(5))
        _ = queue.ingest(follow("c"), at: now.addingTimeInterval(10))
        #expect(queue.feed.count == 1)
        #expect(queue.feed[0].moreFollowers == ["b", "a"])
        #expect(second.sound == nil)
        _ = queue.ingest(follow("d"), at: now.addingTimeInterval(60))
        #expect(queue.feed.count == 2)
    }

    @Test func theSameAlertDeliveredTwiceShowsOnce() {
        var queue = AlertQueue()
        let sub = StudioEvent.subscription(StudioSubscription(id: "x", userID: "1", userName: "A", kind: .new, tier: .one, isPrime: false, message: ""))
        let first = queue.ingest(sub, at: now)
        let again = queue.ingest(sub, at: now)
        #expect(first.feedChanged)
        #expect(!again.feedChanged)
        #expect(queue.feed.count == 1)
    }

    @Test func aRaidTakesTheBannerFromABigGiftAndTheGiftComesBack() {
        var queue = AlertQueue()
        let bomb = StudioEvent.giftBomb(StudioGiftBomb(id: "g", gifterID: "1", gifterName: "A", count: 10, tier: .one))
        let raid = StudioEvent.raid(StudioRaid(raiderID: "2", raiderName: "B", raiderLogin: "b", viewers: 300, profileImageURL: nil))
        _ = queue.ingest(bomb, at: now)
        #expect(queue.banner?.event == bomb)
        _ = queue.ingest(raid, at: now.addingTimeInterval(1))
        #expect(queue.banner?.event == raid)
        let raidEnded = queue.tick(at: now.addingTimeInterval(14))
        #expect(raidEnded)
        #expect(queue.banner?.event == bomb)
        let bombEnded = queue.tick(at: now.addingTimeInterval(23))
        #expect(bombEnded)
        #expect(queue.banner == nil)
    }

    @Test func smallGiftsAndCheersStayInTheFeed() {
        var queue = AlertQueue()
        _ = queue.ingest(.giftBomb(StudioGiftBomb(id: "g", gifterID: nil, gifterName: nil, count: 2, tier: .one)), at: now)
        _ = queue.ingest(.cheer(StudioCheer(id: "c", userID: "1", userName: "A", bits: 100, message: "")), at: now)
        #expect(queue.banner == nil)
        #expect(queue.feed.count == 2)
    }

    @Test func hiddenKindsAndSilentRoomsAreRespected() {
        var queue = AlertQueue(preferences: AlertPreferences(shown: [.raids], sounds: []))
        let hidden = queue.ingest(follow("a"), at: now)
        #expect(!hidden.feedChanged)
        let raid = queue.ingest(.raid(StudioRaid(raiderID: "2", raiderName: "B", raiderLogin: "b", viewers: 3, profileImageURL: nil)), at: now)
        #expect(raid.feedChanged && raid.sound == nil)
    }
}

struct SessionTallyTests {
    @Test func theRecapCountsAndExpiresADayAfterTheStream() {
        let start = Date(timeIntervalSince1970: 0)
        var tally = SessionTally(startedAt: start)
        tally.record(.follow(StudioFollow(userID: "1", userName: "a", followedAt: start)))
        tally.record(.subscription(StudioSubscription(id: "s", userID: "1", userName: "a", kind: .resub(months: 3), tier: .one, isPrime: false, message: "")))
        tally.record(.subscription(StudioSubscription(id: "g", userID: "1", userName: "a", kind: .gift(recipientName: "b"), tier: .one, isPrime: false, message: "")))
        tally.record(.giftBomb(StudioGiftBomb(id: "b", gifterID: nil, gifterName: nil, count: 10, tier: .one)))
        tally.record(.cheer(StudioCheer(id: "c", userID: nil, userName: nil, bits: 500, message: "")))
        tally.record(.raid(StudioRaid(raiderID: "r", raiderName: "r", raiderLogin: "r", viewers: 312, profileImageURL: nil)))
        tally.record(.adBreakBegan(StudioAdBreak(startedAt: start, duration: 90, isAutomatic: true)))
        tally.record(viewers: 100)
        tally.record(viewers: 200)
        #expect(tally.followers == 1 && tally.subscriptions == 1 && tally.giftedSubscriptions == 11)
        #expect(tally.bits == 500 && tally.raids == 1 && tally.raidViewers == 312 && tally.adBreaks == 1 && tally.adSeconds == 90)
        #expect(tally.peakViewers == 200 && tally.averageViewers == 150)
        #expect(!tally.isExpired(at: Date(timeIntervalSince1970: 1_000_000)))
        tally.end(at: Date(timeIntervalSince1970: 3600))
        #expect(!tally.isExpired(at: Date(timeIntervalSince1970: 3600 + 86_000)))
        #expect(tally.isExpired(at: Date(timeIntervalSince1970: 3600 + 86_401)))
        let decoded = try? JSONDecoder().decode(SessionTally.self, from: JSONEncoder().encode(tally))
        #expect(decoded == tally)
    }
}

struct StudioHelixTests {
    private let factory = HelixRequestFactory(clientID: "cid")

    @Test func theAdScheduleReadsRFC3339StringNumbersAndUnixTimes() {
        let documented = Data(#"{"data":[{"next_ad_at":"2023-08-01T23:08:18+00:00","last_ad_at":"","duration":"60","preroll_free_time":"90","snooze_count":"1","snooze_refresh_at":"2023-08-01T23:08:18+00:00"}]}"#.utf8)
        let schedule = StudioHelixDecoder.adSchedule(documented, fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(schedule?.nextAdAt == Date(timeIntervalSince1970: 1_690_931_298))
        #expect(schedule?.lastAdAt == nil)
        #expect(schedule?.duration == 60 && schedule?.prerollFreeSeconds == 90 && schedule?.snoozeCount == 1)
        let unix = Data(#"{"data":[{"next_ad_at":1690931298,"last_ad_at":"1690930000","duration":90,"preroll_free_time":0,"snooze_count":3,"snooze_refresh_at":0}]}"#.utf8)
        let other = StudioHelixDecoder.adSchedule(unix, fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(other?.nextAdAt == Date(timeIntervalSince1970: 1_690_931_298))
        #expect(other?.lastAdAt == Date(timeIntervalSince1970: 1_690_930_000))
        #expect(other?.snoozeRefreshAt == nil)
    }

    @Test func aSnoozeKeepsWhatItDoesNotRepeat() {
        let before = AdSchedule(nextAdAt: Date(timeIntervalSince1970: 100), lastAdAt: Date(timeIntervalSince1970: 50), duration: 90, prerollFreeSeconds: 0, snoozeCount: 2, snoozeRefreshAt: nil, fetchedAt: Date(timeIntervalSince1970: 0))
        let after = StudioHelixDecoder.snoozed(Data(#"{"data":[{"snooze_count":1,"next_ad_at":"1970-01-01T00:06:40Z","snooze_refresh_at":""}]}"#.utf8), previous: before, fetchedAt: Date(timeIntervalSince1970: 1))
        #expect(after?.nextAdAt == Date(timeIntervalSince1970: 400))
        #expect(after?.snoozeCount == 1 && after?.duration == 90 && after?.lastAdAt == Date(timeIntervalSince1970: 50))
    }

    @Test func requestsGoWhereTwitchDocumentsThem() throws {
        let commercial = factory.startCommercial(broadcasterID: "1", length: 600, token: "t")
        #expect(commercial.method == .post && commercial.url.absoluteString == "https://api.twitch.tv/helix/channels/commercial")
        let body = try JSONSerialization.jsonObject(with: commercial.body ?? Data()) as? [String: Any]
        #expect(body?["length"] as? Int == 180)
        let pin = factory.pinMessage(broadcasterID: "1", moderatorID: "2", messageID: "m", durationSeconds: 10, token: "t")
        #expect(pin.method == .put && pin.url.absoluteString.contains("chat/pins") && pin.url.absoluteString.contains("duration_seconds=30"))
        let modes = factory.updateChatSettings(broadcasterID: "1", moderatorID: "2", change: .slow(seconds: 10), token: "t")
        #expect(modes.method == .patch)
        #expect(String(data: modes.body ?? Data(), encoding: .utf8) == #"{"slow_mode":true,"slow_mode_wait_time":10}"#)
        #expect(factory.snoozeNextAd(broadcasterID: "1", token: "t").url.absoluteString == "https://api.twitch.tv/helix/channels/ads/schedule/snooze?broadcaster_id=1")
    }

    @Test func activePollsPredictionsAndModeratedChannels() {
        #expect(StudioHelixDecoder.activePoll(Data(#"{"data":[{"id":"p","title":"t","status":"COMPLETED","choices":[]}]}"#.utf8)) == nil)
        #expect(StudioHelixDecoder.activePoll(Data(#"{"data":[{"id":"p","title":"t","status":"ACTIVE","choices":[{"id":"a","title":"A","votes":2}]}]}"#.utf8))?.totalVotes == 2)
        #expect(StudioHelixDecoder.activePrediction(Data(#"{"data":[{"id":"q","title":"t","status":"LOCKED","outcomes":[]}]}"#.utf8))?.phase == .locked)
        let moderated = StudioHelixDecoder.moderatedChannels(Data(#"{"data":[{"broadcaster_id":"5","broadcaster_login":"nightjar","broadcaster_name":"Nightjar"}],"pagination":{"cursor":"c"}}"#.utf8))
        #expect(moderated.channels == [ModeratedChannel(id: "5", login: "nightjar", name: "Nightjar")])
        #expect(moderated.cursor == "c")
        #expect(StudioHelixDecoder.hypeTrain(Data(#"{"data":[{"current":null}]}"#.utf8)) == nil)
    }
}
