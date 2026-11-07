import UIKit
import EmbrCore
import MidgarCore

/// A chatter's card, opened by tapping their name: who they are, what they said while this chat was open, and what the
/// viewer can do about them. Anyone can mention, highlight, block or report them; a moderator can also delete the
/// message, time them out, ban or unban.
@MainActor
final class ChatUserCardViewController: UIViewController {
    struct Context {
        let user: ChatUser
        let message: ChatMessage?
        let channelLogin: String?
        let canChat: Bool
        let canModerate: Bool
        let isSelf: Bool
    }

    var onMention: ((ChatUser) -> Void)?
    var onOpenProfile: ((ChatUser) -> Void)?

    private let context: Context
    private let viewModel: ChatViewModel
    private let api: TwitchAPIProviding
    private let images: ImageLoading
    private let settings: SettingsStore
    private let animator = EmoteAnimator.shared

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let sinceLabel = UILabel()
    private let supporterTag = SupporterTag()
    private let historyTitle = UILabel()
    private let emptyLabel = UILabel()
    private var highlightButton: UIButton?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ChatRow>!
    private var loadedWidth: CGFloat = 0

    init(
        context: Context,
        viewModel: ChatViewModel,
        api: TwitchAPIProviding = AppContainer.shared.api,
        images: ImageLoading = AppContainer.shared.images,
        settings: SettingsStore = .shared
    ) {
        self.context = context
        self.viewModel = viewModel
        self.api = api
        self.images = images
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        let header = makeHeader()
        let actions = makeActions()
        let moderation = context.canModerate && !context.isSelf ? makeModeration() : nil
        setUpHistory()

        let stack = UIStackView(arrangedSubviews: [header, actions] + [moderation].compactMap { $0 } + [historyTitle])
        stack.axis = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(20, after: header)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor, constant: -8),
            collectionView.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor, constant: 8),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
            emptyLabel.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
        ])
        loadUser()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        settleHistory()
        let width = collectionView.bounds.width
        guard width > 0, width != loadedWidth else { return }
        loadedWidth = width
        loadHistory(width: width)
    }

    /// Keeps a short history right under its title: the list is upside down so the newest message sits at the bottom
    /// as in chat, which would otherwise leave a few messages floating at the foot of the card.
    private func settleHistory() {
        let clearance = view.safeAreaInsets.bottom
        let content = collectionView.collectionViewLayout.collectionViewContentSize.height
        let inset = clearance + max(0, collectionView.bounds.height - clearance - content)
        guard abs(collectionView.contentInset.top - inset) > 0.5 else { return }
        collectionView.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: 0, right: 0)
    }

    private func makeHeader() -> UIView {
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 32
        avatar.backgroundColor = Theme.surface
        avatar.image = UIImage(systemName: "person.fill")
        avatar.tintColor = Theme.secondaryText
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 64),
            avatar.heightAnchor.constraint(equalToConstant: 64),
        ])

        nameLabel.text = context.user.displayName
        nameLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.readableUsernameColor(context.user.color)
        nameLabel.numberOfLines = 1
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7

        detailLabel.text = "@\(context.user.login)"
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = Theme.secondaryText

        sinceLabel.font = .preferredFont(forTextStyle: .footnote)
        sinceLabel.adjustsFontForContentSizeCategory = true
        sinceLabel.textColor = Theme.secondaryText
        sinceLabel.isHidden = true

        supporterTag.show(userID: context.user.id)

        let names = UIStackView(arrangedSubviews: [nameLabel, detailLabel, sinceLabel])
        names.axis = .vertical
        names.spacing = 2
        let row = UIStackView(arrangedSubviews: [avatar, names])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        let column = UIStackView(arrangedSubviews: [row, supporterTag])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 10
        return column
    }

    private func makeActions() -> UIView {
        var buttons: [UIButton] = []
        if context.canChat && !context.isSelf {
            buttons.append(Self.cardButton(String(localized: "Mention"), symbol: "at") { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true) { self.onMention?(self.context.user) }
            })
        }
        if !context.isSelf {
            let highlight = Self.cardButton(String(localized: "Highlight"), symbol: "star") { [weak self] in
                self?.toggleHighlight()
            }
            highlightButton = highlight
            buttons.append(highlight)
            refreshHighlightButton()
        }
        buttons.append(Self.cardButton(String(localized: "Profile"), symbol: "person.crop.circle") { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { self.onOpenProfile?(self.context.user) }
        })
        let more = Self.cardButton(String(localized: "More"), symbol: "ellipsis", action: nil)
        more.menu = moreMenu()
        more.showsMenuAsPrimaryAction = true
        buttons.append(more)
        return Self.buttonRow(buttons)
    }

    private func moreMenu() -> UIMenu {
        var actions: [UIMenuElement] = [
            UIAction(title: String(localized: "Copy Name"), image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = self.context.user.login
                Haptics.selection()
            },
        ]
        if let message = context.message {
            actions.append(UIAction(title: String(localized: "Copy Message"), image: UIImage(systemName: "text.quote")) { _ in
                UIPasteboard.general.string = message.plainText
                Haptics.selection()
            })
        }
        guard !context.isSelf else { return UIMenu(children: actions) }
        var safety: [UIMenuElement] = []
        if let message = context.message {
            safety.append(UIMenu(title: String(localized: "Report Message"), image: UIImage(systemName: "exclamationmark.bubble"), options: .destructive, children: ChatReportReason.allCases.map { reason in
                UIAction(title: reason.title, attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    Haptics.notify(.success)
                    self.viewModel.report(message: message, reason: reason.rawValue, channelLogin: self.context.channelLogin)
                    self.dismiss(animated: true)
                }
            }))
        }
        safety.append(UIAction(title: String(localized: "Block @\(context.user.login)"), image: UIImage(systemName: "hand.raised"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            Haptics.notify(.success)
            self.viewModel.block(userID: self.context.user.id, login: self.context.user.login, message: self.context.message, channelLogin: self.context.channelLogin)
            self.dismiss(animated: true)
        })
        actions.append(UIMenu(options: .displayInline, children: safety))
        return UIMenu(children: actions)
    }

    private func makeModeration() -> UIView {
        let user = context.user
        var buttons: [UIButton] = []
        if let message = context.message, message.moderation == .visible {
            buttons.append(Self.cardButton(String(localized: "Delete"), symbol: "trash", tint: .systemRed) { [weak self] in
                self?.viewModel.deleteMessage(messageID: message.id)
                Haptics.notify(.success)
                self?.dismiss(animated: true)
            })
        }
        let timeout = Self.cardButton(String(localized: "Timeout"), symbol: "timer", tint: .systemOrange, action: nil)
        timeout.menu = UIMenu(title: String(localized: "Time Out @\(user.login)"), children: ChatTimeout.allCases.map { length in
            UIAction(title: length.title) { [weak self] _ in
                self?.viewModel.timeoutUser(userID: user.id, duration: length.rawValue)
                Haptics.notify(.success)
                self?.dismiss(animated: true)
            }
        })
        timeout.showsMenuAsPrimaryAction = true
        buttons.append(timeout)
        buttons.append(Self.cardButton(String(localized: "Ban"), symbol: "nosign", tint: .systemRed) { [weak self] in
            self?.confirmBan()
        })
        buttons.append(Self.cardButton(String(localized: "Unban"), symbol: "checkmark.shield", tint: .systemGreen) { [weak self] in
            self?.viewModel.unbanUser(userID: user.id)
            Haptics.notify(.success)
            self?.dismiss(animated: true)
        })
        let title = UILabel()
        title.text = String(localized: "Moderation")
        title.font = .preferredFont(forTextStyle: .footnote)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.secondaryText
        let column = UIStackView(arrangedSubviews: [title, Self.buttonRow(buttons)])
        column.axis = .vertical
        column.spacing = 8
        return column
    }

    private func confirmBan() {
        let user = context.user
        let alert = UIAlertController(
            title: String(localized: "Ban @\(user.login)?"),
            message: String(localized: "They can't chat here until a moderator unbans them."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Ban"), style: .destructive) { [weak self] _ in
            self?.viewModel.banUser(userID: user.id)
            Haptics.notify(.success)
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func setUpHistory() {
        historyTitle.font = .preferredFont(forTextStyle: .footnote)
        historyTitle.adjustsFontForContentSizeCategory = true
        historyTitle.textColor = Theme.secondaryText
        historyTitle.text = String(localized: "In this chat")

        emptyLabel.text = String(localized: "No messages from them since you opened this chat.")
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        let registration = UICollectionView.CellRegistration<MessageCell, ChatRow> { [weak self] cell, _, row in
            guard let self, let laidOut = row.laidOut else { return }
            cell.configure(with: laidOut, message: row.message, images: self.images, animator: self.animator)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        }
    }

    private func loadUser() {
        Task { [weak self] in
            guard let self else { return }
            guard let user = try? await self.api.user(login: self.context.user.login) else { return }
            self.apply(user)
            if let url = user.profileImageURL, let image = await self.images.image(for: url, targetScale: self.traitCollection.displayScale) {
                self.avatar.image = image
            }
        }
    }

    private func apply(_ user: TwitchUser) {
        var detail = "@\(user.login)"
        switch user.broadcasterType {
        case "partner": detail += " · " + String(localized: "Partner")
        case "affiliate": detail += " · " + String(localized: "Affiliate")
        default: break
        }
        detailLabel.text = detail
        if let created = user.createdAt {
            sinceLabel.text = String(localized: "On Twitch since \(created.formatted(.dateTime.month(.abbreviated).year()))")
            sinceLabel.isHidden = false
        }
        supporterTag.show(userID: user.id)
    }

    private func loadHistory(width: CGFloat) {
        Task { [weak self] in
            guard let self else { return }
            let rows = await self.viewModel.history(of: self.context.user, width: width)
            var snapshot = NSDiffableDataSourceSnapshot<Int, ChatRow>()
            snapshot.appendSections([0])
            snapshot.appendItems(rows.reversed(), toSection: 0)
            await self.dataSource.applySnapshotUsingReloadData(snapshot)
            self.collectionView.layoutIfNeeded()
            self.settleHistory()
            self.emptyLabel.isHidden = !rows.isEmpty
            self.historyTitle.text = rows.isEmpty
                ? String(localized: "In this chat")
                : String(localized: "In this chat · \(rows.count)")
        }
    }

    private var isHighlighted: Bool {
        settings.current.highlightUserList.contains { $0.caseInsensitiveCompare(context.user.login) == .orderedSame }
    }

    private func toggleHighlight() {
        let login = context.user.login.lowercased()
        let highlighted = isHighlighted
        settings.update { settings in
            var users = settings.highlightUserList.filter { $0.lowercased() != login }
            if !highlighted { users.append(login) }
            settings.highlightUsers = users
        }
        Haptics.selection()
        refreshHighlightButton()
    }

    private func refreshHighlightButton() {
        guard let button = highlightButton else { return }
        let on = isHighlighted
        button.configuration?.title = on ? String(localized: "Highlighted") : String(localized: "Highlight")
        button.configuration?.image = UIImage(systemName: on ? "star.fill" : "star")
        button.accessibilityTraits = on ? [.button, .selected] : .button
    }

    private static func cardButton(_ title: String, symbol: String, tint: UIColor = Theme.accent, action: (() -> Void)?) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = tint
        configuration.baseBackgroundColor = tint
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
            return updated
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        if let action {
            button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        }
        return button
    }

    private static func buttonRow(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }
}

extension ChatUserCardViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let height = dataSource.itemIdentifier(for: indexPath)?.laidOut?.height ?? 1
        return CGSize(width: collectionView.bounds.width, height: height)
    }
}

/// How long a moderator's timeout lasts, in seconds.
enum ChatTimeout: Int, CaseIterable {
    case minute = 60
    case tenMinutes = 600
    case hour = 3600
    case day = 86400
    case week = 604800

    var title: String {
        switch self {
        case .minute: String(localized: "1 minute")
        case .tenMinutes: String(localized: "10 minutes")
        case .hour: String(localized: "1 hour")
        case .day: String(localized: "1 day")
        case .week: String(localized: "1 week")
        }
    }
}

/// Why a viewer reports a chat message. The raw value is the canonical English reason the developer's review endpoint
/// receives; only the title is localized.
enum ChatReportReason: String, CaseIterable {
    case spam = "Spam"
    case harassment = "Harassment or bullying"
    case hate = "Hateful conduct"
    case violence = "Violence or threats"
    case other = "Other"

    var title: String {
        switch self {
        case .spam: String(localized: "Spam")
        case .harassment: String(localized: "Harassment or bullying")
        case .hate: String(localized: "Hateful conduct")
        case .violence: String(localized: "Violence or threats")
        case .other: String(localized: "Other")
        }
    }
}
