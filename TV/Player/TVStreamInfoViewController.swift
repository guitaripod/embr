import UIKit
import EmbrCore

/// The Channel tab of the player's info panel (swipe down): who is streaming, for how long, to how many, and what.
final class TVStreamInfoViewController: UIViewController {
    private let avatar = TVArtworkView(shape: .circle, placeholderSymbol: "person.fill")
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let tagsLabel = UILabel()

    init() {
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Channel", comment: "Tab of the player's info panel")
        preferredContentSize = CGSize(width: 1760, height: 260)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = TVFont.bold(.headline)
        nameLabel.textColor = .white
        titleLabel.font = TVFont.body
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        titleLabel.numberOfLines = 2
        detailLabel.font = TVFont.cardSubtitle
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        tagsLabel.font = TVFont.cardSubtitle
        tagsLabel.textColor = Theme.accent

        let text = UIStackView(arrangedSubviews: [nameLabel, titleLabel, detailLabel, tagsLabel])
        text.axis = .vertical
        text.spacing = 8
        let row = UIStackView(arrangedSubviews: [avatar, text])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 40
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 160),
            avatar.heightAnchor.constraint(equalToConstant: 160),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func show(_ stream: LiveStream, avatarURL: URL?) {
        loadViewIfNeeded()
        avatar.setImage(avatarURL)
        nameLabel.text = stream.userName.isEmpty ? stream.userLogin : stream.userName
        titleLabel.text = stream.title
        let uptime = Date().timeIntervalSince(stream.startedAt)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = uptime >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        detailLabel.text = [
            stream.gameName,
            String(localized: "\(stream.viewerCount.formatted()) viewers"),
            formatter.string(from: uptime).map { String(localized: "Live for \($0)") },
            Locale.current.localizedString(forLanguageCode: stream.language),
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        tagsLabel.text = stream.tags.prefix(6).joined(separator: "  ")
        tagsLabel.isHidden = stream.tags.isEmpty
    }

    func show(title: String, subtitle: String, detail: String, avatarURL: URL?) {
        loadViewIfNeeded()
        avatar.setImage(avatarURL)
        nameLabel.text = title
        titleLabel.text = subtitle
        detailLabel.text = detail
        tagsLabel.isHidden = true
    }
}
