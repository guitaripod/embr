import UIKit
import Combine

/// A page of settings drawn as the system Settings app draws its own: inset grouped rows with colored icons, switches,
/// pop-up menus and chevrons. The page asks its builder for its rows whenever something they show may have changed and
/// redraws only the rows that look different; switches and menus are kept per row, so flipping one animates in place.
@MainActor
class SettingsPageViewController: UIViewController, UICollectionViewDelegate {
    /// A row the search finds, with where it lives.
    struct SearchEntry {
        let item: SettingsItem
        let path: String
        let open: (UIViewController) -> Void
    }

    private let build: (SettingsPageViewController) -> [SettingsSection]
    private let changes: AnyPublisher<Void, Never>?
    private var sections: [SettingsSection] = []
    private var items: [String: SettingsItem] = [:]
    private var signatures: [String: String] = [:]
    private var sectionSignatures: [String: String] = [:]
    private var switches: [String: UISwitch] = [:]
    private var menuButtons: [String: UIButton] = [:]
    private var cancellables = Set<AnyCancellable>()
    private(set) var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var pendingHighlight: String?

    /// Rows the search looks through, for the page that offers search.
    var searchEntries: (() -> [SearchEntry])?
    private var searchQuery = ""

    init(title: String, changes: AnyPublisher<Void, Never>?, build: @escaping (SettingsPageViewController) -> [SettingsSection]) {
        self.build = build
        self.changes = changes
        super.init(nibName: nil, bundle: nil)
        self.title = title
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.groupedBackground
        configureCollectionView()
        configureDataSource()
        changes?
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.reload() }
            .store(in: &cancellables)
        if searchEntries != nil { configureSearch() }
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        flashPendingHighlight()
    }

    /// Opens the page scrolled to a row that flashes briefly, as a search result does in the system Settings app.
    func highlight(_ id: String) {
        pendingHighlight = id
        if view.window != nil { flashPendingHighlight() }
    }

    /// Asks the builder again and redraws what changed.
    func reload() {
        let next = isSearching ? searchSections() : build(self)
        apply(next)
    }

    private var isSearching: Bool {
        !searchQuery.isEmpty
    }

    private func apply(_ next: [SettingsSection]) {
        sections = next
        var nextItems: [String: SettingsItem] = [:]
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        var changedItems: [String] = []
        var changedSections: [String] = []
        let current = dataSource.snapshot()
        for section in next {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.items.map(\.id), toSection: section.id)
            let sectionSignature = (section.header ?? "") + "\u{1F}" + (section.footer ?? "")
            if let old = sectionSignatures[section.id], old != sectionSignature, current.indexOfSection(section.id) != nil {
                changedSections.append(section.id)
            }
            sectionSignatures[section.id] = sectionSignature
            for item in section.items {
                nextItems[item.id] = item
                let signature = item.signature
                if let old = signatures[item.id], old != signature, current.indexOfItem(item.id) != nil {
                    changedItems.append(item.id)
                }
                signatures[item.id] = signature
                if case .toggle(let isOn, _) = item.kind, let toggle = switches[item.id], toggle.isOn != isOn {
                    toggle.setOn(isOn, animated: view.window != nil)
                }
            }
        }
        items = nextItems
        snapshot.reconfigureItems(changedItems.filter { snapshot.indexOfItem($0) != nil })
        if !changedSections.isEmpty { snapshot.reloadSections(changedSections) }
        dataSource.apply(snapshot, animatingDifferences: current.numberOfItems > 0 && view.window != nil)
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        config.footerMode = .supplementary
        config.backgroundColor = Theme.groupedBackground
        let layout = StreamListLayout.readableList(using: config)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Theme.groupedBackground
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            cell.configurationUpdateHandler = { cell, state in
                cell.backgroundConfiguration = Theme.groupedRowBackground(for: state)
            }
            guard let self, let item = self.items[id] else { return }
            self.configure(cell, with: item)
        }
        let custom = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, id in
            cell.backgroundConfiguration = .clear()
            guard let self, let item = self.items[id], case .custom(let make) = item.kind,
                  !cell.contentView.subviews.contains(where: { $0.accessibilityIdentifier == id }) else { return }
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            let content = make()
            content.accessibilityIdentifier = id
            content.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                content.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
                content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
            ])
        }
        dataSource = UICollectionViewDiffableDataSource<String, String>(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            if case .custom = self?.items[id]?.kind {
                return collectionView.dequeueConfiguredReusableCell(using: custom, for: indexPath, item: id)
            }
            return collectionView.dequeueConfiguredReusableCell(using: row, for: indexPath, item: id)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] view, _, indexPath in
            var content = UIListContentConfiguration.header()
            content.text = self?.section(at: indexPath.section)?.header
            view.contentConfiguration = content
        }
        let footer = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionFooter) { [weak self] view, _, indexPath in
            var content = UIListContentConfiguration.footer()
            content.text = self?.section(at: indexPath.section)?.footer
            view.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: kind == UICollectionView.elementKindSectionFooter ? footer : header, for: indexPath)
        }
    }

    private func section(at index: Int) -> SettingsSection? {
        sections.indices.contains(index) ? sections[index] : nil
    }

    private func configure(_ cell: UICollectionViewListCell, with item: SettingsItem) {
        var content: UIListContentConfiguration
        switch item.kind {
        case .link(let value, _) where value != nil && item.subtitle == nil:
            content = .valueCell()
            content.secondaryText = value
        case .value(let value):
            content = .valueCell()
            content.secondaryText = value
        default:
            content = item.subtitle == nil ? .cell() : .subtitleCell()
            content.secondaryText = item.subtitle
            content.secondaryTextProperties.color = Theme.secondaryText
            content.textToSecondaryTextVerticalPadding = 2
        }
        content.text = item.title
        if let icon = item.icon {
            content.image = icon.image
            content.imageProperties.maximumSize = CGSize(width: SettingsIcon.side, height: SettingsIcon.side)
            content.imageProperties.reservedLayoutSize = CGSize(width: SettingsIcon.side, height: SettingsIcon.side)
            content.imageToTextPadding = 14
        }
        cell.accessories = []
        cell.accessibilityTraits = []
        cell.accessibilityValue = nil

        switch item.kind {
        case .toggle(let isOn, _):
            cell.contentConfiguration = content
            let toggle = switchControl(for: item.id)
            if toggle.isOn != isOn { toggle.setOn(isOn, animated: cell.window != nil) }
            toggle.accessibilityLabel = item.title
            cell.accessories = [.customView(configuration: .init(customView: toggle, placement: .trailing()))]
        case .link:
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .menu(let value, let choices):
            cell.contentConfiguration = content
            let button = menuButton(for: item.id)
            updateMenu(button, title: item.title, value: value, choices: choices)
            cell.accessories = [.customView(configuration: .init(customView: button, placement: .trailing(), reservedLayoutWidth: .actual))]
        case .action(let role, _):
            switch role {
            case .normal: break
            case .accent: content.textProperties.color = Theme.accent
            case .destructive: content.textProperties.color = .systemRed
            }
            cell.contentConfiguration = content
            cell.accessibilityTraits = .button
        case .price(let price, _):
            cell.contentConfiguration = content
            cell.accessibilityTraits = .button
            cell.accessibilityValue = price
            if let price {
                cell.accessories = [.label(text: price, options: .init(tintColor: Theme.accent, font: .preferredFont(forTextStyle: .body)))]
            }
        case .value:
            cell.contentConfiguration = content
        case .loading:
            content.textProperties.color = Theme.secondaryText
            cell.contentConfiguration = content
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            cell.accessories = [.customView(configuration: .init(customView: spinner, placement: .trailing()))]
        case .slider(let value, let range, let step, let format, let commit):
            cell.contentConfiguration = SliderRowConfiguration(icon: item.icon?.image, title: item.title, value: value, range: range, step: step, format: format, commit: commit)
        case .stepper(let value, let range, let step, let format, let commit):
            cell.contentConfiguration = StepperRowConfiguration(icon: item.icon?.image, title: item.title, value: value, range: range, step: step, format: format, commit: commit)
        case .profile(let name, let detail, let avatar, _):
            var profile = UIListContentConfiguration.subtitleCell()
            profile.text = name
            profile.secondaryText = detail
            profile.textProperties.font = .preferredFont(forTextStyle: .title3).withWeight(.semibold)
            profile.textProperties.adjustsFontForContentSizeCategory = true
            profile.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            profile.secondaryTextProperties.adjustsFontForContentSizeCategory = true
            profile.secondaryTextProperties.color = Theme.secondaryText
            profile.textToSecondaryTextVerticalPadding = 3
            profile.image = avatar ?? Self.placeholderAvatar
            profile.imageProperties.maximumSize = CGSize(width: 60, height: 60)
            profile.imageProperties.reservedLayoutSize = CGSize(width: 60, height: 60)
            profile.imageProperties.cornerRadius = 30
            profile.imageProperties.tintColor = Theme.secondaryText
            profile.imageToTextPadding = 14
            profile.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            cell.contentConfiguration = profile
            cell.accessories = [.disclosureIndicator()]
        case .custom:
            break
        }
    }

    private static let placeholderAvatar = UIImage(
        systemName: "person.crop.circle.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 60, weight: .regular)
    )

    /// One switch per row for the life of the page, so a redraw changes its state instead of replacing it.
    private func switchControl(for id: String) -> UISwitch {
        if let existing = switches[id] { return existing }
        let toggle = UISwitch()
        toggle.onTintColor = Theme.accent
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            guard let self, let toggle, let item = self.items[id], case .toggle(_, let set) = item.kind else { return }
            set(toggle.isOn)
        }, for: .valueChanged)
        switches[id] = toggle
        return toggle
    }

    private func menuButton(for id: String) -> UIButton {
        if let existing = menuButtons[id] { return existing }
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = Theme.secondaryText
        config.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(textStyle: .footnote, scale: .small))
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .body)
            return attributes
        }
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        menuButtons[id] = button
        return button
    }

    private func updateMenu(_ button: UIButton, title: String, value: String, choices: [SettingsChoice]) {
        var config = button.configuration
        config?.title = value
        button.configuration = config
        button.accessibilityLabel = title
        button.accessibilityValue = value
        button.menu = UIMenu(children: choices.map { choice in
            UIAction(title: choice.title, state: choice.isSelected ? .on : .off) { _ in choice.select() }
        })
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return false }
        return items[id]?.isSelectable ?? false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath), let item = items[id] else { return }
        let cell = collectionView.cellForItem(at: indexPath)
        switch item.kind {
        case .link(_, let open), .profile(_, _, _, let open):
            open(self)
            if navigationController?.topViewController === self, presentedViewController == nil {
                collectionView.deselectItem(at: indexPath, animated: true)
            }
        case .action(_, let run), .price(_, let run):
            collectionView.deselectItem(at: indexPath, animated: true)
            run(self, cell)
        default:
            collectionView.deselectItem(at: indexPath, animated: true)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let selected = collectionView.indexPathsForSelectedItems else { return }
        for indexPath in selected {
            if let coordinator = transitionCoordinator {
                coordinator.animate(alongsideTransition: { _ in
                    self.collectionView.deselectItem(at: indexPath, animated: true)
                }, completion: { context in
                    if context.isCancelled { self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: []) }
                })
            } else {
                collectionView.deselectItem(at: indexPath, animated: animated)
            }
        }
    }

    private func flashPendingHighlight() {
        guard let id = pendingHighlight, let indexPath = dataSource.indexPath(for: id) else { return }
        pendingHighlight = nil
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let cell = self?.collectionView.cellForItem(at: indexPath) else { return }
            cell.isHighlighted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                UIView.transition(with: cell, duration: 0.4, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    cell.isHighlighted = false
                }
            }
        }
    }
}

extension SettingsPageViewController: UISearchResultsUpdating {
    private func configureSearch() {
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Search")
        navigationItem.searchController = search
        navigationItem.preferredSearchBarPlacement = .stacked
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != searchQuery else { return }
        searchQuery = query
        reload()
    }

    /// Every row whose title or keywords contain the query, each showing where it lives.
    private func searchSections() -> [SettingsSection] {
        let needle = searchQuery.lowercased()
        let entries = (searchEntries?() ?? []).filter { entry in
            entry.item.title.lowercased().contains(needle) || entry.item.keywords.contains { $0.lowercased().contains(needle) }
        }
        guard !entries.isEmpty else {
            return [SettingsSection(id: "search.empty", footer: String(localized: "No settings match “\(searchQuery)”."), items: [])]
        }
        let rows = entries.map { entry in
            SettingsItem(id: "search." + entry.item.id, title: entry.item.title, subtitle: entry.path, icon: entry.item.icon, kind: .link(value: nil, open: entry.open))
        }
        return [SettingsSection(id: "search.results", items: rows)]
    }
}
