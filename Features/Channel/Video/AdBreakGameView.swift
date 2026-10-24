import UIKit

/// A self-contained one-tap "flappy"-style mini-game shown in the video area during
/// ad breaks: an ember flies through scrolling pillars. Scales to any bounds, persists
/// a high score, and runs a `CADisplayLink` only while actively playing.
@MainActor
final class AdBreakGameView: UIView {

    private enum State { case idle, playing, gameOver }

    private struct Pillar {
        var x: CGFloat
        var gapCenter: CGFloat
        var scored: Bool
    }

    var onActiveChanged: ((Bool) -> Void)?

    private let ember = UIImageView()
    private let scoreLabel = UILabel()
    private let messageLabel = UILabel()
    private let hintLabel = UILabel()

    private var pillarViews: [(top: UIView, bottom: UIView)] = []
    private var pillars: [Pillar] = []

    private var state: State = .idle
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    private var emberY: CGFloat = 0
    private var velocity: CGFloat = 0
    private var score = 0

    private let emberRadius: CGFloat = 13
    private let pillarColor = Theme.accent.withAlphaComponent(0.85)
    private static let bestKey = "embr.flyer.best"

    private var best: Int {
        get { UserDefaults.standard.integer(forKey: Self.bestKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.bestKey) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        buildHierarchy()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func activate() {
        guard state != .playing else { return }
        resetToIdle()
    }

    func deactivate() {
        stopLink()
        state = .idle
        onActiveChanged?(false)
    }

    private func buildHierarchy() {
        ember.image = UIImage(systemName: "flame.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold))
        ember.tintColor = .systemOrange
        ember.contentMode = .scaleAspectFit
        ember.frame = CGRect(x: 0, y: 0, width: emberRadius * 2 + 6, height: emberRadius * 2 + 6)
        ember.layer.shadowColor = UIColor.systemOrange.cgColor
        ember.layer.shadowRadius = 8
        ember.layer.shadowOpacity = 0.7
        ember.layer.shadowOffset = .zero
        addSubview(ember)

        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .heavy)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreLabel.isHidden = true
        scoreLabel.layer.shadowColor = UIColor.black.cgColor
        scoreLabel.layer.shadowRadius = 4
        scoreLabel.layer.shadowOpacity = 0.5
        scoreLabel.layer.shadowOffset = .zero
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scoreLabel)

        messageLabel.font = .systemFont(ofSize: 17, weight: .bold)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            scoreLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            scoreLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),

            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    private var emberX: CGFloat { bounds.width * 0.3 }
    private var pillarWidth: CGFloat { max(38, bounds.width * 0.11) }
    private var gapHeight: CGFloat { max(120, bounds.height * 0.42) }
    private var pillarSpacing: CGFloat { max(180, bounds.width * 0.78) }
    private var gravity: CGFloat { bounds.height * 3.0 }
    private var flapVelocity: CGFloat { -bounds.height * 1.0 }
    private var pillarSpeed: CGFloat { max(150, bounds.width * 0.5) }

    private func resetToIdle() {
        stopLink()
        state = .idle
        score = 0
        pillars = []
        emberY = bounds.height / 2
        velocity = 0
        layoutPillars()
        scoreLabel.isHidden = true
        ember.center = CGPoint(x: emberX, y: emberY)
        ember.transform = .identity
        messageLabel.text = String(localized: "Embr Flyer")
        hintLabel.text = best > 0 ? String(localized: "Tap to fly · Best \(best)") : String(localized: "Tap to fly through the ad break")
        messageLabel.isHidden = false
        hintLabel.isHidden = false
        onActiveChanged?(false)
    }

    private func beginPlaying() {
        state = .playing
        score = 0
        velocity = flapVelocity
        emberY = bounds.height / 2
        let firstX = bounds.width + pillarWidth
        pillars = [makePillar(at: firstX), makePillar(at: firstX + pillarSpacing)]
        scoreLabel.isHidden = false
        scoreLabel.text = "0"
        messageLabel.isHidden = true
        hintLabel.isHidden = true
        startLink()
        Haptics.impact(.light)
        onActiveChanged?(true)
    }

    private func makePillar(at x: CGFloat) -> Pillar {
        let margin = gapHeight / 2 + 24
        let center = CGFloat.random(in: margin...max(margin, bounds.height - margin))
        return Pillar(x: x, gapCenter: center, scored: false)
    }

    @objc private func handleTap() {
        switch state {
        case .idle: beginPlaying()
        case .playing: velocity = flapVelocity
        case .gameOver: resetToIdle()
        }
    }

    private func startLink() {
        stopLink()
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard state == .playing, bounds.height > 0 else { return }
        let dt: CFTimeInterval = lastTimestamp == 0 ? link.duration : min(link.timestamp - lastTimestamp, 1.0 / 30.0)
        lastTimestamp = link.timestamp

        velocity += gravity * CGFloat(dt)
        emberY += velocity * CGFloat(dt)

        let speed = pillarSpeed * CGFloat(dt)
        for index in pillars.indices { pillars[index].x -= speed }
        pillars.removeAll { $0.x + pillarWidth < 0 }
        if let last = pillars.last, last.x < bounds.width - pillarSpacing {
            pillars.append(makePillar(at: last.x + pillarSpacing))
        }

        for index in pillars.indices where !pillars[index].scored && pillars[index].x + pillarWidth < emberX - emberRadius {
            pillars[index].scored = true
            score += 1
            scoreLabel.text = "\(score)"
            if score > best { best = score }
            Haptics.impact(.light)
        }

        layoutPillars()
        ember.center = CGPoint(x: emberX, y: emberY)
        ember.transform = CGAffineTransform(rotationAngle: max(-0.45, min(0.9, velocity / (bounds.height * 2.2))))

        if isColliding() { endGame() }
    }

    private func isColliding() -> Bool {
        if emberY - emberRadius < 0 || emberY + emberRadius > bounds.height { return true }
        let emberBox = CGRect(x: emberX - emberRadius, y: emberY - emberRadius, width: emberRadius * 2, height: emberRadius * 2)
        for pillar in pillars {
            let gapTop = pillar.gapCenter - gapHeight / 2
            let gapBottom = pillar.gapCenter + gapHeight / 2
            let top = CGRect(x: pillar.x, y: 0, width: pillarWidth, height: gapTop)
            let bottom = CGRect(x: pillar.x, y: gapBottom, width: pillarWidth, height: bounds.height - gapBottom)
            if emberBox.intersects(top) || emberBox.intersects(bottom) { return true }
        }
        return false
    }

    private func endGame() {
        stopLink()
        state = .gameOver
        Haptics.notify(.error)
        scoreLabel.isHidden = true
        messageLabel.text = String(localized: "Score \(score)")
        hintLabel.text = String(localized: "Best \(best) · Tap to play again")
        messageLabel.isHidden = false
        hintLabel.isHidden = false
        UIView.animate(withDuration: 0.25, delay: 0, options: [.allowUserInteraction]) {
            self.ember.alpha = 0.4
        } completion: { _ in
            self.ember.alpha = 1
        }
        onActiveChanged?(false)
    }

    private func layoutPillars() {
        while pillarViews.count < pillars.count {
            let top = makePillarView()
            let bottom = makePillarView()
            insertSubview(top, belowSubview: ember)
            insertSubview(bottom, belowSubview: ember)
            pillarViews.append((top, bottom))
        }
        for (index, views) in pillarViews.enumerated() {
            guard index < pillars.count else {
                views.top.isHidden = true
                views.bottom.isHidden = true
                continue
            }
            let pillar = pillars[index]
            let gapTop = pillar.gapCenter - gapHeight / 2
            let gapBottom = pillar.gapCenter + gapHeight / 2
            views.top.isHidden = false
            views.bottom.isHidden = false
            views.top.frame = CGRect(x: pillar.x, y: -12, width: pillarWidth, height: gapTop + 12)
            views.bottom.frame = CGRect(x: pillar.x, y: gapBottom, width: pillarWidth, height: bounds.height - gapBottom + 12)
        }
    }

    private func makePillarView() -> UIView {
        let view = UIView()
        view.backgroundColor = pillarColor
        view.layer.cornerRadius = 7
        view.layer.cornerCurve = .continuous
        return view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if state == .idle {
            emberY = bounds.height / 2
            ember.center = CGPoint(x: emberX, y: emberY)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { deactivate() }
    }

    isolated deinit {
        displayLink?.invalidate()
    }
}
