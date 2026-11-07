import UIKit
import Combine
import SDWebImage

/// Plays the animated emotes on screen in chat. Each emote view animates itself; this starts and stops them together:
/// paused during fast scrolls, and still while Animate Emotes is off or, on a phone, in Low Power Mode.
@MainActor
final class EmoteAnimator {
    static let shared = EmoteAnimator()

    private var registered: [ObjectIdentifier: WeakView] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var allowed = EmoteAnimator.animationAllowed

    var isPaused: Bool = false {
        didSet {
            guard isPaused != oldValue else { return }
            applyPlayback()
        }
    }

    private struct WeakView {
        weak var view: SDAnimatedImageView?
    }

    init() {
        SettingsStore.shared.changes
            .map(\.animateEmotes)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAllowed() }
            .store(in: &cancellables)
        #if os(iOS)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAllowed() }
            .store(in: &cancellables)
        #endif
    }

    func register(_ view: UIView, url: URL) {
        guard let animatedView = view as? SDAnimatedImageView else { return }
        if registered.count > 64 { pruneReleased() }
        registered[ObjectIdentifier(animatedView)] = WeakView(view: animatedView)
        if allowed, !isPaused {
            animatedView.startAnimating()
        } else {
            animatedView.stopAnimating()
        }
    }

    func unregister(_ view: UIView) {
        if let animatedView = view as? SDAnimatedImageView {
            animatedView.stopAnimating()
        }
        registered.removeValue(forKey: ObjectIdentifier(view))
    }

    private static var animationAllowed: Bool {
        #if os(iOS)
        return SettingsStore.shared.current.animateEmotes && !ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return SettingsStore.shared.current.animateEmotes
        #endif
    }

    private func refreshAllowed() {
        let now = Self.animationAllowed
        guard now != allowed else { return }
        allowed = now
        applyPlayback()
    }

    private func applyPlayback() {
        let plays = allowed && !isPaused
        for weakView in registered.values {
            if plays { weakView.view?.startAnimating() } else { weakView.view?.stopAnimating() }
        }
    }

    /// Cells unregister their views on reuse; this drops the entries of views that went away with their cell.
    private func pruneReleased() {
        registered = registered.filter { $0.value.view != nil }
    }
}
