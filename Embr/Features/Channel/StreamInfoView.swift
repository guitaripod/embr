import UIKit
import EmbrCore

@MainActor
final class StreamInfoView: UIView {
    var onTapGame: (() -> Void)?

    private let titleLabel = UILabel()
    private let gameButton = UIButton(type: .system)
    private let metaLabel = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.background

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
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

        metaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        metaLabel.textColor = Theme.secondaryText
        metaLabel.textAlignment = .right
        metaLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [gameButton, UIView(), metaLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let stack = UIStackView(arrangedSubviews: [titleLabel, row])
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(channel: ChannelInfo) {
        titleLabel.text = channel.title.isEmpty ? channel.broadcasterName : channel.title
        setGame(channel.gameName)
        metaLabel.text = nil
        gameButton.isUserInteractionEnabled = false
    }

    func configure(stream: LiveStream) {
        titleLabel.text = stream.title
        setGame(stream.gameName)
        gameButton.isUserInteractionEnabled = !stream.gameName.isEmpty
        metaLabel.text = [Self.viewers(stream.viewerCount), Self.uptime(stream.startedAt)].compactMap { $0 }.joined(separator: "  ·  ")
    }

    private func setGame(_ name: String) {
        gameButton.isHidden = name.isEmpty
        gameButton.configuration?.title = name
    }

    private static func viewers(_ count: Int) -> String {
        let formatted: String
        if count >= 1_000_000 { formatted = String(format: "%.1fM", Double(count) / 1_000_000) }
        else if count >= 1_000 { formatted = String(format: "%.1fK", Double(count) / 1_000) }
        else { formatted = String(count) }
        return "\(formatted) watching"
    }

    private static func uptime(_ start: Date) -> String? {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return nil }
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
