import MidgarCommerce
import MidgarCore
import UIKit

/// When a watched stream offers Founding Member, through the shared ``MidgarOfferPolicy``: after the second live stream
/// watched for three minutes, then after every sixth more and at least three days apart, three times in all, never to
/// a Founding Member. The offer is the fitting room itself, and it waits until the viewer has left the stream, so
/// nothing ever covers a playing video. A session that asked for a rating makes no offer: one ask is enough.
@MainActor
final class WatchOffer {
    static let firstOfferAfter = 2
    static let laterOfferEvery = 6

    static let shared = WatchOffer(
        policy: MidgarOfferPolicy(appID: EmbrMidgar.appID, firstOfferAfter: firstOfferAfter, laterOfferEvery: laterOfferEvery))

    private let policy: MidgarOfferPolicy
    private var isDue = false
    private var askedForRating = false

    init(policy: MidgarOfferPolicy) {
        self.policy = policy
    }

    /// Counts a live stream the viewer stayed on long enough to count as watched. An offer it earns is made once they
    /// leave the stream, by ``offerIfDue(afterLeaving:)``.
    func noteStreamWatched(isMember: Bool) {
        if policy.noteValue(isOwned: isMember) {
            isDue = true
        }
    }

    /// Holds the offer back for the rest of the session, because Embr just asked for a rating.
    func noteRatingAsked() {
        askedForRating = true
    }

    /// Whether leaving a stream now is the moment: a stream watched in this session earned the offer, no rating was
    /// asked for, and the policy still agrees, which it stops doing once the viewer owns Founding Member.
    func isMoment(isMember: Bool) -> Bool {
        isDue && !askedForRating && !isMember && policy.evaluate() == .offer
    }

    /// Records that the offer is on screen.
    func noteOffered() {
        isDue = false
        policy.noteOffered()
    }
}

extension WatchOffer {
    /// Offers Founding Member over the page the viewer comes back to, once the stream's page has gone. A back swipe
    /// let go of half-way leaves the stream on screen and the offer for later. The offer waits one more turn of the
    /// main queue after the way back has finished, so building its page does not land on top of the work of taking
    /// the stream's page apart: on an iPhone XS the two together held the screen for a tenth of a second.
    func offerIfDue(afterLeaving stream: UIViewController) {
        guard isMomentNow, let host = stream.tabBarController else { return }
        guard let transition = stream.transitionCoordinator else {
            DispatchQueue.main.async { self.present(over: host) }
            return
        }
        transition.animate(alongsideTransition: nil) { context in
            guard !context.isCancelled else { return }
            DispatchQueue.main.async { self.present(over: host) }
        }
    }

    /// Whether the offer may come up for the person using the app. A test host and a demo capture never see it; a
    /// capture that asks for it with `-screenshotWatchOffer` sees it without the watching.
    private var isMomentNow: Bool {
        let isMember = SupporterStore.shared.isSupporter
        #if DEBUG
        if ScreenshotHarness.watchOffer { return !isMember }
        #endif
        return EmbrMidgar.reachesMidgarServices && isMoment(isMember: isMember)
    }

    /// Shows the fitting room once the viewer is back among the lists with nothing else in front of them. Another
    /// stream opened straight from this one, a sheet already up or a window that left the foreground keeps the offer
    /// for the next stream they leave.
    private func present(over host: UITabBarController) {
        let front = (host.selectedViewController as? UINavigationController)?.topViewController
        guard isMomentNow, host.presentedViewController == nil, !(front is PlaybackPage),
              host.view.window?.windowScene?.activationState == .foregroundActive
        else { return }
        countOffer()
        host.present(SupporterViewController.sheet(placement: .moment), animated: true)
        MidgarLog.info("offered Founding Member after a watched stream", category: .supporter)
    }

    /// Counts the offer that is about to show. One posed for a capture is not counted: it must not use up one of the
    /// three a viewer gets on the phone it was posed on.
    private func countOffer() {
        #if DEBUG
        if ScreenshotHarness.watchOffer {
            isDue = false
            return
        }
        #endif
        noteOffered()
    }
}
