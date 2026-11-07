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
    private var groups: [(EmoteSection, [Emote])] = []
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
    private var preferredHeights: [Bool: CGFloat] = [:]
    private var isLandscape = false
    private var chips: [UIButton] = []
    private var selectedChip = -1
    private var repeatTimer: Timer?
    private var repeatTicks = 0
    private let pageGuide = UILayoutGuide()
    private var pageLeading: NSLayoutConstraint!

    /// Keeps the keyboard's content to the page beside the fold that the chat is on, so no emote
    /// sits on the crease. The system keyboard splits itself across a fold; this one is a plain
    /// view and is told where the page begins.
    func setPageLeading(_ inset: CGFloat) {
        guard pageLeading.constant != inset else { return }
        pageLeading.constant = inset
    }

    override var intrinsicContentSize: CGSize {
        let height = preferredHeights[isLandscape] ?? Self.rememberedHeight(landscape: isLandscape) ?? typicalHeight
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    /// The system keyboard's usual height with its suggestion bar, until the real one has been seen.
    private var typicalHeight: CGFloat {
        if traitCollection.userInterfaceIdiom == .pad { return 398 + bottomInset }
        return (isLandscape ? 230 : 311) + bottomInset
    }

    /// The home indicator's inset, read from the key window before this keyboard is in one.
    private var bottomInset: CGFloat {
        if let window { return window.safeAreaInsets.bottom }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first { $0.isKeyWindow }?.safeAreaInsets.bottom ?? 0
    }

    /// Matches the system keyboard's height, home indicator area included, so swapping keyboards keeps the chat still.
    /// The height is kept per orientation and remembered, so the emote keyboard opened first next time is already the
    /// right size.
    func setPreferredHeight(_ height: CGFloat, landscape: Bool) {
        Self.remember(height, landscape: landscape)
        preferredHeights[landscape] = height
        if landscape == isLandscape { fitHeight(landscape: landscape) }
    }

    /// An input view comes up at its frame's height, so the frame takes the height this keyboard wants for the
    /// orientation before it shows, and again when the orientation changes.
    func fitHeight(landscape: Bool) {
        isLandscape = landscape
        let height = intrinsicContentSize.height
        guard abs(frame.height - height) > 0.5 else { return }
        frame.size.height = height
        invalidateIntrinsicContentSize()
    }

    private static func heightKey(landscape: Bool) -> String {
        landscape ? "chat.keyboardHeight.landscape" : "chat.keyboardHeight.portrait"
    }

    private static func rememberedHeight(landscape: Bool) -> CGFloat? {
        let stored = UserDefaults.standard.double(forKey: heightKey(landscape: landscape))
        return stored > 0 ? CGFloat(stored) : nil
    }

    private static func remember(_ height: CGFloat, landscape: Bool) {
        UserDefaults.standard.set(Double(height), forKey: heightKey(landscape: landscape))
    }

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
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 320))
        autoresizingMask = .flexibleWidth
        backgroundColor = Theme.surface
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Takes the chat's emotes. The catalog is sorted into sections only when it changed, not every time the keyboard
    /// opens, and the recent row is checked again in the background.
    func setCatalog(_ catalog: EmoteCatalog) {
        if catalog != self.catalog || groups.isEmpty {
            self.catalog = catalog
            groups = Self.groups(catalog)
            rebuild()
        }
        loadRecents()
    }

    private func rebuild() {
        let previous = sections.map(\.section)
        sections = buildSections()
        applySnapshot()
        if sections.map(\.section) != previous { rebuildChips() }
        selectChip(topSection())
        emptyLabel.isHidden = !sections.isEmpty
    }

    /// The section showing at the top of the grid.
    private func topSection() -> Int {
        let top = CGPoint(x: collectionView.bounds.midX, y: collectionView.contentOffset.y + collectionView.adjustedContentInset.top + 30)
        return (collectionView.indexPathForItem(at: top) ?? collectionView.indexPathsForVisibleItems.min())?.section ?? 0
    }

    private func loadRecents() {
        let catalog = self.catalog
        Task { [weak self] in
            let records = await DatabaseManager.shared.recentEmotes()
            var seen = Set<String>()
            let resolved = records.compactMap { catalog.lookup($0.name) }.filter { seen.insert($0.id).inserted }
            guard let self, resolved.map(\.id) != self.recents.map(\.id) else { return }
            self.recents = resolved
            self.rebuild()
        }
    }

    /// The recent row first, then the sorted groups without the emotes the recent row already shows.
    private func buildSections() -> [(section: EmoteSection, emotes: [Emote])] {
        var result: [(section: EmoteSection, emotes: [Emote])] = []
        if !recents.isEmpty {
            result.append((EmoteSection(title: String(localized: "Recent")), recents))
        }
        let recentIDs = Set(recents.map(\.id))
        for (section, emotes) in groups {
            let kept = recentIDs.isEmpty ? emotes : emotes.filter { !recentIDs.contains($0.id) }
            if !kept.isEmpty { result.append((section, kept)) }
        }
        return result
    }

    /// The catalog in sections: the channel's Twitch emotes, each third-party provider, then Twitch's globals, each
    /// sorted by name once with its sort key computed once per emote.
    private static func groups(_ catalog: EmoteCatalog) -> [(EmoteSection, [Emote])] {
        let channel = Array(catalog.channel.values)
        let global = Array(catalog.global.values)
        var usedIDs = Set<String>()
        func take(_ emotes: [Emote]) -> [Emote] {
            emotes
                .map { (key: $0.name.lowercased(), emote: $0) }
                .sorted { $0.key < $1.key }
                .map(\.emote)
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
        addLayoutGuide(pageGuide)
        pageLeading = pageGuide.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            pageLeading,
            pageGuide.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        chipsScroll.translatesAutoresizingMaskIntoConstraints = false
        chipsScroll.showsHorizontalScrollIndicator = false
        chipsStack.axis = .horizontal
        chipsStack.spacing = 6
        chipsStack.alignment = .center
        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        chipsStack.isLayoutMarginsRelativeArrangement = true
        chipsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: ChatMetrics.edge, bottom: 0, trailing: ChatMetrics.edge)
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
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
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
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdBackspace(_:)))
        hold.minimumPressDuration = 0.4
        backspaceButton.addGestureRecognizer(hold)

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
            chipsScroll.leadingAnchor.constraint(equalTo: pageGuide.leadingAnchor),
            chipsScroll.trailingAnchor.constraint(equalTo: pageGuide.trailingAnchor),
            chipsScroll.heightAnchor.constraint(equalToConstant: 44),
            chipsStack.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor),
            chipsStack.heightAnchor.constraint(equalTo: chipsScroll.frameLayoutGuide.heightAnchor),

            collectionView.topAnchor.constraint(equalTo: chipsScroll.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: pageGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: pageGuide.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: pageGuide.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: pageGuide.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),

            bottomBar.topAnchor.constraint(equalTo: collectionView.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: pageGuide.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: pageGuide.trailingAnchor),
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

    /// Holding delete keeps deleting, faster after the first few, like the system keyboard.
    @objc private func holdBackspace(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            repeatTicks = 0
            onBackspace?()
            Haptics.impact(.light)
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.repeatBackspace() }
            }
        case .ended, .cancelled, .failed:
            repeatTimer?.invalidate()
            repeatTimer = nil
        default:
            break
        }
    }

    private func repeatBackspace() {
        repeatTicks += 1
        guard repeatTicks > 4 || repeatTicks % 2 == 0 else { return }
        onBackspace?()
    }

    private func rebuildChips() {
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        chips = []
        selectedChip = -1
        for (index, entry) in sections.enumerated() {
            let chip = UIButton(type: .system)
            chip.addAction(UIAction { [weak self] _ in self?.scrollToSection(index) }, for: .touchUpInside)
            chips.append(chip)
            chipsStack.addArrangedSubview(chip)
            styleChip(chip, title: entry.section.title, selected: false)
        }
    }

    private func styleChip(_ chip: UIButton, title: String, selected: Bool) {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = selected ? Theme.accent : .tertiarySystemFill
        config.baseForegroundColor = selected ? Theme.onAccent : Theme.primaryText
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        var attributed = AttributedString(title)
        attributed.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold), maximumPointSize: 20)
        config.attributedTitle = attributed
        chip.configuration = config
        chip.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    /// Marks the section showing at the top of the grid and brings its chip into view.
    private func selectChip(_ index: Int) {
        guard index != selectedChip, chips.indices.contains(index) else { return }
        if chips.indices.contains(selectedChip) {
            styleChip(chips[selectedChip], title: sections[selectedChip].section.title, selected: false)
        }
        selectedChip = index
        styleChip(chips[index], title: sections[index].section.title, selected: true)
        let frame = chips[index].convert(chips[index].bounds, to: chipsScroll).insetBy(dx: -24, dy: 0)
        chipsScroll.scrollRectToVisible(frame, animated: true)
    }

    private func scrollToSection(_ index: Int) {
        guard sections.indices.contains(index), !sections[index].emotes.isEmpty else { return }
        Haptics.selection()
        selectChip(index)
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
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: ChatMetrics.edge - 4, bottom: 12, trailing: ChatMetrics.edge - 4)
                return section
            }
        }
    }

    private func configureDataSource() {
        let registration = UICollectionView.CellRegistration<EmoteKeyCell, Emote> { [weak self] cell, _, emote in
            guard let self else { return }
            cell.configure(with: emote, images: self.images)
        }
        dataSource = UICollectionViewDiffableDataSource<EmoteSection, Emote>(collectionView: collectionView) { collectionView, indexPath, emote in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: emote)
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
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        selectChip(topSection())
    }

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
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = emote.name
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
