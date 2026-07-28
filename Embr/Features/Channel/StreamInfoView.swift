import UIKit
import EmbrCore

@MainActor
final class StreamInfoView: UIView {
    var onTapGame: (() -> Void)?

    private enum State: Equatable { case loading, live, offline }

    private struct LiveSnapshot: Equatable {
        var title: String
        var gameName: String
        var tags: [String]
        var isMature: Bool
        var viewerCount: Int
        var startedAt: Date?
    }

    private let titleLabel = UILabel()
    private let gameButton = UIButton(type: .system)

    private let livePill = UIView()
    private let liveDot = UIImageView()
    private let liveLabel = UILabel()

    private let viewersIcon = UIImageView()
    private let viewersLabel = UILabel()
    private let viewersStack = UIStackView()

    private let uptimeIcon = UIImageView()
    private let uptimeLabel = UILabel()
    private let uptimeStack = UIStackView()

    private let statusLabel = UILabel()
    private let matureBadge = UILabel()
    private let tagsRow = UIStackView()

    private var state: State = .loading
    private var channelName = ""
    private var startedAt: Date?
    private var viewerCount = 0
    private var uptimeTimer: Timer?
    private var pulseActive = false
    private var lastSnapshot: LiveSnapshot?

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.background

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        var gameConfig = UIButton.Configuration.tinted()
        gameConfig.image = UIImage(systemName: "gamecontroller.fill")
        gameConfig.imagePadding = 5
        gameConfig.cornerStyle = .capsule
        gameConfig.baseForegroundColor = Theme.accent
        gameConfig.buttonSize = .small
        gameButton.configuration = gameConfig
        gameButton.contentHorizontalAlignment = .leading
        gameButton.addAction(UIAction { [weak self] _ in self?.onTapGame?() }, for: .touchUpInside)
        gameButton.setContentHuggingPriority(.required, for: .horizontal)
        gameButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        gameButton.titleLabel?.adjustsFontForContentSizeCategory = true

        configureLivePill()
        configureStat(viewersStack, icon: viewersIcon, label: viewersLabel, symbol: "eye.fill")
        configureStat(uptimeStack, icon: uptimeIcon, label: uptimeLabel, symbol: "clock.fill")

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.isHidden = true

        configureMatureBadge()

        let liveCluster = UIStackView(arrangedSubviews: [livePill, viewersStack, uptimeStack, statusLabel])
        liveCluster.axis = .horizontal
        liveCluster.spacing = 10
        liveCluster.alignment = .center
        liveCluster.setContentHuggingPriority(.required, for: .horizontal)
        liveCluster.setContentCompressionResistancePriority(.required, for: .horizontal)

        let metaRow = UIStackView(arrangedSubviews: [gameButton, UIView(), liveCluster])
        metaRow.axis = .horizontal
        metaRow.spacing = 8
        metaRow.alignment = .center

