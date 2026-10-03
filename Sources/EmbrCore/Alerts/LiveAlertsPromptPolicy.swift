import Foundation

/// Decides whether Embr may explain live alerts and then ask for notification permission.
///
/// Alerts only exist for a signed-in viewer's followed channels, so the ask belongs to the moment
/// someone signs in, once, and only while the system has not already answered.
public enum LiveAlertsPromptPolicy {
    public enum SystemStatus: Sendable, Equatable {
        case notDetermined
        case answered
    }

    public static func shouldOffer(isSignedIn: Bool, systemStatus: SystemStatus, alreadyOffered: Bool) -> Bool {
        isSignedIn && systemStatus == .notDetermined && !alreadyOffered
    }
}
