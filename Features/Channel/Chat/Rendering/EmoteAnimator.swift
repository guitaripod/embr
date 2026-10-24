import UIKit
import SDWebImage

@MainActor
final class EmoteAnimator {
    static let shared = EmoteAnimator()

    private var displayLink: CADisplayLink?
    private var registered: [ObjectIdentifier: WeakView] = [:]

    var isPaused: Bool = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused {
                stopAll()
            } else {
                resumeAll()
            }
            displayLink?.isPaused = isPaused
        }
    }

    private struct WeakView {
        weak var view: SDAnimatedImageView?
    }

    init() {}

    func register(_ view: UIView, url: URL) {
        guard let animatedView = view as? SDAnimatedImageView else { return }
        registered[ObjectIdentifier(animatedView)] = WeakView(view: animatedView)
        if !isPaused {
            animatedView.startAnimating()
        } else {
            animatedView.stopAnimating()
        }
        startIfNeeded()
    }

    func unregister(_ view: UIView) {
        if let animatedView = view as? SDAnimatedImageView {
            animatedView.stopAnimating()
        }
        registered.removeValue(forKey: ObjectIdentifier(view))
        if registered.isEmpty { stop() }
    }

    private func startIfNeeded() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 5, maximum: 15, preferred: 10)
        link.add(to: .main, forMode: .common)
        link.isPaused = isPaused
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        var deadKeys: [ObjectIdentifier] = []
        for (key, weakView) in registered where weakView.view == nil {
            deadKeys.append(key)
        }
        for key in deadKeys { registered.removeValue(forKey: key) }
        if registered.isEmpty { stop() }
    }

    private func stopAll() {
        for weakView in registered.values { weakView.view?.stopAnimating() }
    }

    private func resumeAll() {
        for weakView in registered.values { weakView.view?.startAnimating() }
    }
}
