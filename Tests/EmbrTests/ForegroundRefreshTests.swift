import Foundation
import Testing
import UIKit

@testable import Embr

@MainActor
struct ForegroundRefreshTests {
    @MainActor
    private final class Harness {
        let center = NotificationCenter()
        var now = Date(timeIntervalSince1970: 1_000)
        var onScreen = true
        var refreshes = 0
        var refresher: ForegroundRefresh!

        init() {
            refresher = ForegroundRefresh(
                center: center,
                now: { [unowned self] in self.now },
                isOnScreen: { [unowned self] in self.onScreen },
                action: { [unowned self] in self.refreshes += 1 }
            )
        }

        func returnToForeground(after seconds: TimeInterval) {
            now += seconds
            center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        }
    }

    @Test func aListOnScreenRefreshesWhenItIsStale() {
        let harness = Harness()
        harness.returnToForeground(after: ForegroundRefresh.staleAfter + 1)
        #expect(harness.refreshes == 1)
    }

    @Test func aFreshListIsLeftAlone() {
        let harness = Harness()
        harness.returnToForeground(after: 10)
        #expect(harness.refreshes == 0)
    }

    @Test func aRefreshByOtherMeansRestartsTheClock() {
        let harness = Harness()
        harness.now += ForegroundRefresh.staleAfter
        harness.refresher.noteRefreshed()
        harness.returnToForeground(after: 5)
        #expect(harness.refreshes == 0)
    }

    @Test func aCoveredListRefreshesWhenItNextAppears() {
        let harness = Harness()
        harness.onScreen = false
        harness.returnToForeground(after: ForegroundRefresh.staleAfter + 1)
        #expect(harness.refreshes == 0)
        harness.refresher.listWillAppear()
        #expect(harness.refreshes == 1)
        harness.refresher.listWillAppear()
        #expect(harness.refreshes == 1)
    }

    @Test func appearingWithoutAReturnToTheAppDoesNotRefresh() {
        let harness = Harness()
        harness.now += ForegroundRefresh.staleAfter * 10
        harness.refresher.listWillAppear()
        #expect(harness.refreshes == 0)
    }

    @Test func twoQuickReturnsRefreshOnce() {
        let harness = Harness()
        harness.returnToForeground(after: ForegroundRefresh.staleAfter + 1)
        harness.returnToForeground(after: 5)
        #expect(harness.refreshes == 1)
    }
}
