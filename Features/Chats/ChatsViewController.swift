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
    private var chipStates: [StripItem: ChipState] = [:]
    private let columns = UIStackView()
    private let emptyState = UIStackView()
    private var controllers: [String: ChatViewController] = [:]
    private lazy var composerAccessoryView: ChatComposerAccessoryView = {
        let accessory = ChatComposerAccessoryView()
        accessory.onCompose = { [weak self] emotes in
            self?.syncFloatingComposer()
            self?.frontChat?.focusComposer(emotes: emotes)
        }
        return accessory
    }()
    private var composerAccessory: AnyObject?
    private var isOnScreen = false
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isOnScreen = true
        updateComposerAccessory(animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.setVisible(Set(shown))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isOnScreen = false
        updateComposerAccessory(animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.setVisible([])
    }

    /// On a phone the chat in front writes from the tab bar itself: its composer folds into the tab bar's accessory,
    /// in the same glass, and opens above the keyboard when tapped. Wider layouts keep the composer in each column.
    private var foldsComposerIntoTabBar: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return OrientationCoordinator.isPhone && tabBarController != nil
    }

    private var frontChat: ChatViewController? {
        shown.first.flatMap { controllers[$0] }
    }

    /// Shows the folded composer while this tab is on screen with a chat open, and takes it away otherwise, since
    /// the accessory belongs to the whole tab bar.
    private func updateComposerAccessory(animated: Bool) {
        guard #available(iOS 26.0, *), let tabBarController else { return }
        let wanted = foldsComposerIntoTabBar && isOnScreen && frontChat != nil
        if wanted {
            refreshComposerAccessory()
            if composerAccessory == nil || tabBarController.bottomAccessory !== composerAccessory {
                let accessory = UITabAccessory(contentView: composerAccessoryView)
                composerAccessory = accessory
                tabBarController.setBottomAccessory(accessory, animated: animated)
            }
        } else if let accessory = composerAccessory {
            composerAccessory = nil
            if tabBarController.bottomAccessory === accessory {
                tabBarController.setBottomAccessory(nil, animated: animated)
            }
        }
    }

    /// Hands the folded composer's frame to the chat in front, so its open composer floats in the same place and
    /// shape.
    private func syncFloatingComposer() {
        guard let chat = frontChat, chat.isViewLoaded, composerAccessoryView.window != nil else { return }
        let frame = composerAccessoryView.convert(composerAccessoryView.bounds, to: chat.view)
        guard frame.width > 0, frame.height > 0 else { return }
        let inset = max(0, min(frame.minX, chat.view.bounds.width - frame.maxX))
        chat.setFloatingComposerGeometry(horizontalInset: inset, height: frame.height)
    }

    private func refreshComposerAccessory() {
        guard let chat = frontChat else { return }
        composerAccessoryView.show(placeholder: chat.composerPlaceholder, draft: chat.composerDraft, canCompose: chat.canCompose)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncFloatingComposer()
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
            let state = self.chipState(for: item)
            cell.show(title: state.title, symbol: state.symbol, count: state.count, alert: state.alert, selected: state.selected)
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
        updateComposerAccessory(animated: true)
        setHidden(emptyState, !ids.isEmpty)
        setHidden(columns, ids.isEmpty)
        setHidden(strip, ids.isEmpty && model.mentions.isEmpty)
        if view.window != nil { model.setVisible(Set(shown)) }
        updateStrip(items: [.mentions] + ids.map(StripItem.chat))
    }

    /// What one chip shows; the strip redraws a chip only when this changes.
    private struct ChipState: Equatable {
        let title: String
        let symbol: String?
        let count: Int
        let alert: Bool
        let selected: Bool

        /// What decides the chip's width: a count that only changes value or color is redrawn in place, without asking
        /// the strip to measure its chips again.
        var widthKey: String {
            "\(title)|\(symbol ?? "")|\(ChatChipCell.badgeText(count)?.count ?? 0)"
        }
    }

    private func chipState(for item: StripItem) -> ChipState {
        switch item {
        case .mentions:
            let unseen = model.unseenMentions
            return ChipState(title: String(localized: "Mentions"), symbol: "at", count: unseen, alert: unseen > 0, selected: false)
        case .chat(let id):
            let session = model.session(for: id)
            return ChipState(
                title: model.entries.first { $0.id == id }?.name ?? id,
                symbol: nil,
                count: session?.unread ?? 0,
                alert: (session?.highlights ?? 0) > 0,
                selected: shown.contains(id)
            )
        }
    }

    /// Busy chats change the model several times a second; the strip is applied again only when its chips or their
    /// order changed, and then only the chips that look different are redrawn.
    private func updateStrip(items: [StripItem]) {
        let states = Dictionary(uniqueKeysWithValues: items.map { ($0, chipState(for: $0)) })
        let current = stripSource.snapshot()
        let changed = items.filter { chipStates[$0] != nil && chipStates[$0] != states[$0] }
        defer { chipStates = states }
        if current.itemIdentifiers == items {
            let resized = changed.filter { chipStates[$0]?.widthKey != states[$0]?.widthKey }
            for item in changed where !resized.contains(item) {
                guard let state = states[item], let indexPath = stripSource.indexPath(for: item),
                      let cell = strip.cellForItem(at: indexPath) as? ChatChipCell else { continue }
                cell.show(title: state.title, symbol: state.symbol, count: state.count, alert: state.alert, selected: state.selected)
            }
            guard !resized.isEmpty else { return }
            var snapshot = current
            snapshot.reconfigureItems(resized)
            stripSource.apply(snapshot, animatingDifferences: false)
            return
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, StripItem>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        snapshot.reconfigureItems(changed.filter { current.indexOfItem($0) != nil })
        stripSource.apply(snapshot, animatingDifferences: false)
    }

    private func setHidden(_ view: UIView, _ hidden: Bool) {
        if view.isHidden != hidden { view.isHidden = hidden }
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
            if foldsComposerIntoTabBar {
                chat.setComposerDock(.tabAccessory)
                chat.onComposerSummaryChanged = { [weak self, weak chat] in
                    guard let self, let chat, chat === self.frontChat else { return }
                    self.refreshComposerAccessory()
                }
            }
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
        switch sheet {
        case "mentions": presentMentions()
        case "compose": frontChat?.focusComposer()
        case "emotes": frontChat?.focusComposer(emotes: true)
        case "typing", "multiline", "reply", "auto", "emotetap", "sendtap":
            frontChat?.focusComposer()
            let drafts = [
                "typing": "gg that was clean",
                "multiline": "that last fight was unreal, the timing on the parry and then the swap into the shield build right before the boss phase change",
                "auto": "that was so cozy",
                "sendtap": "see you all tomorrow",
            ]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let chat = self?.frontChat else { return }
                chat.composeForScreenshot(draft: drafts[sheet], reply: sheet == "reply")
                guard sheet == "emotetap" || sheet == "sendtap" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let tapped = chat.tapComposerForTesting(sheet == "sendtap" ? "send" : "emote")
                    MidgarLog.info("chats: composer \(sheet) reached its button: \(tapped)", category: .chat)
                }
            }
        case "tap":
            let tapped = composerAccessoryView.tapFieldForTesting()
            MidgarLog.info("chats: folded composer tap reached the field: \(tapped)", category: .chat)
        case "draft":
            frontChat?.focusComposer()
            frontChat?.composeForScreenshot(draft: "see you all at the finals tonight", reply: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.frontChat?.endComposing() }
        default: presentPicker()
        }
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
    /// While the chat in front writes above the keyboard, the folded copy in the tab bar steps aside, so a hardware
    /// keyboard, which leaves the tab bar on screen, never shows two composers.
    func chatViewController(_ controller: ChatViewController, isComposing: Bool) {
        guard controller === frontChat else { return }
        composerAccessoryView.isUserInteractionEnabled = !isComposing
        UIView.animate(withDuration: 0.2) {
            self.composerAccessoryView.alpha = isComposing ? 0 : 1
        }
    }

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
    private var shownSymbol: String? = ""
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

    nonisolated static func badgeText(_ count: Int) -> String? {
        count == 0 ? nil : count > 99 ? "99+" : "\(count)"
    }

    func show(title: String, symbol: String?, count: Int, alert: Bool, selected: Bool) {
        if titleLabel.text != title { titleLabel.text = title }
        if symbol != shownSymbol {
            shownSymbol = symbol
            icon.image = symbol.flatMap { UIImage(systemName: $0) }
            icon.isHidden = symbol == nil
        }
        let foreground = selected ? UIColor.white : Theme.primaryText
        titleLabel.textColor = foreground
        icon.tintColor = selected ? .white : Theme.accent
        contentView.backgroundColor = selected ? Theme.accent : Theme.surfaceElevated
        if badge.isHidden != (count == 0) { badge.isHidden = count == 0 }
        let badgeText = Self.badgeText(count)
        if badge.text != badgeText { badge.text = badgeText }
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
