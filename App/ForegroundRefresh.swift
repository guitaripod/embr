import UIKit
import Combine

/// Brings a list up to date when the app comes back from the background: at once if the list is on screen, otherwise the
/// next time it appears. A list refreshed within the last minute is left as it is.
@MainActor
final class ForegroundRefresh {
    static let staleAfter: TimeInterval = 60

    private let isOnScreen: () -> Bool
    private let action: () -> Void
    private let now: () -> Date
    private var lastRefresh: Date
    private var isPending = false
    private var cancellable: AnyCancellable?

    init(
        center: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        isOnScreen: @escaping () -> Bool,
        action: @escaping () -> Void
    ) {
        self.isOnScreen = isOnScreen
        self.action = action
        self.now = now
        lastRefresh = now()
        cancellable = center.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.didEnterForeground() }
            }
    }

    /// The list loaded by other means (its first load, pull to refresh), so a return soon after leaves it alone.
    func noteRefreshed() {
        lastRefresh = now()
        isPending = false
    }

    /// Called from the list's `viewWillAppear`, to catch up on a return to the foreground it missed while covered.
    func listWillAppear() {
        guard isPending else { return }
        isPending = false
        refreshIfStale()
    }

    private func didEnterForeground() {
        if isOnScreen() {
            refreshIfStale()
        } else {
            isPending = true
        }
    }

    private func refreshIfStale() {
        guard now().timeIntervalSince(lastRefresh) >= Self.staleAfter else { return }
        lastRefresh = now()
        action()
    }
}
