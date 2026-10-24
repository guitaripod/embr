import Testing
@testable import EmbrCore

@Suite struct LiveAlertsPromptPolicyTests {
    @Test func offersToASignedInViewerWhoHasNotBeenAsked() {
        #expect(LiveAlertsPromptPolicy.shouldOffer(isSignedIn: true, systemStatus: .notDetermined, alreadyOffered: false))
    }

    @Test func neverOffersToGuests() {
        #expect(!LiveAlertsPromptPolicy.shouldOffer(isSignedIn: false, systemStatus: .notDetermined, alreadyOffered: false))
    }

    @Test func doesNotOfferOnceTheSystemHasAnswered() {
        #expect(!LiveAlertsPromptPolicy.shouldOffer(isSignedIn: true, systemStatus: .answered, alreadyOffered: false))
    }

    @Test func offersOnlyOnce() {
        #expect(!LiveAlertsPromptPolicy.shouldOffer(isSignedIn: true, systemStatus: .notDetermined, alreadyOffered: true))
    }
}
