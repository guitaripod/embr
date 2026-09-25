import Foundation
import Testing
@testable import EmbrCore

@Suite struct ReviewPromptPolicyTests {
    private let day: TimeInterval = 86_400
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func doesNotAskAtOneSuccess() {
        #expect(!ReviewPromptPolicy.shouldAsk(successCount: 1, askDates: [], successCountAtLastAsk: 0, now: now))
    }

    @Test func asksAtTwoSuccesses() {
        #expect(ReviewPromptPolicy.shouldAsk(successCount: 2, askDates: [], successCountAtLastAsk: 0, now: now))
    }

    @Test func keepsAskingUntilTheFirstAskLands() {
        #expect(ReviewPromptPolicy.shouldAsk(successCount: 6, askDates: [], successCountAtLastAsk: 0, now: now))
    }

    @Test func doesNotReaskBeforeFourteenDaysEvenWithEnoughNewSuccesses() {
        let lastAsk = now.addingTimeInterval(-5 * day)
        #expect(!ReviewPromptPolicy.shouldAsk(successCount: 10, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test func doesNotReaskBeforeThreeNewSuccessesEvenAfterFourteenDays() {
        let lastAsk = now.addingTimeInterval(-20 * day)
        #expect(!ReviewPromptPolicy.shouldAsk(successCount: 4, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test func reasksOnceBothConditionsAreMet() {
        let lastAsk = now.addingTimeInterval(-20 * day)
        #expect(ReviewPromptPolicy.shouldAsk(successCount: 5, askDates: [lastAsk], successCountAtLastAsk: 2, now: now))
    }

    @Test func neverAFourthAskWithinARollingYear() {
        let askDates = [
            now.addingTimeInterval(-300 * day),
            now.addingTimeInterval(-200 * day),
            now.addingTimeInterval(-20 * day)
        ]
        #expect(!ReviewPromptPolicy.shouldAsk(successCount: 100, askDates: askDates, successCountAtLastAsk: 10, now: now))
    }

    @Test func aFourthAskIsAllowedOnceTheOldestAgesOut() {
        let askDates = [
            now.addingTimeInterval(-370 * day),
            now.addingTimeInterval(-200 * day),
            now.addingTimeInterval(-20 * day)
        ]
        #expect(ReviewPromptPolicy.shouldAsk(successCount: 100, askDates: askDates, successCountAtLastAsk: 10, now: now))
    }
}
