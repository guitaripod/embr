import UIKit
import Combine
import EmbrCore

/// A moderator's queue for one chat: messages AutoMod is holding, to allow or deny; unban requests, to approve or
/// deny; and the moderation log.
@MainActor
final class ModerationQueueViewController: UIViewController {
    private enum Page: Int, CaseIterable {
        case held
        case requests
        case log

        var title: String {
            switch self {
            case .held: String(localized: "AutoMod")
            case .requests: String(localized: "Requests")
            case .log: String(localized: "Log")
            }
        }
    }

    private enum Item: Hashable {
        case held(String)
        case request(String)
        case log(Int)
    }

    private let viewModel: ChatViewModel
    private let pages = UISegmentedControl(items: Page.allCases.map(\.title))
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private let emptyLabel = UILabel()
    private var queue: ModerationQueue
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: ChatViewModel, startingWithLog: Bool) {
        self.viewModel = viewModel
        self.queue = viewModel.moderation
        super.init(nibName: nil, bundle: nil)
        pages.selectedSegmentIndex = startingWithLog ? Page.log.rawValue : (queue.held.isEmpty && !queue.requests.isEmpty ? Page.requests.rawValue : Page.held.rawValue)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.titleView = pages
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        pages.addAction(UIAction { [weak self] _ in self?.apply() }, for: .valueChanged)
        setUpList()
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor, constant: -16),
        ])
        viewModel.moderationSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                self?.queue = queue
                self?.apply()
            }
            .store(in: &cancellables)
        apply()
    }

    private var page: Page {
        Page(rawValue: pages.selectedSegmentIndex) ?? .held
    }

    private func setUpList() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Theme.background
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath, allow: false)
        }
        config.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            self?.swipeActions(at: indexPath, allow: true)
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: StreamListLayout.readableList(using: config))
        collectionView.backgroundColor = Theme.background
        collectionView.allowsSelection = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { [weak self] cell, _, item in
            self?.configure(cell, item)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: row, for: indexPath, item: item)
        }
    }

    private func configure(_ cell: UICollectionViewListCell, _ item: Item) {
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.color = Theme.secondaryText
        content.textToSecondaryTextVerticalPadding = 4
        cell.backgroundConfiguration = Theme.groupedRowBackground()
        cell.accessories = []
        switch item {
        case .held(let id):
            guard let held = queue.held.first(where: { $0.id == id }) else { break }
            content.attributedText = Self.line(name: held.author.displayName, color: held.author.color, text: held.text)
            content.secondaryText = "\(held.reason.capitalized) · \(held.heldAt.formatted(date: .omitted, time: .shortened))"
            cell.accessories = Self.decisionButtons(
                allow: String(localized: "Allow"), deny: String(localized: "Deny"),
                onAllow: { [weak self] in self?.viewModel.resolveHeld(held, allow: true) },
                onDeny: { [weak self] in self?.viewModel.resolveHeld(held, allow: false) }
            )
        case .request(let id):
            guard let request = queue.requests.first(where: { $0.id == id }) else { break }
            content.attributedText = Self.line(name: request.user.displayName, color: request.user.color, text: request.text)
            content.secondaryText = request.createdAt.formatted(date: .abbreviated, time: .shortened)
            cell.accessories = Self.decisionButtons(
                allow: String(localized: "Unban"), deny: String(localized: "Deny"),
                onAllow: { [weak self] in self?.viewModel.resolveUnbanRequest(request, approve: true) },
                onDeny: { [weak self] in self?.viewModel.resolveUnbanRequest(request, approve: false) }
            )
        case .log(let index):
            guard queue.log.indices.contains(index) else { break }
            let entry = queue.log[index]
            content.text = entry.summary
            content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
            content.secondaryText = entry.messageText.map { "“\($0)” · " + entry.at.formatted(date: .omitted, time: .shortened) }
                ?? entry.at.formatted(date: .omitted, time: .shortened)
        }
        cell.contentConfiguration = content
    }

    private static func line(name: String, color: ChatColor?, text: String) -> NSAttributedString {
        let line = NSMutableAttributedString(string: name + ": ", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body).withSymbolicTraits(.traitBold),
            .foregroundColor: Theme.readableUsernameColor(color),
        ])
        line.append(NSAttributedString(string: text, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: Theme.primaryText]))
        return line
    }

    private static func decisionButtons(allow: String, deny: String, onAllow: @escaping () -> Void, onDeny: @escaping () -> Void) -> [UICellAccessory] {
        let row = UIStackView(arrangedSubviews: [
            decisionButton(deny, symbol: "xmark", tint: .systemRed) { Haptics.notify(.success); onDeny() },
            decisionButton(allow, symbol: "checkmark", tint: .systemGreen) { Haptics.notify(.success); onAllow() },
        ])
        row.axis = .horizontal
        row.spacing = 8
        return [.customView(configuration: .init(customView: row, placement: .trailing(), reservedLayoutWidth: .actual))]
    }

    private static func decisionButton(_ title: String, symbol: String, tint: UIColor, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: symbol)
        configuration.baseForegroundColor = tint
        configuration.baseBackgroundColor = tint
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = title
        return button
    }

    private func swipeActions(at indexPath: IndexPath, allow: Bool) -> UISwipeActionsConfiguration? {
        let action: (() -> Void)?
        switch dataSource.itemIdentifier(for: indexPath) {
        case .held(let id):
            action = queue.held.first { $0.id == id }.map { held in { [weak self] in self?.viewModel.resolveHeld(held, allow: allow) } }
        case .request(let id):
            action = queue.requests.first { $0.id == id }.map { request in { [weak self] in self?.viewModel.resolveUnbanRequest(request, approve: allow) } }
        default:
            action = nil
        }
        guard let action else { return nil }
        let title = allow ? String(localized: "Allow") : String(localized: "Deny")
        let swipe = UIContextualAction(style: allow ? .normal : .destructive, title: title) { _, _, done in
            Haptics.notify(.success)
            action()
            done(true)
        }
        swipe.backgroundColor = allow ? .systemGreen : .systemRed
        return UISwipeActionsConfiguration(actions: [swipe])
    }

    private func apply() {
        let items: [Item]
        switch page {
        case .held:
            items = queue.held.map { .held($0.id) }
            emptyLabel.text = String(localized: "No messages are waiting for AutoMod review.")
        case .requests:
            items = queue.requests.map { .request($0.id) }
            emptyLabel.text = String(localized: "No unban requests are waiting.")
        case .log:
            items = queue.log.indices.map(Item.log)
            emptyLabel.text = String(localized: "Moderation actions in this chat show up here while it's open.")
        }
        for (index, page) in Page.allCases.enumerated() {
            let count = page == .held ? queue.held.count : (page == .requests ? queue.requests.count : 0)
            pages.setTitle(count > 0 ? "\(page.title) (\(count))" : page.title, forSegmentAt: index)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyLabel.isHidden = !items.isEmpty
    }
}

private extension UIFont {
    func withSymbolicTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
