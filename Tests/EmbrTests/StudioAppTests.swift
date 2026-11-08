import EmbrCore
import Foundation
import Testing

@testable import Embr

@MainActor
struct StudioAppTests {
    @Test func settingsFromAnOlderVersionKeepTheirValuesAndFillTheRest() throws {
        let old = Data(#"{"chatOnRight":true,"defaultAdLength":60}"#.utf8)
        let settings = try JSONDecoder().decode(StudioSettings.self, from: old)
        #expect(settings.chatOnRight)
        #expect(settings.defaultAdLength == 60)
        #expect(settings.stayAwakeWhileLive)
        #expect(settings.role == .broadcaster)
        #expect(settings.alerts == AlertPreferences())
    }

    @Test func turningAdChimesOffSilencesOnlyTheAdWarning() {
        var settings = StudioSettings()
        settings.adWarnings = false
        #expect(!settings.effectiveAlerts.sounds.contains(.adWarning))
        #expect(settings.effectiveAlerts.sounds.contains(.raid))
    }

    @Test func aRelaunchMidStreamKeepsCountingAndTheRecapExpiresAfterADay() throws {
        let defaults = try #require(UserDefaults(suiteName: "StudioAppTests.recap.\(UUID().uuidString)"))
        let store = StudioRecapStore(defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_000_000)
        var tally = SessionTally(startedAt: start)
        tally.followers = 7
        store.save(liveTally: tally, for: "c")
        #expect(store.liveTally(for: "c", startedAt: start.addingTimeInterval(2))?.followers == 7)
        #expect(store.liveTally(for: "c", startedAt: start.addingTimeInterval(3600)) == nil)
        tally.end(at: start.addingTimeInterval(3600))
        store.save(recap: tally, for: "c")
        #expect(store.liveTally(for: "c", startedAt: start) == nil)
        #expect(store.recap(for: "c", now: start.addingTimeInterval(7200))?.followers == 7)
        #expect(store.recap(for: "c", now: start.addingTimeInterval(3600 + 86_401)) == nil)
    }

    @Test func askingForStudioKeepsModeratorToolsScopes() {
        let withTools = TwitchScopes.viewerDefault + TwitchScopes.moderatorTools
        let scopes = StudioLauncher.scopes(for: [.adBreaks], keeping: withTools)
        #expect(scopes.contains("channel:read:ads"))
        #expect(TwitchScopes.moderatorTools.allSatisfy(scopes.contains))
        #expect(Set(scopes).count == scopes.count)
        let plain = StudioLauncher.scopes(for: [.adBreaks], keeping: TwitchScopes.viewerDefault)
        #expect(!plain.contains("moderator:manage:automod"))
    }

    @Test func theProWeekRunsSevenDaysFromItsStart() throws {
        let start = Date(timeIntervalSince1970: 0)
        #expect(StudioProWeek.phase(start: nil, now: start) == .notStarted)
        #expect(StudioProWeek.phase(start: start, now: start.addingTimeInterval(86_400)).isActive)
        #expect(StudioProWeek.phase(start: start, now: start.addingTimeInterval(7 * 86_400 + 1)) == .over)
        #expect(StudioProWeek.daysLeft(until: start.addingTimeInterval(3600), now: start) == 1)
    }

    @Test func theProWeekStartsOnceForABroadcastersOwnLiveStream() throws {
        let suite = "StudioAppTests.week.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = StudioProStore(defaults: defaults, week: .local(suite: suite))
        store.noteLiveStream(role: .moderator, isSample: false)
        store.noteLiveStream(role: .broadcaster, isSample: true)
        #expect(store.weekPhase() == .notStarted)
        let first = Date()
        store.noteLiveStream(role: .broadcaster, isSample: false, now: first)
        store.noteLiveStream(role: .broadcaster, isSample: false, now: first.addingTimeInterval(500_000))
        guard case .active(let endsAt) = store.weekPhase(now: first) else {
            Issue.record("the week should be running")
            return
        }
        #expect(abs(endsAt.timeIntervalSince(first.addingTimeInterval(StudioProWeek.length))) < 0.01)
        #expect(store.hasPro)
    }

    @Test func studioCountsAgreeWithTheirNumber() {
        let one = 1, three = 3
        #expect(String(localized: "\(one) raids") == "1 raid")
        #expect(String(localized: "\(three) raids") == "3 raids")
        #expect(String(localized: "This stream: +\(one) followers") == "This stream: +1 follower")
        #expect(String(localized: "\(one) snoozes left") == "1 snooze left")
        #expect(String(localized: "\(one) days left") == "1 day left")
        #expect(String(localized: "\("ana") gifted \(one) subs") == "ana gifted 1 sub")
        #expect(String(localized: "\("ana") gifted \(three) subs") == "ana gifted 3 subs")
        #expect(String(localized: "Last stream: \("40") peak viewers, +\(one) followers, \("2") subs and gifts.") == "Last stream: 40 peak viewers, +1 follower, 2 subs and gifts.")
    }

    @Test func germanStudioCountsAgreeWithTheirNumber() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        let locale = Locale(identifier: "de")
        func format(_ key: String, _ arguments: CVarArg...) -> String {
            String(format: german.localizedString(forKey: key, value: nil, table: nil), locale: locale, arguments: arguments)
        }
        #expect(format("%lld raids", 1) == "1 Raid")
        #expect(format("%lld raids", 4) == "4 Raids")
        #expect(format("%@ gifted %lld subs", "ana", 1) == "ana hat 1 Abo verschenkt")
        #expect(format("%@ gifted %lld subs", "ana", 5) == "ana hat 5 Abos verschenkt")
    }

    @Test func everyStudioProductGrantsTheStudioEntitlement() {
        for id in StudioProStore.productIDs {
            #expect(EmbrMidgar.entitlementsByProduct[id] == StudioProStore.entitlement)
        }
        #expect(EmbrMidgar.entitlementsByProduct[SupporterAPI.productID] == SupporterStore.entitlement)
        #expect(Set(EmbrMidgar.productIDs).isSuperset(of: StudioProStore.productIDs))
    }
}
