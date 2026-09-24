import UIKit
import Combine
import AuthenticationServices
import SafariServices
import EmbrCore
import MidgarKit

@MainActor
final class SettingsViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case general
        case chat
        case safety
        case video
        case account
        case support
        case about

        var title: String {
            switch self {
            case .general: return String(localized: "General")
            case .chat: return String(localized: "Chat")
            case .safety: return String(localized: "Safety & Moderation")
            case .video: return String(localized: "Video")
            case .account: return String(localized: "Account")
            case .support: return String(localized: "Support Embr")
            case .about: return String(localized: "About")
            }
        }
    }

    private enum Row: Hashable {
        case theme
        case openLinksInApp
        case haptics

        case showTimestamps
        case compactChat
        case messageScale
        case fontSizeDelta
        case highlightMentions
        case recentMessagesBackfill
        case animateEmotes
        case thirdPartyEmotes(EmoteProvider)

        case filterObjectionableContent
        case mutedKeywords
        case blockedUsers

        case autoplay
        case backgroundAudio
        case chatDelaySeconds
        case autoSyncChatDelay
        case keepScreenAwake

        case accountStatus
        case accountAction

        case rateApp
        case shareApp
        case tip(String)
        case tipsStatus

        case version
        case github
        case moreApps
        case termsOfUse
        case privacyPolicy
        case contactSupport
        case shareLogs
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
        title = String(localized: "Settings")
        tabBarItem = UITabBarItem(
            title: String(localized: "Settings"),
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
        config.footerMode = .supplementary
        let layout = StreamListLayout.readableList(using: config)
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
        let footerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionFooter
        ) { footer, _, indexPath in
            guard let section = Section(rawValue: indexPath.section), let text = Self.footerText(for: section) else {
                footer.contentConfiguration = nil
                return
            }
            var content = UIListContentConfiguration.footer()
            content.text = text
            footer.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            let registration = kind == UICollectionView.elementKindSectionFooter ? footerRegistration : headerRegistration
            return collectionView.dequeueConfiguredReusableSupplementary(using: registration, for: indexPath)
        }
    }

    private static func footerText(for section: Section) -> String? {
        switch section {
        case .general: return String(localized: "Appearance, link handling, and haptic feedback across the app.")
        case .chat: return String(localized: "Readability, message size, and which emote sets load in chat.")
        case .safety: return String(localized: "Hide objectionable messages, mute specific words, and manage users you've blocked. Blocked and reported users are hidden instantly and sent to the developer for review.")
        case .video: return String(localized: "Stream quality, autoplay, and how chat stays in sync with the video.")
        case .account: return String(localized: "Sign in with Twitch to follow channels and join chat.")
        case .support:
            return TipJarStore.shared.hasTipped
                ? String(localized: "Thank you for supporting Embr. Tips unlock nothing — every feature is free for everyone.")
                : String(localized: "Embr is free and independent. Tips unlock nothing; they just help keep the app going.")
        case .about: return String(localized: "Embr is an independent, open-source Twitch client. Not affiliated with Twitch.")
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

        TipJarStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadSupportSection()
            }
            .store(in: &cancellables)
        TipJarStore.shared.loadProducts()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections(Section.allCases)
        snapshot.appendItems([.theme, .openLinksInApp, .haptics], toSection: .general)
        snapshot.appendItems(
            [.showTimestamps, .compactChat, .messageScale, .fontSizeDelta,
             .highlightMentions, .recentMessagesBackfill, .animateEmotes]
            + thirdPartyProviders.map(Row.thirdPartyEmotes),
            toSection: .chat
        )
        snapshot.appendItems([.filterObjectionableContent, .mutedKeywords, .blockedUsers], toSection: .safety)
        snapshot.appendItems(
            [.autoplay, .backgroundAudio, .chatDelaySeconds, .autoSyncChatDelay, .keepScreenAwake],
            toSection: .video
        )
        snapshot.appendItems([.accountStatus, .accountAction], toSection: .account)
        snapshot.appendItems(supportRows(), toSection: .support)
        snapshot.appendItems([.version, .github, .moreApps, .termsOfUse, .privacyPolicy, .contactSupport, .shareLogs], toSection: .about)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    /// Rate and Share always; then one row per tip once the App Store has answered, or a
    /// single status row while it is loading or unreachable.
    private func supportRows() -> [Row] {
        var rows: [Row] = [.rateApp, .shareApp]
        #if DEBUG
        if ScreenshotHarness.previewTips {
            return rows + TipJarStore.productIDs.map(Row.tip)
        }
        #endif
        let store = TipJarStore.shared
        if store.state == .loaded {
            rows += store.products.map { Row.tip($0.id) }
        } else {
            rows.append(.tipsStatus)
        }
        return rows
    }

    private func reloadSupportSection() {
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(snapshot.itemIdentifiers(inSection: .support))
        snapshot.appendItems(supportRows(), toSection: .support)
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .support))
        snapshot.reloadSections([.support])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    #if DEBUG
    func showSupportForScreenshot() {
        applySnapshot()
        guard let section = dataSource.snapshot().indexOfSection(.support) else { return }
        collectionView.scrollToItem(at: IndexPath(item: 0, section: section), at: .centeredVertically, animated: false)
    }
    #endif

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
        let tile = Self.iconImage(for: row)
        content.image = tile
        content.imageProperties.maximumSize = CGSize(width: 29, height: 29)
        content.imageProperties.reservedLayoutSize = CGSize(width: 29, height: 29)
        content.imageToTextPadding = 12

        switch row {
        case .theme:
            content.text = String(localized: "Theme")
            cell.contentConfiguration = content
            cell.accessories = [.customView(configuration: .init(customView: themeButton(selected: settings.theme), placement: .trailing()))]

        case .openLinksInApp:
            switchRow(cell, &content, title: String(localized: "Open Links In App"), isOn: settings.openLinksInApp) { store, on in
                store.update { $0.openLinksInApp = on }
            }
        case .haptics:
            switchRow(cell, &content, title: String(localized: "Haptics"), isOn: settings.hapticsEnabled) { store, on in
                store.update { $0.hapticsEnabled = on }
            }

        case .showTimestamps:
            switchRow(cell, &content, title: String(localized: "Show Timestamps"), isOn: settings.showTimestamps) { store, on in
                store.update { $0.showTimestamps = on }
            }
        case .compactChat:
            switchRow(cell, &content, title: String(localized: "Compact Chat"), isOn: settings.compactChat) { store, on in
                store.update { $0.compactChat = on }
            }
        case .messageScale:
            sliderRow(
                cell, icon: tile,
                title: String(localized: "Message Scale"),
                value: settings.messageScale, range: 0.75...1.5, step: 0.05,
                format: { String(format: "%.2fx", $0) }
            ) { store, value in
                store.update { $0.messageScale = value }
            }
        case .fontSizeDelta:
            stepperRow(
                cell, icon: tile,
                title: String(localized: "Font Size Adjustment"),
                value: Double(settings.fontSizeDelta), range: -4...8, step: 1,
                format: { $0 >= 0 ? "+\(Int($0))" : "\(Int($0))" }
            ) { store, value in
                store.update { $0.fontSizeDelta = Int(value.rounded()) }
            }
        case .highlightMentions:
            switchRow(cell, &content, title: String(localized: "Highlight Mentions"), isOn: settings.highlightMentions) { store, on in
                store.update { $0.highlightMentions = on }
            }
        case .recentMessagesBackfill:
            switchRow(cell, &content, title: String(localized: "Backfill Recent Messages"), isOn: settings.recentMessagesBackfill) { store, on in
                store.update { $0.recentMessagesBackfill = on }
            }
        case .animateEmotes:
            switchRow(cell, &content, title: String(localized: "Animate Emotes"), isOn: settings.animateEmotes) { store, on in
                store.update { $0.animateEmotes = on }
            }
        case let .thirdPartyEmotes(provider):
            switchRow(cell, &content, title: String(localized: "\(provider.displayName) Emotes"), isOn: settings.thirdPartyEmotesEnabled(provider)) { store, on in
                store.update { $0.showThirdPartyEmotes[provider] = on }
            }
        case .filterObjectionableContent:
            switchRow(cell, &content, title: String(localized: "Filter Objectionable Content"), isOn: settings.objectionableFilterEnabled) { store, on in
                store.update { $0.filterObjectionableContent = on }
            }
        case .mutedKeywords:
            content.text = String(localized: "Muted Keywords")
            let count = settings.mutedKeywordList.count
            content.secondaryText = count == 0 ? String(localized: "None") : (count == 1 ? String(localized: "1 word") : String(localized: "\(count) words"))
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .blockedUsers:
            content.text = String(localized: "Blocked Users")
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]

        case .autoplay:
            switchRow(cell, &content, title: String(localized: "Autoplay"), isOn: settings.autoplay) { store, on in
                store.update { $0.autoplay = on }
            }
        case .backgroundAudio:
            switchRow(cell, &content, title: String(localized: "Background Audio"), isOn: settings.backgroundAudio ?? true) { store, on in
                store.update { $0.backgroundAudio = on }
            }
        case .chatDelaySeconds:
            sliderRow(
                cell, icon: tile,
                title: String(localized: "Chat Delay"),
                value: settings.chatDelaySeconds, range: 0...10, step: 0.5,
                format: { String(format: "%.1fs", $0) }
            ) { store, value in
                store.update { $0.chatDelaySeconds = value }
            }
        case .autoSyncChatDelay:
            switchRow(cell, &content, title: String(localized: "Auto-Sync Chat Delay"), isOn: settings.autoSyncChatDelay) { store, on in
                store.update { $0.autoSyncChatDelay = on }
            }
        case .keepScreenAwake:
            switchRow(cell, &content, title: String(localized: "Keep Screen Awake"), isOn: settings.keepScreenAwake) { store, on in
                store.update { $0.keepScreenAwake = on }
            }

        case .accountStatus:
            switch authState {
            case let .authenticated(user):
                content.text = user.displayName
                content.secondaryText = "@\(user.login)"
            case .anonymous:
                content.text = String(localized: "Not Logged In")
                content.secondaryText = String(localized: "Browsing anonymously")
            }
            cell.contentConfiguration = content
            cell.accessories = []
        case .accountAction:
            switch authState {
            case .authenticated:
                content.text = String(localized: "Log Out")
                content.textProperties.color = .systemRed
            case .anonymous:
                content.text = String(localized: "Log In with Twitch")
                content.textProperties.color = Theme.accent
            }
            cell.contentConfiguration = content
            cell.accessories = []

        case .rateApp:
            content.text = String(localized: "Rate Embr")
            content.textProperties.color = Theme.accent
            cell.contentConfiguration = content
            cell.accessories = []
        case .shareApp:
            content.text = String(localized: "Share Embr")
            content.textProperties.color = Theme.accent
            cell.contentConfiguration = content
            cell.accessories = []
        case let .tip(id):
            let (name, price) = tipLabels(for: id)
            content.text = name
            cell.contentConfiguration = content
            cell.accessories = price.map { [.label(text: $0, options: .init(tintColor: Theme.accent, font: .preferredFont(forTextStyle: .body)))] } ?? []
        case .tipsStatus:
            switch TipJarStore.shared.state {
            case .unavailable:
                content.text = String(localized: "Tips Unavailable")
                content.secondaryText = String(localized: "Couldn't reach the App Store. Tap to try again.")
                cell.accessories = []
            case .idle, .loading, .loaded:
                content.text = String(localized: "Loading Tips…")
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessories = [.customView(configuration: .init(customView: spinner, placement: .trailing()))]
            }
            content.textProperties.color = Theme.secondaryText
            cell.contentConfiguration = content

        case .version:
            content.text = String(localized: "Version")
            content.secondaryText = Self.versionString
            cell.contentConfiguration = content
            cell.accessories = []
        case .github:
            content.text = String(localized: "GitHub")
            content.textProperties.color = Theme.link
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .moreApps:
            content.text = String(localized: "More Apps")
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .termsOfUse:
            content.text = String(localized: "Terms of Use")
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .privacyPolicy:
            content.text = String(localized: "Privacy Policy")
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        case .contactSupport:
            content.text = String(localized: "Contact Support")
            content.textProperties.color = Theme.accent
            cell.contentConfiguration = content
            cell.accessories = []
        case .shareLogs:
            content.text = String(localized: "Share Diagnostic Logs")
            content.textProperties.color = Theme.accent
            cell.contentConfiguration = content
            cell.accessories = []
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
        toggle.accessibilityLabel = title
        toggle.addAction(UIAction { [weak self] act in
            guard let self, let sw = act.sender as? UISwitch else { return }
            action(self.store, sw.isOn)
        }, for: .valueChanged)
        cell.accessories = [.customView(configuration: .init(customView: toggle, placement: .trailing()))]
    }

    private func sliderRow(
        _ cell: UICollectionViewListCell,
        icon: UIImage,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        action: @escaping (SettingsStore, Double) -> Void
    ) {
        cell.accessories = []
        cell.contentConfiguration = SliderRowConfiguration(
            icon: icon,
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
        icon: UIImage,
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        action: @escaping (SettingsStore, Double) -> Void
    ) {
        cell.accessories = []
        cell.contentConfiguration = StepperRowConfiguration(
            icon: icon,
            title: title,
            value: value,
            range: range,
            step: step,
            format: format,
            commit: { [weak self] value in
                guard let self else { return }
                action(self.store, value)
            }
        )
    }

    private func themeButton(selected: Settings.ThemePreference) -> UIButton {
        let options: [(String, Settings.ThemePreference)] = [(String(localized: "System"), .system), (String(localized: "Light"), .light), (String(localized: "Dark"), .dark)]
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

    private static func iconImage(for row: Row) -> UIImage {
        let spec: (String, UIColor)
        switch row {
        case .theme: spec = ("circle.lefthalf.filled", .systemIndigo)
        case .openLinksInApp: spec = ("safari.fill", .systemBlue)
        case .haptics: spec = ("hand.tap.fill", .systemPink)
        case .showTimestamps: spec = ("clock.fill", .systemGray)
        case .compactChat: spec = ("rectangle.compress.vertical", .systemTeal)
        case .messageScale: spec = ("textformat.size", .systemIndigo)
        case .fontSizeDelta: spec = ("character.cursor.ibeam", .systemIndigo)
        case .highlightMentions: spec = ("at", Theme.accent)
        case .recentMessagesBackfill: spec = ("arrow.counterclockwise", .systemTeal)
        case .animateEmotes: spec = ("face.smiling.fill", .systemOrange)
        case .thirdPartyEmotes: spec = ("puzzlepiece.extension.fill", .systemGreen)
        case .filterObjectionableContent: spec = ("eye.slash.fill", .systemRed)
        case .mutedKeywords: spec = ("character.bubble.fill", .systemOrange)
        case .blockedUsers: spec = ("hand.raised.fill", .systemRed)
        case .autoplay: spec = ("play.fill", .systemGreen)
        case .backgroundAudio: spec = ("speaker.wave.2.circle.fill", .systemPurple)
        case .chatDelaySeconds: spec = ("timer", .systemOrange)
        case .autoSyncChatDelay: spec = ("arrow.triangle.2.circlepath", .systemTeal)
        case .keepScreenAwake: spec = ("sun.max.fill", .systemYellow)
        case .accountStatus: spec = ("person.crop.circle.fill", Theme.accent)
        case .accountAction: spec = ("rectangle.portrait.and.arrow.right", .systemRed)
        case .rateApp: spec = ("star.fill", .systemYellow)
        case .shareApp: spec = ("square.and.arrow.up.fill", .systemGreen)
        case let .tip(id): spec = (Self.tipSymbol(for: id), .systemOrange)
        case .tipsStatus: spec = ("flame.fill", .systemOrange)
        case .version: spec = ("info.circle.fill", .systemGray)
        case .github: spec = ("chevron.left.forwardslash.chevron.right", .label)
        case .moreApps: spec = ("square.grid.2x2.fill", Theme.accent)
        case .termsOfUse: spec = ("doc.text.fill", .systemGray)
        case .privacyPolicy: spec = ("hand.raised.fill", .systemBlue)
        case .contactSupport: spec = ("envelope.fill", Theme.accent)
        case .shareLogs: spec = ("square.and.arrow.up", .systemBlue)
        }
        return iconTile(spec.0, spec.1)
    }

    private static func iconTile(_ symbol: String, _ color: UIColor) -> UIImage {
        let size = CGSize(width: 29, height: 29)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 7).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            guard let symbolImage = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let s = symbolImage.size
            symbolImage.draw(in: CGRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2, width: s.width, height: s.height))
        }
    }

    private static func tipSymbol(for id: String) -> String {
        switch TipJarStore.productIDs.firstIndex(of: id) {
        case 0: return "flame"
        case 1: return "flame.fill"
        default: return "flame.circle.fill"
        }
    }

    /// The App Store's own localized name and price for a tip. The DEBUG screenshot preview
    /// substitutes fixed US-priced rows because a simulator launched by `simctl` has no
    /// StoreKit configuration to answer from.
    private func tipLabels(for id: String) -> (String, String?) {
        if let product = TipJarStore.shared.product(id: id) {
            return (product.displayName, product.displayPrice)
        }
        #if DEBUG
        if ScreenshotHarness.previewTips, let index = TipJarStore.productIDs.firstIndex(of: id) {
            let previews = [
                (String(localized: "Small Tip"), "$1.99"),
                (String(localized: "Medium Tip"), "$4.99"),
                (String(localized: "Large Tip"), "$9.99"),
            ]
            return previews[index]
        }
        #endif
        return (String(localized: "Tip"), nil)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/guitaripod/embr") else { return }
        if store.current.openLinksInApp {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = Theme.accent
            present(safari, animated: true)
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func shareLogs(from sourceView: UIView?) {
        let urls = AppLogger.shared.logFileURLs()
        guard !urls.isEmpty else {
            let alert = UIAlertController(title: String(localized: "No Logs Yet"), message: String(localized: "Diagnostic logs will appear here after you use the app."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(activity, animated: true)
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
        let alert = UIAlertController(title: String(localized: "Log Out?"), message: String(localized: "You'll return to browsing as a guest."), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "Log Out"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { await self.auth.logout() }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
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
        case .github, .moreApps, .accountAction, .mutedKeywords, .blockedUsers, .termsOfUse, .privacyPolicy, .contactSupport, .shareLogs,
             .rateApp, .shareApp, .tip:
            return true
        case .tipsStatus:
            return TipJarStore.shared.state == .unavailable
        default:
            return false
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        defer { collectionView.deselectItem(at: indexPath, animated: true) }
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .github:
            openGitHub()
        case .moreApps:
            Midgar.present(from: self, config: MidgarConfig(accent: Theme.accent, title: String(localized: "More Apps")))
        case .accountAction:
            performAccountAction()
        case .mutedKeywords:
            navigationController?.pushViewController(MutedKeywordsViewController(), animated: true)
        case .blockedUsers:
            navigationController?.pushViewController(BlockedUsersViewController(), animated: true)
        case .termsOfUse:
            navigationController?.pushViewController(
                LegalViewController(title: LegalText.termsTitle, body: LegalText.terms), animated: true
            )
        case .privacyPolicy:
            navigationController?.pushViewController(
                LegalViewController(title: LegalText.privacyTitle, body: LegalText.privacy), animated: true
            )
        case .contactSupport:
            openSupportEmail()
        case .shareLogs:
            shareLogs(from: collectionView.cellForItem(at: indexPath))
        case .rateApp:
            UIApplication.shared.open(AppStoreLinks.writeReview)
        case .shareApp:
            shareApp(from: collectionView.cellForItem(at: indexPath))
        case let .tip(id):
            leaveTip(id)
        case .tipsStatus:
            TipJarStore.shared.retry()
        default:
            break
        }
    }

    private func shareApp(from sourceView: UIView?) {
        let activity = UIActivityViewController(activityItems: AppStoreLinks.shareItems, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(activity, animated: true)
    }

    private func leaveTip(_ id: String) {
        guard let product = TipJarStore.shared.product(id: id) else { return }
        collectionView.isUserInteractionEnabled = false
        Task { [weak self] in
            let outcome = await TipJarStore.shared.purchase(product, in: self?.view.window?.windowScene)
            guard let self else { return }
            self.collectionView.isUserInteractionEnabled = true
            self.presentTipOutcome(outcome)
        }
    }

    private func presentTipOutcome(_ outcome: TipJarStore.Outcome) {
        let title: String
        let message: String
        switch outcome {
        case .thanked:
            Haptics.notify(.success)
            title = String(localized: "Thank You!")
            message = String(localized: "Your tip keeps Embr going.")
        case .pending:
            title = String(localized: "Waiting for Approval")
            message = String(localized: "Your tip will go through once it's approved.")
        case let .failed(reason):
            Haptics.notify(.error)
            title = String(localized: "Couldn't Complete the Tip")
            message = reason
        case .cancelled:
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func openSupportEmail() {
        let subject = String(localized: "Embr Support (\(Self.versionString))")
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = LegalText.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        guard let url = components.url else {
            presentSupportFallback()
            return
        }
        UIApplication.shared.open(url) { [weak self] success in
            guard !success else { return }
            self?.presentSupportFallback()
        }
    }

    private func presentSupportFallback() {
        UIPasteboard.general.string = LegalText.supportEmail
        let alert = UIAlertController(
            title: String(localized: "Contact Support"),
            message: String(localized: "Email \(LegalText.supportEmail)\n\nThe address has been copied to your clipboard."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

private struct SliderRowConfiguration: UIContentConfiguration {
    var icon: UIImage?
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
    private let iconView = UIImageView()
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
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)

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
        slider.addTarget(self, action: #selector(sliderCommitted), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [header, slider])
        textStack.axis = .vertical
        textStack.spacing = 6

        let row = UIStackView(arrangedSubviews: [iconView, textStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 29),
            iconView.heightAnchor.constraint(equalToConstant: 29),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func apply(_ config: SliderRowConfiguration) {
        iconView.image = config.icon
        titleLabel.text = config.title
        slider.minimumValue = Float(config.range.lowerBound)
        slider.maximumValue = Float(config.range.upperBound)
        slider.value = Float(config.value)
        slider.accessibilityLabel = config.title
        slider.accessibilityValue = config.format(config.value)
        valueLabel.text = config.format(config.value)
    }

    private func snappedValue() -> Double {
        let raw = Double(slider.value)
        let stepped = (raw / current.step).rounded() * current.step
        return min(max(stepped, current.range.lowerBound), current.range.upperBound)
    }

    @objc private func sliderChanged() {
        let formatted = current.format(snappedValue())
        valueLabel.text = formatted
        slider.accessibilityValue = formatted
    }

    @objc private func sliderCommitted() {
        current.commit(snappedValue())
    }
}

private struct StepperRowConfiguration: UIContentConfiguration {
    var icon: UIImage?
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var commit: (Double) -> Void

    func makeContentView() -> UIView & UIContentView { StepperRowView(self) }
    func updated(for state: UIConfigurationState) -> StepperRowConfiguration { self }
}

@MainActor
private final class StepperRowView: UIView, UIContentView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private var current: StepperRowConfiguration
    private var liveValue: Double

    var configuration: UIContentConfiguration {
        get { current }
        set {
            guard let config = newValue as? StepperRowConfiguration else { return }
            current = config
            liveValue = config.value
            apply(config)
        }
    }

    init(_ configuration: StepperRowConfiguration) {
        self.current = configuration
        self.liveValue = configuration.value
        super.init(frame: .zero)
        preservesSuperviewLayoutMargins = true
        build()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold))
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.primaryText
        valueLabel.textAlignment = .center
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureStepperButton(minusButton, symbol: "minus")
        configureStepperButton(plusButton, symbol: "plus")
        minusButton.addAction(UIAction { [weak self] _ in self?.step(by: -1) }, for: .touchUpInside)
        plusButton.addAction(UIAction { [weak self] _ in self?.step(by: 1) }, for: .touchUpInside)

        let control = UIStackView(arrangedSubviews: [minusButton, valueLabel, plusButton])
        control.axis = .horizontal
        control.alignment = .center
        control.spacing = 2
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.backgroundColor = Theme.surfaceElevated
        control.layer.cornerRadius = 9
        control.layer.cornerCurve = .continuous
        control.isLayoutMarginsRelativeArrangement = true
        control.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)

        let row = UIStackView(arrangedSubviews: [iconView, titleLabel, control])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 29),
            iconView.heightAnchor.constraint(equalToConstant: 29),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureStepperButton(_ button: UIButton, symbol: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.baseForegroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        button.configuration = config
    }

    private func apply(_ config: StepperRowConfiguration) {
        iconView.image = config.icon
        titleLabel.text = config.title
        valueLabel.text = config.format(liveValue)
        minusButton.accessibilityLabel = String(localized: "Decrease \(config.title)")
        plusButton.accessibilityLabel = String(localized: "Increase \(config.title)")
        valueLabel.isAccessibilityElement = true
        valueLabel.accessibilityLabel = config.title
        valueLabel.accessibilityValue = config.format(liveValue)
        updateButtonStates()
    }

    private func step(by direction: Double) {
        let next = min(max(liveValue + current.step * direction, current.range.lowerBound), current.range.upperBound)
        guard next != liveValue else { return }
        liveValue = next
        valueLabel.text = current.format(liveValue)
        valueLabel.accessibilityValue = current.format(liveValue)
        updateButtonStates()
        Haptics.selection()
        current.commit(liveValue)
    }

    private func updateButtonStates() {
        minusButton.isEnabled = liveValue > current.range.lowerBound
        plusButton.isEnabled = liveValue < current.range.upperBound
    }
}
