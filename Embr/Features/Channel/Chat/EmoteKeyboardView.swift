import UIKit
import SDWebImage
import EmbrCore

@MainActor
final class EmoteKeyboardView: UIView {
    var onInsert: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onSwitchToKeyboard: (() -> Void)?

    private struct EmoteSection: Hashable { let title: String }

    private let images: ImageLoading
    private var sections: [(section: EmoteSection, emotes: [Emote])] = []
    private var recents: [Emote] = []
    private var catalog = EmoteCatalog()

    private let chipsScroll = UIScrollView()
    private let chipsStack = UIStackView()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<EmoteSection, Emote>!
    private let keyboardButton = UIButton(type: .system)
    private let backspaceButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private var bottomBarBottom: NSLayoutConstraint!
    private var homeInset: CGFloat = 0

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 320 + homeInset) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let inset = window?.safeAreaInsets.bottom ?? 0
        guard inset != homeInset else { return }
        homeInset = inset
        bottomBarBottom?.constant = -homeInset
        invalidateIntrinsicContentSize()
    }

    init(images: ImageLoading) {
        self.images = images
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 320))
        autoresizingMask = .flexibleWidth
        backgroundColor = Theme.surface
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCatalog(_ catalog: EmoteCatalog) {
        self.catalog = catalog
        rebuild()
        loadRecents()
    }

    private func rebuild() {
        sections = Self.buildSections(catalog, recents: recents)
        rebuildChips()
        applySnapshot()
        emptyLabel.isHidden = !sections.isEmpty
    }

    private func loadRecents() {
        let catalog = self.catalog
        Task { [weak self] in
            let records = await DatabaseManager.shared.recentEmotes()
            var seen = Set<String>()
            let resolved = records.compactMap { catalog.lookup($0.name) }.filter { seen.insert($0.id).inserted }
            guard let self else { return }
            self.recents = resolved
            self.rebuild()
        }
    }

    private static func buildSections(_ catalog: EmoteCatalog, recents: [Emote]) -> [(EmoteSection, [Emote])] {
        let recentIDs = Set(recents.map(\.id))
        var result: [(EmoteSection, [Emote])] = baseSections(catalog, excluding: recentIDs)
        if !recents.isEmpty {
            result.insert((EmoteSection(title: String(localized: "Recent")), recents), at: 0)
        }
        return result
    }

    private static func baseSections(_ catalog: EmoteCatalog, excluding: Set<String>) -> [(EmoteSection, [Emote])] {
        let channel = Array(catalog.channel.values)
        let global = Array(catalog.global.values)
        var usedIDs = excluding
        func take(_ emotes: [Emote]) -> [Emote] {
            emotes
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
                .filter { usedIDs.insert($0.id).inserted }
        }

        var result: [(EmoteSection, [Emote])] = []
        let channelTwitch = take(channel.filter { $0.provider == .twitch })
        if !channelTwitch.isEmpty { result.append((EmoteSection(title: String(localized: "Channel")), channelTwitch)) }
        for provider in [EmoteProvider.sevenTV, .betterTTV, .frankerFaceZ] {
            let group = take((channel + global).filter { $0.provider == provider })
            if !group.isEmpty { result.append((EmoteSection(title: provider.displayName), group)) }
        }
        let globalTwitch = take(global.filter { $0.provider == .twitch })
        if !globalTwitch.isEmpty { result.append((EmoteSection(title: String(localized: "Global")), globalTwitch)) }
        return result
    }

    private func build() {
        chipsScroll.translatesAutoresizingMaskIntoConstraints = false
        chipsScroll.showsHorizontalScrollIndicator = false
        chipsStack.axis = .horizontal
        chipsStack.spacing = 6
        chipsStack.alignment = .center
        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        chipsStack.isLayoutMarginsRelativeArrangement = true
        chipsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        chipsScroll.addSubview(chipsStack)
        addSubview(chipsScroll)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .none
        addSubview(collectionView)
        configureDataSource()

        emptyLabel.text = String(localized: "No emotes available")
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        configureUtilityButton(keyboardButton, symbol: "keyboard")
        configureUtilityButton(backspaceButton, symbol: "delete.left")
        keyboardButton.accessibilityLabel = String(localized: "Keyboard")
        backspaceButton.accessibilityLabel = String(localized: "Delete")
        keyboardButton.addAction(UIAction { [weak self] _ in self?.onSwitchToKeyboard?() }, for: .touchUpInside)
        backspaceButton.addAction(UIAction { [weak self] _ in
            Haptics.impact(.light)
            self?.onBackspace?()
        }, for: .touchUpInside)

        let bottomBar = UIStackView(arrangedSubviews: [keyboardButton, UIView(), backspaceButton])
        bottomBar.axis = .horizontal
        bottomBar.alignment = .center
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.isLayoutMarginsRelativeArrangement = true
        bottomBar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        let separator = UIView()
        separator.backgroundColor = Theme.surfaceElevated
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        addSubview(bottomBar)
        bottomBarBottom = bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -homeInset)

        NSLayoutConstraint.activate([
            chipsScroll.topAnchor.constraint(equalTo: topAnchor),
            chipsScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            chipsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            chipsScroll.heightAnchor.constraint(equalToConstant: 40),
            chipsStack.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor),
            chipsStack.heightAnchor.constraint(equalTo: chipsScroll.frameLayoutGuide.heightAnchor),

            collectionView.topAnchor.constraint(equalTo: chipsScroll.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),

            bottomBar.topAnchor.constraint(equalTo: collectionView.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),
            bottomBarBottom
        ])
    }

    private func configureUtilityButton(_ button: UIButton, symbol: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        config.baseForegroundColor = Theme.secondaryText
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func rebuildChips() {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for entry in sections {
            let chip = UIButton(type: .system)
            var config = UIButton.Configuration.gray()
            config.baseForegroundColor = Theme.primaryText
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12)
            var title = AttributedString(entry.section.title)
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            config.attributedTitle = title
            chip.configuration = config
            let sectionTitle = entry.section.title
            chip.addAction(UIAction { [weak self] _ in self?.scrollToSection(title: sectionTitle) }, for: .touchUpInside)
            chipsStack.addArrangedSubview(chip)
        }
    }

    private func scrollToSection(title: String) {
        guard let index = sections.firstIndex(where: { $0.section.title == title }),
              !sections[index].emotes.isEmpty else { return }
        collectionView.scrollToItem(at: IndexPath(item: 0, section: index), at: .top, animated: true)
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            MainActor.assumeIsolated {
                let columns = max(5, Int(environment.container.effectiveContentSize.width / 60))
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .fractionalHeight(1.0)))
                item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(54)),
                    repeatingSubitem: item, count: columns)
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
                section.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(28)),
                        elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                ]
                return section
            }
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<EmoteKeyCell, Emote> { [weak self] cell, _, emote in
            guard let self else { return }
            cell.configure(with: emote, images: self.images)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, let section = self.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = view.defaultContentConfiguration()
            content.text = section.title
            content.textProperties.color = Theme.secondaryText
            content.textProperties.font = .systemFont(ofSize: 12, weight: .semibold)
            view.contentConfiguration = content
            view.backgroundConfiguration = .clear()
        }
        dataSource = UICollectionViewDiffableDataSource<EmoteSection, Emote>(collectionView: collectionView) { collectionView, indexPath, emote in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: emote)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<EmoteSection, Emote>()
        for entry in sections {
            snapshot.appendSections([entry.section])
            snapshot.appendItems(entry.emotes, toSection: entry.section)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension EmoteKeyboardView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let emote = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        EmoteUsage.record(emote)
        onInsert?(emote.name)
    }
}

@MainActor
private final class EmoteKeyCell: UICollectionViewCell {
    private let imageView = SDAnimatedImageView()
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.8),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? Theme.surfaceElevated : .clear }
    }

    func configure(with emote: Emote, images: ImageLoading) {
        loadTask?.cancel()
        imageView.image = nil
        imageView.autoPlayAnimatedImage = SettingsStore.shared.current.animateEmotes
        loadTask = Task { [weak self] in
            let image = await images.emoteImage(for: emote, scale: .x2)
            guard !Task.isCancelled else { return }
            self?.imageView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        imageView.image = nil
        contentView.backgroundColor = .clear
    }
}
