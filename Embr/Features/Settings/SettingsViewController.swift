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
            var content = UIListContentConfiguration.groupedHeader()
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
            let control = UISegmentedControl(items: ["System", "Light", "Dark"])
            control.selectedSegmentIndex = themeIndex(settings.theme)
            control.addAction(UIAction { [weak self] action in
                guard let segmented = action.sender as? UISegmentedControl else { return }
                let theme = Self.theme(forIndex: segmented.selectedSegmentIndex)
                self?.store.update { $0.theme = theme }
            }, for: .valueChanged)
            cell.accessories = [.customView(configuration: .init(customView: control, placement: .trailing()))]

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
                cell, &content,
                title: "Message Scale",
                value: settings.messageScale, range: 0.75...1.5, step: 0.05,
                valueText: String(format: "%.2fx", settings.messageScale)
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
                cell, &content,
                title: "Chat Delay",
                value: settings.chatDelaySeconds, range: 0...10, step: 0.5,
                valueText: String(format: "%.1fs", settings.chatDelaySeconds)
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
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        slider.minimumTrackTintColor = Theme.accent
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        slider.addAction(UIAction { [weak self] act in
            guard let self, let s = act.sender as? UISlider else { return }
            let snapped = (Double(s.value) / step).rounded() * step
            action(self.store, min(max(snapped, range.lowerBound), range.upperBound))
        }, for: .valueChanged)
        cell.accessories = [.customView(configuration: .init(customView: slider, placement: .trailing()))]
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

    private func themeIndex(_ theme: Settings.ThemePreference) -> Int {
        switch theme {
        case .system: return 0
        case .light: return 1
        case .dark: return 2
        }
    }

    private static func theme(forIndex index: Int) -> Settings.ThemePreference {
        switch index {
        case 1: return .light
        case 2: return .dark
        default: return .system
        }
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
            Task { await auth.logout() }
        case .anonymous:
            login()
        }
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
