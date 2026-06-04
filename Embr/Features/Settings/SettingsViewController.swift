import UIKit
import Combine
import AuthenticationServices
import EmbrCore

@MainActor
final class SettingsViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case general
        case chat
        case video
        case account
        case about

        var title: String {
            switch self {
            case .general: return "General"
            case .chat: return "Chat"
            case .video: return "Video"
            case .account: return "Account"
            case .about: return "About"
            }
        }
    }

    private enum Row: Hashable {
        case theme
        case accentPurple
        case openLinksInApp
        case haptics
        case shareCrashLogs

        case showTimestamps
        case compactChat
        case messageScale
        case fontSizeDelta
        case showDeletedMessages
        case highlightMentions
        case recentMessagesBackfill
        case animateEmotes
        case thirdPartyEmotes(EmoteProvider)

        case defaultQuality
        case defaultToHighest
        case autoplay
        case chatDelaySeconds
        case autoSyncChatDelay
        case keepScreenAwake

        case accountStatus
        case accountAction

        case version
        case github
    }

    private let store: SettingsStore
    private let auth: AuthService
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Row>!
    private var cancellables = Set<AnyCancellable>()
    private var authState: AuthState = .anonymous

    private let thirdPartyProviders: [EmoteProvider] = [.sevenTV, .betterTTV, .frankerFaceZ]

    init(store: SettingsStore = .shared, auth: AuthService = .shared) {
        self.store = store
        self.auth = auth
        super.init(nibName: nil, bundle: nil)
        title = "Settings"
        tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        configureCollectionView()
        configureDataSource()
        bind()
        applySnapshot()
    }

    private func configureCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Theme.background
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.delegate = self
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureDataSource() {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Row> { [weak self] cell, _, row in
            self?.configure(cell, for: row)
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Row>(collectionView: collectionView) { collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: row)
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            guard let section = Section(rawValue: indexPath.section) else { return }
            var content = UIListContentConfiguration.header()
            content.text = section.title
            header.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func bind() {
        store.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconfigureVisibleRows()
            }
            .store(in: &cancellables)

        auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.authState = state
                self?.reconfigureAccountRows()
            }
            .store(in: &cancellables)
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.theme, .accentPurple, .openLinksInApp, .haptics, .shareCrashLogs], toSection: .general)
        snapshot.appendItems(
            [.showTimestamps, .compactChat, .messageScale, .fontSizeDelta, .showDeletedMessages,
             .highlightMentions, .recentMessagesBackfill, .animateEmotes]
            + thirdPartyProviders.map(Row.thirdPartyEmotes),
            toSection: .chat
        )
        snapshot.appendItems(
            [.defaultQuality, .defaultToHighest, .autoplay, .chatDelaySeconds, .autoSyncChatDelay, .keepScreenAwake],
            toSection: .video
        )
        snapshot.appendItems([.accountStatus, .accountAction], toSection: .account)
        snapshot.appendItems([.version, .github], toSection: .about)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reconfigureVisibleRows() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reconfigureAccountRows() {
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([.accountStatus, .accountAction])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func configure(_ cell: UICollectionViewListCell, for row: Row) {
        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        var content = cell.defaultContentConfiguration()
        let settings = store.current

        switch row {
        case .theme:
            content.text = "Theme"
            cell.contentConfiguration = content
            cell.accessories = [.customView(configuration: .init(customView: themeButton(selected: settings.theme), placement: .trailing()))]

        case .accentPurple:
            switchRow(cell, &content, title: "Use Twitch Purple Accent", isOn: settings.accentUsesTwitchPurple) { store, on in
                store.update { $0.accentUsesTwitchPurple = on }
            }
        case .openLinksInApp:
            switchRow(cell, &content, title: "Open Links In App", isOn: settings.openLinksInApp) { store, on in
                store.update { $0.openLinksInApp = on }
            }
        case .haptics:
            switchRow(cell, &content, title: "Haptics", isOn: settings.hapticsEnabled) { store, on in
                store.update { $0.hapticsEnabled = on }
            }
        case .shareCrashLogs:
            switchRow(cell, &content, title: "Share Crash Logs", isOn: settings.shareCrashLogs) { store, on in
                store.update { $0.shareCrashLogs = on }
            }

        case .showTimestamps:
            switchRow(cell, &content, title: "Show Timestamps", isOn: settings.showTimestamps) { store, on in
                store.update { $0.showTimestamps = on }
            }
        case .compactChat:
            switchRow(cell, &content, title: "Compact Chat", isOn: settings.compactChat) { store, on in
                store.update { $0.compactChat = on }
            }
        case .messageScale:
            sliderRow(
                cell,
                title: "Message Scale",
                value: settings.messageScale, range: 0.75...1.5, step: 0.05,
                format: { String(format: "%.2fx", $0) }
            ) { store, value in
                store.update { $0.messageScale = value }
            }
        case .fontSizeDelta:
            stepperRow(
                cell, &content,
                title: "Font Size Adjustment",
                value: Double(settings.fontSizeDelta), range: -4...8, step: 1,
                valueText: settings.fontSizeDelta >= 0 ? "+\(settings.fontSizeDelta)" : "\(settings.fontSizeDelta)"
            ) { store, value in
                store.update { $0.fontSizeDelta = Int(value.rounded()) }
            }
        case .showDeletedMessages:
            switchRow(cell, &content, title: "Show Deleted Messages", isOn: settings.showDeletedMessages) { store, on in
                store.update { $0.showDeletedMessages = on }
            }
        case .highlightMentions:
            switchRow(cell, &content, title: "Highlight Mentions", isOn: settings.highlightMentions) { store, on in
                store.update { $0.highlightMentions = on }
            }
        case .recentMessagesBackfill:
            switchRow(cell, &content, title: "Backfill Recent Messages", isOn: settings.recentMessagesBackfill) { store, on in
                store.update { $0.recentMessagesBackfill = on }
            }
        case .animateEmotes:
            switchRow(cell, &content, title: "Animate Emotes", isOn: settings.animateEmotes) { store, on in
                store.update { $0.animateEmotes = on }
            }
        case let .thirdPartyEmotes(provider):
            switchRow(cell, &content, title: provider.displayName + " Emotes", isOn: settings.thirdPartyEmotesEnabled(provider)) { store, on in
                store.update { $0.showThirdPartyEmotes[provider] = on }
            }

        case .defaultQuality:
            content.text = "Default Quality"
            content.secondaryText = settings.defaultQuality.capitalized
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .defaultToHighest:
            switchRow(cell, &content, title: "Default To Highest Quality", isOn: settings.defaultToHighest) { store, on in
                store.update { $0.defaultToHighest = on }
            }
        case .autoplay:
            switchRow(cell, &content, title: "Autoplay", isOn: settings.autoplay) { store, on in
                store.update { $0.autoplay = on }
            }
        case .chatDelaySeconds:
            sliderRow(
                cell,
                title: "Chat Delay",
                value: settings.chatDelaySeconds, range: 0...10, step: 0.5,
                format: { String(format: "%.1fs", $0) }
            ) { store, value in
                store.update { $0.chatDelaySeconds = value }
            }
        case .autoSyncChatDelay:
            switchRow(cell, &content, title: "Auto-Sync Chat Delay", isOn: settings.autoSyncChatDelay) { store, on in
                store.update { $0.autoSyncChatDelay = on }
            }
        case .keepScreenAwake:
            switchRow(cell, &content, title: "Keep Screen Awake", isOn: settings.keepScreenAwake) { store, on in
                store.update { $0.keepScreenAwake = on }
            }

        case .accountStatus:
            switch authState {
            case let .authenticated(user):
                content.text = user.displayName
                content.secondaryText = "@\(user.login)"
            case .anonymous:
                content.text = "Not Logged In"
                content.secondaryText = "Browsing anonymously"
            }
            cell.contentConfiguration = content
            cell.accessories = []
        case .accountAction:
            switch authState {
            case .authenticated:
                content.text = "Log Out"
                content.textProperties.color = .systemRed
            case .anonymous:
                content.text = "Log In with Twitch"
                content.textProperties.color = Theme.accent
            }
            cell.contentConfiguration = content
            cell.accessories = []

        case .version:
            content.text = "Version"
            content.secondaryText = Self.versionString
            cell.contentConfiguration = content
            cell.accessories = []
        case .github:
            content.text = "GitHub"
            content.textProperties.color = Theme.link
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }
    }

    private func switchRow(
        _ cell: UICollectionViewListCell,
        _ content: inout UIListContentConfiguration,
        title: String,
        isOn: Bool,
        action: @escaping (SettingsStore, Bool) -> Void
    ) {
        content.text = title
        cell.contentConfiguration = content
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = Theme.accent
        toggle.addAction(UIAction { [weak self] act in
            guard let self, let sw = act.sender as? UISwitch else { return }
            action(self.store, sw.isOn)
        }, for: .valueChanged)
        cell.accessories = [.customView(configuration: .init(customView: toggle, placement: .trailing()))]
    }

    private func sliderRow(
        _ cell: UICollectionViewListCell,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        action: @escaping (SettingsStore, Double) -> Void
    ) {
        cell.accessories = []
        cell.contentConfiguration = SliderRowConfiguration(
            title: title,
            value: value,
            range: range,
            step: step,
            format: format,
            commit: { [weak self] snapped in
                guard let self else { return }
                action(self.store, snapped)
            }
        )
    }

    private func stepperRow(
        _ cell: UICollectionViewListCell,
        _ content: inout UIListContentConfiguration,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String,
        action: @escaping (SettingsStore, Double) -> Void
    ) {
        content.text = title
        content.secondaryText = valueText
        cell.contentConfiguration = content
        let stepper = UIStepper()
        stepper.minimumValue = range.lowerBound
        stepper.maximumValue = range.upperBound
        stepper.stepValue = step
        stepper.value = value
        stepper.addAction(UIAction { [weak self] act in
            guard let self, let s = act.sender as? UIStepper else { return }
            action(self.store, s.value)
        }, for: .valueChanged)
        cell.accessories = [.customView(configuration: .init(customView: stepper, placement: .trailing()))]
    }

    private func themeButton(selected: Settings.ThemePreference) -> UIButton {
        let options: [(String, Settings.ThemePreference)] = [("System", .system), ("Light", .light), ("Dark", .dark)]
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = Theme.secondaryText
        let button = UIButton(configuration: configuration)
        button.menu = UIMenu(children: options.map { title, preference in
            UIAction(title: title, state: preference == selected ? .on : .off) { [weak self] _ in
                self?.store.update { $0.theme = preference }
            }
        })
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
        return button
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func presentQualityPicker() {
        let qualities = ["auto", "source", "720p60", "720p", "480p", "360p", "160p", "audio_only"]
        let alert = UIAlertController(title: "Default Quality", message: nil, preferredStyle: .actionSheet)
        for quality in qualities {
            alert.addAction(UIAlertAction(title: quality.capitalized, style: .default) { [weak self] _ in
                self?.store.update { $0.defaultQuality = quality }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/guitaripod/embr") else { return }
        UIApplication.shared.open(url)
    }

    private func performAccountAction() {
        switch authState {
        case .authenticated:
            confirmLogout()
        case .anonymous:
            login()
        }
    }

    private func confirmLogout() {
        let alert = UIAlertController(title: "Log Out?", message: "You'll return to browsing as a guest.", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { await self.auth.logout() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func login() {
        guard let anchor = view.window else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.auth.login(presentationAnchor: anchor)
            } catch {
                AppLogger.shared.warn("login failed: \(error)", category: .auth)
            }
        }
    }
}

extension SettingsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .defaultQuality, .github, .accountAction:
            return true
        default:
            return false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer { collectionView.deselectItem(at: indexPath, animated: true) }
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .defaultQuality:
            presentQualityPicker()
        case .github:
            openGitHub()
        case .accountAction:
            performAccountAction()
        default:
            break
        }
    }
}

private struct SliderRowConfiguration: UIContentConfiguration {
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var commit: (Double) -> Void

    func makeContentView() -> UIView & UIContentView {
        SliderRowView(self)
    }

    func updated(for state: UIConfigurationState) -> SliderRowConfiguration { self }
}

@MainActor
private final class SliderRowView: UIView, UIContentView {
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var current: SliderRowConfiguration

    var configuration: UIContentConfiguration {
        get { current }
        set {
            guard let config = newValue as? SliderRowConfiguration else { return }
            current = config
            apply(config)
        }
    }

    init(_ configuration: SliderRowConfiguration) {
        self.current = configuration
        super.init(frame: .zero)
        preservesSuperviewLayoutMargins = true
        build()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText

        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.secondaryText
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderCommitted), for: [.touchUpInside, .touchUpOutside])

        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.spacing = 8

        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func apply(_ config: SliderRowConfiguration) {
        titleLabel.text = config.title
        slider.minimumValue = Float(config.range.lowerBound)
        slider.maximumValue = Float(config.range.upperBound)
        slider.value = Float(config.value)
        valueLabel.text = config.format(config.value)
    }

    private func snappedValue() -> Double {
        let raw = Double(slider.value)
        let stepped = (raw / current.step).rounded() * current.step
        return min(max(stepped, current.range.lowerBound), current.range.upperBound)
    }

    @objc private func sliderChanged() {
        valueLabel.text = current.format(snappedValue())
    }

    @objc private func sliderCommitted() {
        current.commit(snappedValue())
    }
}
