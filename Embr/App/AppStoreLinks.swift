import Foundation

/// The two doors to the App Store a person opens on purpose — the review form, and the listing
/// handed to the share sheet with one line saying what the app is — as opposed to the review the
/// app asks for by itself (`ReviewPrompt`).
enum AppStoreLinks {
    static let appID = "6784940198"
    static let listing = URL(string: "https://apps.apple.com/app/id\(appID)")!
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!

    /// The line beside the link in the share sheet, so the message is not a bare URL.
    static var sharePitch: String {
        String(
            localized: "Embr — a fast, native way to watch Twitch on iPhone, with 7TV, BTTV and FFZ emotes in chat.",
            comment: "Text beside the App Store link in the share sheet")
    }

    static var shareItems: [Any] { [sharePitch, listing] }
}