        tagsRow.axis = .horizontal
        tagsRow.spacing = 6
        tagsRow.alignment = .center
        tagsRow.isHidden = true

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, matureBadge])
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .top

        let stack = UIStackView(arrangedSubviews: [titleRow, metaRow, tagsRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        titleLabel.isAccessibilityElement = true
        viewersStack.isAccessibilityElement = false
        uptimeStack.isAccessibilityElement = false
        livePill.isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit { uptimeTimer?.invalidate() }

    private func configureLivePill() {
        liveDot.image = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .black))
        liveDot.tintColor = .white
        liveDot.contentMode = .scaleAspectFit

        liveLabel.text = String(localized: "LIVE")
        liveLabel.font = .systemFont(ofSize: 10, weight: .heavy)
        liveLabel.textColor = .white

        let pillStack = UIStackView(arrangedSubviews: [liveDot, liveLabel])
        pillStack.axis = .horizontal
        pillStack.spacing = 4
        pillStack.alignment = .center
        pillStack.isUserInteractionEnabled = false
        pillStack.translatesAutoresizingMaskIntoConstraints = false

        livePill.backgroundColor = Theme.liveDot
        livePill.layer.cornerRadius = 8
        livePill.layer.cornerCurve = .continuous
        livePill.setContentHuggingPriority(.required, for: .horizontal)
        livePill.addSubview(pillStack)
        NSLayoutConstraint.activate([
            pillStack.topAnchor.constraint(equalTo: livePill.topAnchor, constant: 3),
            pillStack.bottomAnchor.constraint(equalTo: livePill.bottomAnchor, constant: -3),
            pillStack.leadingAnchor.constraint(equalTo: livePill.leadingAnchor, constant: 7),
            pillStack.trailingAnchor.constraint(equalTo: livePill.trailingAnchor, constant: -7)
        ])
    }

    private func configureStat(_ stack: UIStackView, icon: UIImageView, label: UILabel, symbol: String) {
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.secondaryText
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureMatureBadge() {
        matureBadge.text = "18+"
        matureBadge.font = .systemFont(ofSize: 10, weight: .heavy)
        matureBadge.textColor = .white
        matureBadge.backgroundColor = Theme.slowMode
        matureBadge.textAlignment = .center
        matureBadge.layer.cornerRadius = 5
        matureBadge.layer.cornerCurve = .continuous
        matureBadge.layer.masksToBounds = true
        matureBadge.setContentHuggingPriority(.required, for: .horizontal)
        matureBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        matureBadge.isHidden = true
        matureBadge.accessibilityLabel = String(localized: "Mature content")
        NSLayoutConstraint.activate([
            matureBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),
            matureBadge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func configure(channel: ChannelInfo) {
        channelName = channel.broadcasterName
        lastSnapshot = nil
        stopUptimeTicking()
        transition {
            self.titleLabel.text = channel.title.isEmpty ? channel.broadcasterName : channel.title
            self.setGame(channel.gameName)
            self.gameButton.isUserInteractionEnabled = false
            self.setTags(channel.tags)
            self.matureBadge.isHidden = true
            self.applyState(.loading)
        }
        updateAccessibility(category: channel.gameName)
    }

    func configure(stream: LiveStream) {
        let snapshot = LiveSnapshot(
            title: stream.title,
            gameName: stream.gameName,
            tags: stream.tags,
            isMature: stream.isMature,
            viewerCount: stream.viewerCount,
            startedAt: stream.startedAt
        )
        if state == .live, lastSnapshot == snapshot { return }
        let wasLive = state == .live
        lastSnapshot = snapshot
        channelName = stream.userName
        startedAt = stream.startedAt
        viewerCount = stream.viewerCount
        let apply = {
            self.titleLabel.text = stream.title
            self.setGame(stream.gameName)
            self.gameButton.isUserInteractionEnabled = !stream.gameName.isEmpty
            self.setTags(stream.tags)
            self.matureBadge.isHidden = !stream.isMature
            self.viewersLabel.text = Self.viewers(stream.viewerCount)
            self.applyState(.live)
        }
        if wasLive { apply() } else { transition(apply) }
        updateUptime()
        startUptimeTicking()
        updateAccessibility(category: stream.gameName)
    }

    func setOffline() {
        guard state != .offline else { return }
        stopUptimeTicking()
        lastSnapshot = nil
        let announce = state == .live
        transition {
            self.statusLabel.text = String(localized: "Offline")
            self.applyState(.offline)
        }
        titleLabel.accessibilityLabel = String(localized: "\(channelName), offline")
        if announce {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "\(channelName) went offline"))
        }
    }

    private func applyState(_ new: State) {
        let wasLive = state == .live
        state = new
        let live = new == .live
        livePill.isHidden = !live
        viewersStack.isHidden = !live
        uptimeStack.isHidden = !live
        statusLabel.isHidden = new != .offline
        if live {
            if !wasLive { setPulse(true) }
        } else {
            setPulse(false)
        }
        if new == .offline {
            matureBadge.isHidden = true
            setTags([])
            gameButton.isUserInteractionEnabled = false
        }
    }

    private func setPulse(_ on: Bool) {
        guard on != pulseActive else { return }
        pulseActive = on
        if on, !Motion.reduced {
            liveDot.addSymbolEffect(.pulse, options: .repeating)
        } else {
            liveDot.removeAllSymbolEffects()
        }
    }

    private func transition(_ changes: @escaping () -> Void) {
        UIView.transition(with: self, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction], animations: changes)
    }

    private func setGame(_ name: String) {
        gameButton.isHidden = name.isEmpty
        gameButton.configuration?.title = name
    }

    private func setTags(_ tags: [String]) {
        tagsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let chips = tags.prefix(3)
        for tag in chips {
            tagsRow.addArrangedSubview(makeChip(tag))
        }
        tagsRow.isHidden = chips.isEmpty
    }

    private func makeChip(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = Theme.secondaryText
        let chip = UIView()
        chip.backgroundColor = Theme.surface
        chip.layer.cornerRadius = 9
        chip.layer.cornerCurve = .continuous
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8)
        ])
        return chip
    }

    private func startUptimeTicking() {
        guard uptimeTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateUptime() }
        }
        RunLoop.main.add(timer, forMode: .common)
        uptimeTimer = timer
    }

    private func stopUptimeTicking() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    private func updateUptime() {
        guard state == .live, let startedAt else { return }
        if let text = Self.uptime(startedAt) {
            uptimeLabel.text = text
            uptimeStack.isHidden = false
        } else {
            uptimeStack.isHidden = true
        }
        updateAccessibility(category: gameButton.configuration?.title ?? "")
    }

    private func updateAccessibility(category: String) {
        var parts = [channelName]
        switch state {
        case .loading: parts.append(String(localized: "loading"))
        case .offline: parts.append(String(localized: "offline"))
        case .live:
            parts.append(String(localized: "live"))
            if !category.isEmpty { parts.append(category) }
            parts.append(String(localized: "\(viewerCount) viewers"))
            if let startedAt, let up = Self.uptime(startedAt) { parts.append(String(localized: "up \(up)")) }
        }
        titleLabel.accessibilityLabel = parts.joined(separator: ", ")
    }

    private static func viewers(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return String(count)
    }

    private static func uptime(_ start: Date) -> String? {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        return hours > 0 ? String(localized: "\(hours)h \(minutes)m") : String(localized: "\(minutes)m")
    }
}
