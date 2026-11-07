import UIKit
import Combine
import SafariServices
import EmbrCore
import MidgarCore

/// The Chats tab: chats kept open without their video, in a strip across the top with unread and highlight counts.
/// The phone shows the chat in front; a wide iPad shows up to three side by side, the ones picked most recently. The
/// strip starts with Mentions, everything that stood out for the viewer in any open chat.
@MainActor
final class ChatsViewController: UIViewController {
    private enum StripItem: Hashable {
        case mentions
        case chat(String)
    }

    private let model: ChatsModel
    private let auth: AuthService
    private var strip: UICollectionView!
    private var stripHeight: NSLayoutConstraint!
    private var stripSource: UICollectionViewDiffableDataSource<Int, StripItem>!
    private let columns = UIStackView()
    private let emptyState = UIStackView()
    private var controllers: [String: ChatViewController] = [:]
    private var controllerSessions: [String: ChatsModel.Session] = [:]
    private var columnViews: [String: ChatColumnView] = [:]
    private var recent: [String] = []
    private var shown: [String] = []
    private var cancellables = Set<AnyCancellable>()

    init(model: ChatsModel = .shared, auth: AuthService = .shared) {
        self.model = model
        self.auth = auth
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Chats")
        tabBarItem = UITabBarItem(
            title: String(localized: "Chats"),
            image: UIImage(systemName: "bubble.left.and.bubble.right"),
            selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            primaryAction: UIAction(title: String(localized: "Add a Chat")) { [weak self] _ in self?.presentPicker() }
        )
        setUpStrip()
        setUpColumns()
        setUpEmptyState()
        model.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: ChatsViewController, _) in
            controller.render()
        }
        Task { [weak self] in
            await self?.model.activate()
            self?.render()
        }
        render()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.setVisible(Set(shown))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.setVisible([])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let fits = columnCapacity
        if fits != lastCapacity {
            lastCapacity = fits
            render()
        }
    }

    private var lastCapacity = 1

    /// How many chats fit side by side: one on a phone or a narrow window, up to three at about 330 points each.
    private var columnCapacity: Int {
        guard traitCollection.horizontalSizeClass == .regular else { return 1 }
        return max(1, min(3, Int(view.bounds.width / 330)))
    }

    private func setUpStrip() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let size = NSCollectionLayoutSize(widthDimension: .estimated(120), heightDimension: .absolute(Self.chipHeight))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8
            section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: ChatMetrics.edge, bottom: 6, trailing: ChatMetrics.edge)
            return section
        }
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        layout.configuration = configuration
        strip = UICollectionView(frame: .zero, collectionViewLayout: layout)
        strip.backgroundColor = .clear
        strip.showsHorizontalScrollIndicator = false
        strip.delegate = self
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)

        let chip = UICollectionView.CellRegistration<ChatChipCell, StripItem> { [weak self] cell, _, item in
            guard let self else { return }
            switch item {
            case .mentions:
                cell.show(
                    title: String(localized: "Mentions"),
                    symbol: "at",
                    count: self.model.unseenMentions,
                    alert: self.model.unseenMentions > 0,
                    selected: false
                )
            case .chat(let id):
                let entry = self.model.entries.first { $0.id == id }
                let session = self.model.session(for: id)
                cell.show(
                    title: entry?.name ?? id,
                    symbol: nil,
                    count: session?.unread ?? 0,
                    alert: (session?.highlights ?? 0) > 0,
                    selected: self.shown.contains(id)
                )
            }
        }
        stripSource = UICollectionViewDiffableDataSource(collectionView: strip) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: chip, for: indexPath, item: item)
        }
    }

    /// Chips grow with Dynamic Type, and the strip with them.
    nonisolated private static var chipHeight: CGFloat {
        UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 36)
    }

    private func setUpColumns() {
        stripHeight = strip.heightAnchor.constraint(equalToConstant: Self.chipHeight + 12)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: ChatsViewController, _) in
            controller.stripHeight.constant = Self.chipHeight + 12
            controller.strip.collectionViewLayout.invalidateLayout()
        }
        columns.axis = .horizontal
        columns.distribution = .fillEqually
        columns.spacing = 1
        columns.backgroundColor = Theme.surface
        columns.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(columns)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stripHeight,
            columns.topAnchor.constraint(equalTo: strip.bottomAnchor),
            columns.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            columns.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setUpEmptyState() {
        let symbol = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right"))
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        symbol.tintColor = Theme.secondaryText
        let title = UILabel()
        title.text = String(localized: "Keep chats open")
        title.font = .preferredFont(forTextStyle: .title3)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.primaryText
        let body = UILabel()
        body.text = String(localized: "Chats stay connected here without the video, with what you missed counted on each. On iPad, three fit side by side.")
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = Theme.secondaryText
        body.textAlignment = .center
        body.numberOfLines = 0
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "Add a Chat")
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = Theme.accent
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.presentPicker() })
        [symbol, title, body, button].forEach(emptyState.addArrangedSubview)
        emptyState.axis = .vertical
        emptyState.alignment = .center
        emptyState.spacing = 12
        emptyState.setCustomSpacing(20, after: body)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            emptyState.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor, constant: 16),
            emptyState.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor, constant: -16),
        ])
    }

    /// Lays the screen out for the open chats: the strip, then the chat in front, or on a wide iPad as many as fit side
    /// by side in strip order, the most recently picked first to stay.
    private func render() {
        dropReplacedControllers()
        let ids = model.entries.map(\.id)
        recent.removeAll { !ids.contains($0) }
        if let selected = model.selected?.id {
            recent.removeAll { $0 == selected }
            recent.insert(selected, at: 0)
        }
        let capacity = columnCapacity
        var picked = Set(recent.prefix(capacity))
        for id in ids where picked.count < capacity { picked.insert(id) }
        let next = ids.filter { picked.contains($0) }
        if next != shown || shown.contains(where: { columnViews[$0] == nil }) {
            shown = next
            layoutColumns()
        }
        for (id, column) in columnViews {
            column.setShowsHeader(shown.count > 1)
            column.setTitle(model.entries.first { $0.id == id }?.name ?? id)
        }
        emptyState.isHidden = !ids.isEmpty
        columns.isHidden = ids.isEmpty
        strip.isHidden = ids.isEmpty && model.mentions.isEmpty
        if view.window != nil { model.setVisible(Set(shown)) }
        var snapshot = NSDiffableDataSourceSnapshot<Int, StripItem>()
        snapshot.appendSections([0])
        snapshot.appendItems([.mentions] + ids.map(StripItem.chat), toSection: 0)
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        stripSource.apply(snapshot, animatingDifferences: false)
    }

    /// Takes down the chat of every column whose session the model replaced, as it does when the viewer signs in or
    /// out, so the column is built again around the new one.
    private func dropReplacedControllers() {
        for (id, session) in controllerSessions where model.session(for: id) !== session {
            controllerSessions[id] = nil
            columnViews.removeValue(forKey: id)?.removeFromSuperview()
            guard let controller = controllers.removeValue(forKey: id) else { continue }
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
    }

    private func layoutColumns() {
        for id in Array(columnViews.keys) where !shown.contains(id) {
            columnViews.removeValue(forKey: id)?.removeFromSuperview()
            if let controller = controllers[id] {
                controller.willMove(toParent: nil)
                controller.view.removeFromSuperview()
                controller.removeFromParent()
            }
        }
        for id in Array(controllers.keys) where !model.contains(id) {
            controllers.removeValue(forKey: id)
            controllerSessions.removeValue(forKey: id)
        }
        for (index, id) in shown.enumerated() {
            guard let session = model.session(for: id) else { continue }
            let column = columnViews[id] ?? makeColumn(for: session)
            if column.superview !== columns {
                columns.insertArrangedSubview(column, at: min(index, columns.arrangedSubviews.count))
            } else if columns.arrangedSubviews.firstIndex(of: column) != index {
                columns.removeArrangedSubview(column)
                columns.insertArrangedSubview(column, at: min(index, columns.arrangedSubviews.count))
            }
        }
    }

    private func makeColumn(for session: ChatsModel.Session) -> ChatColumnView {
        let id = session.entry.id
        let controller = controllers[id] ?? {
            let chat = ChatViewController(
                viewModel: session.viewModel,
                isAnonymous: session.viewer == nil,
                currentUserLogin: session.viewer?.login,
                broadcasterLogin: session.entry.login
            )
            chat.delegate = self
            controllers[id] = chat
            controllerSessions[id] = session
            return chat
        }()
        let column = ChatColumnView()
        column.onClose = { [weak self] in self?.model.close(id) }
        column.onWatch = { [weak self] in self?.watch(session.entry) }
        addChild(controller)
        column.embed(controller.view)
        controller.didMove(toParent: self)
        columnViews[id] = column
        return column
    }

    #if DEBUG
    /// Opens the picker or Mentions over the tab, for a screenshot.
    func presentForScreenshot(_ sheet: String) {
        sheet == "mentions" ? presentMentions() : presentPicker()
    }
    #endif

    private func presentPicker() {
        let picker = ChatPickerViewController { [weak self] entry in
            self?.model.open(entry)
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    private func presentMentions() {
        model.markMentionsSeen()
        let mentions = MentionsViewController(model: model) { [weak self] mention in
            self?.model.select(mention.channel.id)
        }
        present(UINavigationController(rootViewController: mentions), animated: true)
    }

    /// Tapping the chip of the chat already showing alone offers what its column header offers when chats share the
    /// screen: watching the stream or closing the chat.
    private func presentChatActions(for entry: ChatsModel.Entry, from source: UIView?) {
        let sheet = UIAlertController(title: entry.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Watch Stream"), style: .default) { [weak self] _ in
            self?.watch(entry)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Close Chat"), style: .destructive) { [weak self] _ in
            Haptics.impact(.light)
            self?.model.close(entry.id)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController, let source {
            popover.sourceView = source
            popover.sourceRect = source.bounds
        }
        present(sheet, animated: true)
    }

    private func watch(_ entry: ChatsModel.Entry) {
        guard let url = URL(string: "embr://channel/\(entry.login)"), let tabBar = tabBarController as? RootTabBarController else { return }
        let router = DeepLinkRouter()
        Task { await router.handle(url, from: tabBar) }
    }
}

extension ChatsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        Haptics.selection()
        switch stripSource.itemIdentifier(for: indexPath) {
        case .mentions: presentMentions()
        case .chat(let id):
            if shown.count == 1, shown.first == id, let entry = model.entries.first(where: { $0.id == id }) {
                presentChatActions(for: entry, from: collectionView.cellForItem(at: indexPath))
            } else {
                model.select(id)
            }
        case nil: break
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, case .chat(let id) = stripSource.itemIdentifier(for: indexPath),
              let index = model.entries.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = model.entries[index]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIMenuElement] = [
                UIAction(title: String(localized: "Watch Stream"), image: UIImage(systemName: "play.rectangle")) { _ in self?.watch(entry) },
            ]
            var order: [UIAction] = []
            if index > 0 {
                order.append(UIAction(title: String(localized: "Move Left"), image: UIImage(systemName: "arrow.left")) { _ in self?.model.move(from: index, to: index - 1) })
            }
            if let count = self?.model.entries.count, index < count - 1 {
                order.append(UIAction(title: String(localized: "Move Right"), image: UIImage(systemName: "arrow.right")) { _ in self?.model.move(from: index, to: index + 1) })
            }
            if !order.isEmpty { actions.append(UIMenu(options: .displayInline, children: order)) }
            actions.append(UIAction(title: String(localized: "Close Chat"), image: UIImage(systemName: "xmark"), attributes: .destructive) { _ in self?.model.close(id) })
            return UIMenu(title: entry.name, children: actions)
        }
    }
}

