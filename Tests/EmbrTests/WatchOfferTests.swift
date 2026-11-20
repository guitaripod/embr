import Foundation
import MidgarCommerce
import Testing

@testable import Embr

/// Every read and write of the state happens under one lock.
private final class MemoryOfferStorage: MidgarOfferStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var state = MidgarOfferState()

    func load() -> MidgarOfferState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    func save(_ state: MidgarOfferState) -> Bool {
        lock.lock(); defer { lock.unlock() }
        self.state = state
        return true
    }
}

/// A clock the test moves. The date is only read and written under its lock.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_760_000_000)

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return date
    }

    func advance(days: Double) {
        lock.lock(); defer { lock.unlock() }
        date.addTimeInterval(days * 86_400)
    }
}

@MainActor
struct WatchOfferTests {
    private let storage = MemoryOfferStorage()
    private let clock = TestClock()

    /// A session of the app: what a launch starts with, on the state earlier sessions left.
    private func session() -> WatchOffer {
        let clock = clock
        return WatchOffer(policy: MidgarOfferPolicy(
            storage: storage, firstOfferAfter: WatchOffer.firstOfferAfter, laterOfferEvery: WatchOffer.laterOfferEvery,
            clock: { clock.now }))
    }

    private func watch(_ streams: Int, in offer: WatchOffer, isMember: Bool = false) {
        for _ in 0..<streams {
            offer.noteStreamWatched(isMember: isMember)
        }
    }

    @Test func theFirstWatchedStreamEarnsNoOffer() {
        let offer = session()
        watch(1, in: offer)
        #expect(!offer.isMoment(isMember: false))
    }

    @Test func theSecondWatchedStreamEarnsTheOffer() {
        let offer = session()
        watch(2, in: offer)
        #expect(offer.isMoment(isMember: false))
    }

    @Test func aFoundingMemberIsNeverOffered() {
        let offer = session()
        watch(2, in: offer, isMember: true)
        #expect(!offer.isMoment(isMember: true))
        #expect(!offer.isMoment(isMember: false))
    }

    @Test func someoneWhoBoughtAfterEarningTheOfferIsNotOffered() {
        let offer = session()
        watch(2, in: offer)
        #expect(!offer.isMoment(isMember: true))
    }

    @Test func aSessionThatAskedForARatingMakesNoOffer() {
        let offer = session()
        watch(2, in: offer)
        offer.noteRatingAsked()
        #expect(!offer.isMoment(isMember: false))
    }

    @Test func anOfferHeldForARatingComesBackWithAStreamWatchedInALaterSession() {
        let first = session()
        watch(2, in: first)
        first.noteRatingAsked()

        let later = session()
        #expect(!later.isMoment(isMember: false))
        watch(1, in: later)
        #expect(later.isMoment(isMember: false))
    }

    @Test func anOfferMadeIsNotMadeAgainInTheSameSession() {
        let offer = session()
        watch(2, in: offer)
        offer.noteOffered()
        #expect(!offer.isMoment(isMember: false))
        watch(WatchOffer.laterOfferEvery, in: offer)
        #expect(!offer.isMoment(isMember: false))
    }

    @Test func theNextOfferWaitsForSixMoreStreamsAndThreeDays() {
        let first = session()
        watch(2, in: first)
        first.noteOffered()

        clock.advance(days: 1)
        let soon = session()
        watch(WatchOffer.laterOfferEvery, in: soon)
        #expect(!soon.isMoment(isMember: false))

        clock.advance(days: Double(MidgarOfferPolicy.minimumDaysBetweenOffers))
        let later = session()
        #expect(!later.isMoment(isMember: false))
        watch(1, in: later)
        #expect(later.isMoment(isMember: false))
    }

    @Test func noFourthOfferIsEverMade() {
        for _ in 0..<MidgarOfferPolicy.maximumOffers {
            let offer = session()
            watch(WatchOffer.laterOfferEvery, in: offer)
            #expect(offer.isMoment(isMember: false))
            offer.noteOffered()
            clock.advance(days: Double(MidgarOfferPolicy.minimumDaysBetweenOffers) + 1)
        }
        let offer = session()
        watch(WatchOffer.laterOfferEvery * 2, in: offer)
        #expect(!offer.isMoment(isMember: false))
    }
}