extension ChatsViewController: ChatViewControllerDelegate {
    func chatViewController(_ controller: ChatViewController, didTapUsername user: ChatUser) {
        present(ProfileSheetViewController(login: user.login, navigator: navigationController), animated: true)
    }

    func chatViewController(_ controller: ChatViewController, didTapEmote emote: Emote) {}

    func chatViewController(_ controller: ChatViewController, didTapLink url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Theme.accent
        present(safari, animated: true)
    }

    func chatViewController(_ controller: ChatViewController, didRequestReplyTo message: ChatMessage) {
        controller.beginReply(to: message)
    }

    func chatViewControllerDidRequestLogin(_ controller: ChatViewController) {
        guard let anchor = view.window else { return }
        Task { [weak self] in
            do {
                _ = try await self?.auth.login(presentationAnchor: anchor)
            } catch {
                MidgarLog.notice("chats login failed: \(error)", category: .auth)
            }
        }
    }
}

/// One chat in the Chats tab, with a slim header naming it when several are side by side.
@MainActor
private final class ChatColumnView: UIView {
    var onClose: (() -> Void)?
    var onWatch: (() -> Void)?

    private let header = UIView()
    private let titleLabel = UILabel()
    private let body = UIView()
    private var headerHeight: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText
        let watch = Self.iconButton("play.rectangle", label: String(localized: "Watch Stream")) { [weak self] in self?.onWatch?() }
        let close = Self.iconButton("xmark", label: String(localized: "Close Chat")) { [weak self] in self?.onClose?() }
        let row = UIStackView(arrangedSubviews: [titleLabel, UIView(), watch, close])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(row)
        header.backgroundColor = Theme.surface
        header.clipsToBounds = true
        let stack = UIStackView(arrangedSubviews: [header, body])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        headerHeight = header.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerHeight,
            row.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func embed(_ content: UIView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: body.topAnchor),
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: body.bottomAnchor),
        ])
    }

    func setShowsHeader(_ shows: Bool) {
        headerHeight.constant = shows ? 40 : 0
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    private static func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .subheadline)
        configuration.baseForegroundColor = Theme.secondaryText
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = label
        return button
    }
}

/// A chip in the Chats strip: a chat's name, or Mentions, with a count of what arrived out of sight.
@MainActor
private final class ChatChipCell: UICollectionViewCell {
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let badge = BadgeLabel()
    private let row = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 18
        contentView.layer.cornerCurve = .continuous
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        badge.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        badge.textAlignment = .center
        badge.layer.cornerRadius = 9
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: 18),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])
        [icon, titleLabel, badge].forEach(row.addArrangedSubview)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(title: String, symbol: String?, count: Int, alert: Bool, selected: Bool) {
        titleLabel.text = title
        icon.image = symbol.flatMap { UIImage(systemName: $0) }
        icon.isHidden = symbol == nil
        let foreground = selected ? UIColor.white : Theme.primaryText
        titleLabel.textColor = foreground
        icon.tintColor = selected ? .white : Theme.accent
        contentView.backgroundColor = selected ? Theme.accent : Theme.surfaceElevated
        badge.isHidden = count == 0
        badge.text = count > 99 ? "99+" : "\(count)"
        badge.backgroundColor = alert ? Theme.accent : Theme.secondaryText.withAlphaComponent(0.25)
        badge.textColor = alert ? .white : Theme.primaryText
        if selected, alert { badge.backgroundColor = .white; badge.textColor = Theme.accent }
        accessibilityLabel = title
        accessibilityValue = count > 0 ? String(localized: "\(count) unread") : nil
        accessibilityTraits = selected ? [.button, .selected] : .button
    }
}

/// A count in a capsule, padded so a one-digit count reads as a circle and longer ones grow.
private final class BadgeLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 10, height: size.height)
    }
}
