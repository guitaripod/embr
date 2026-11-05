import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore
import MidgarPortal
import MidgarUI

/// The Settings tab: the Twitch account, Founding Supporter, how chat looks beside the video, previews, appearance,
/// the tip jar, Midgar's other apps and the legal pages.
final class TVSettingsViewController: UITableViewController {
    private enum Row: Hashable {
        case account
        case supporter
        case accent
        case chatVisible
        case chatPlacement
        case chatTextSize
        case timestamps
        case animatedEmotes
        case emotes(EmoteProvider)
        case filter
        case blocked
        case previews
        case theme
        case tip(String)
        case moreApps
        case terms
        case privacy
        case support
        case version
    }

    private struct Section {
        let title: String?
        let footer: String?
        let rows: [Row]
    }

    private var sections: [Section] = []
    private var user: AuthenticatedUser?
    private var blockedCount = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(style: .grouped)
        title = String(localized: "Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.remembersLastFocusedIndexPath = true
        AppContainer.shared.auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        SupporterStore.shared.changes
            .merge(with: TipJarStore.shared.changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rebuild() }
            .store(in: &cancellables)
        SettingsStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        TipJarStore.shared.loadProducts()
        SupporterStore.shared.loadProduct()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    private func refresh() {
        Task { [weak self] in
            let user = await AppContainer.shared.auth.currentUser()
            let blocked = await DatabaseManager.shared.blockedUsers().count
            self?.user = user
            self?.blockedCount = blocked
            self?.rebuild()
        }
    }

    private func rebuild() {
        let supporter = SupporterStore.shared.isSupporter
        let chatRows: [Row] = [.chatVisible, .chatPlacement, .chatTextSize, .timestamps, .animatedEmotes]
            + [.emotes(.sevenTV), .emotes(.betterTTV), .emotes(.frankerFaceZ)]
        let tipRows = TipJarStore.shared.products.map { Row.tip($0.id) }
        sections = [
            Section(title: String(localized: "Twitch Account"), footer: nil, rows: [.account]),
            Section(
                title: String(localized: "Founding Supporter"),
                footer: supporter
                    ? String(localized: "Thank you. Your accent color tints Embr on every device signed in to your Apple Account.")
                    : String(localized: "A one-time purchase that keeps Embr independent and gives it your colors and a badge in chat. Nothing about watching ever needs it."),
                rows: supporter ? [.supporter, .accent] : [.supporter]
            ),
            Section(title: String(localized: "Chat"), footer: nil, rows: chatRows),
            Section(
                title: String(localized: "Safety"),
                footer: String(localized: "Objectionable messages are hidden. Users you block are hidden from your chat and reported to the developer."),
                rows: [.filter, .blocked]
            ),
            Section(
                title: String(localized: "Browsing"),
                footer: String(localized: "A focused stream starts a short muted preview. Also off when Video Autoplay is off in the Apple TV's Accessibility settings."),
                rows: [.previews, .theme]
            ),
            Section(title: String(localized: "Tip Jar"), footer: String(localized: "Tips unlock nothing. They keep Embr going."), rows: tipRows),
            Section(title: nil, footer: nil, rows: [.moreApps]),
            Section(title: String(localized: "About"), footer: nil, rows: [.terms, .privacy, .support, .version]),
        ].filter { !$0.rows.isEmpty }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        let settings = SettingsStore.shared.current
        cell.accessoryType = .none
        switch sections[indexPath.section].rows[indexPath.row] {
        case .account:
            if let user {
                content.text = String(localized: "Signed in as \(user.login)")
                content.secondaryText = String(localized: "Sign Out")
            } else {
                content.text = String(localized: "Sign In with Twitch")
                content.secondaryText = nil
                cell.accessoryType = .disclosureIndicator
            }
            content.image = UIImage(systemName: "person.crop.circle")
        case .supporter:
            let store = SupporterStore.shared
            content.image = UIImage(systemName: "flame.fill")
            content.imageProperties.tintColor = Theme.accent
            if store.isSupporter {
                content.text = String(localized: "You're a Founding Supporter")
                content.secondaryText = badgeText(store.badge)
            } else {
                content.text = String(localized: "Become a Founding Supporter")
                content.secondaryText = store.product?.displayPrice
                cell.accessoryType = .disclosureIndicator
            }
        case .accent:
            content.text = String(localized: "Accent Color")
            content.secondaryText = SupporterStore.shared.accent.title
            cell.accessoryType = .disclosureIndicator
        case .chatVisible:
            toggle(&content, String(localized: "Show Chat Beside Video"), settings.tvChatVisibleEnabled)
        case .chatPlacement:
            content.text = String(localized: "Chat Side")
            content.secondaryText = settings.tvChatPlacementPreference == .left ? String(localized: "Left") : String(localized: "Right")
        case .chatTextSize:
            content.text = String(localized: "Chat Text Size")
            content.secondaryText = Self.title(for: settings.tvChatTextSizePreference)
        case .timestamps:
            toggle(&content, String(localized: "Timestamps"), settings.showTimestamps)
        case .animatedEmotes:
            toggle(&content, String(localized: "Animated Emotes"), settings.animateEmotes)
        case .emotes(let provider):
            toggle(&content, Self.title(for: provider), settings.thirdPartyEmotesEnabled(provider))
        case .filter:
            toggle(&content, String(localized: "Filter Objectionable Content"), settings.objectionableFilterEnabled)
        case .blocked:
            content.text = String(localized: "Blocked Users")
            content.secondaryText = blockedCount.formatted()
            cell.accessoryType = .disclosureIndicator
        case .previews:
            toggle(&content, String(localized: "Live Previews"), settings.livePreviewsEnabled)
        case .theme:
            content.text = String(localized: "Appearance")
            content.secondaryText = Self.title(for: settings.theme)
        case .tip(let id):
            let product = TipJarStore.shared.product(id: id)
            content.text = product?.displayName
            content.secondaryText = product?.displayPrice
            content.image = UIImage(systemName: "heart.fill")
            content.imageProperties.tintColor = .systemPink
        case .moreApps:
            content.text = String(localized: "More Apps from Midgar")
            content.image = UIImage(systemName: "square.grid.2x2")
            cell.accessoryType = .disclosureIndicator
        case .terms:
            content.text = LegalText.termsTitle
            cell.accessoryType = .disclosureIndicator
        case .privacy:
            content.text = LegalText.privacyTitle
            cell.accessoryType = .disclosureIndicator
        case .support:
            content.text = String(localized: "Support")
            content.secondaryText = LegalText.supportEmail
        case .version:
            content.text = String(localized: "Version")
            content.secondaryText = MidgarVersionInfo().display
        }
        cell.contentConfiguration = content
        return cell
    }

    private func toggle(_ content: inout UIListContentConfiguration, _ title: String, _ isOn: Bool) {
        content.text = title
        content.secondaryText = isOn ? String(localized: "On") : String(localized: "Off")
    }

    private func badgeText(_ state: SupporterStore.BadgeState) -> String? {
        switch state {
        case .none, .claiming: nil
        case .needsSignIn: String(localized: "Sign in to show your badge")
        case .shown(let login): String(localized: "Badge on \(login)")
        case .failed: String(localized: "Badge not shown yet")
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let store = SettingsStore.shared
        switch sections[indexPath.section].rows[indexPath.row] {
        case .account:
            if user != nil {
                confirmSignOut()
            } else {
                TVRouter.signIn(from: self)
            }
        case .supporter:
            navigationController?.pushViewController(TVSupporterViewController(), animated: true)
        case .accent:
            pickOption(
                title: String(localized: "Accent Color"),
                options: SupporterAccent.allCases,
                selected: SupporterStore.shared.accent,
                label: \.title
            ) { SupporterStore.shared.setAccent($0) }
        case .chatVisible:
            store.update { $0.tvChatVisible = !$0.tvChatVisibleEnabled }
        case .chatPlacement:
            store.update { $0.tvChatPlacement = $0.tvChatPlacementPreference == .left ? .right : .left }
        case .chatTextSize:
            pickOption(
                title: String(localized: "Chat Text Size"),
                options: Settings.ChatTextSize.allCases,
                selected: store.current.tvChatTextSizePreference,
                label: { Self.title(for: $0) }
            ) { size in store.update { $0.tvChatTextSize = size } }
        case .timestamps:
            store.update { $0.showTimestamps.toggle() }
        case .animatedEmotes:
            store.update { $0.animateEmotes.toggle() }
        case .emotes(let provider):
            store.update { $0.showThirdPartyEmotes[provider] = !$0.thirdPartyEmotesEnabled(provider) }
        case .filter:
            store.update { $0.filterObjectionableContent = !$0.objectionableFilterEnabled }
        case .blocked:
            navigationController?.pushViewController(TVBlockedUsersViewController(), animated: true)
        case .previews:
            store.update { $0.livePreviews = !$0.livePreviewsEnabled }
        case .theme:
            pickOption(
                title: String(localized: "Appearance"),
                options: Settings.ThemePreference.allCases,
                selected: store.current.theme,
                label: { Self.title(for: $0) }
            ) { theme in store.update { $0.theme = theme } }
        case .tip(let id):
            guard let product = TipJarStore.shared.product(id: id) else { return }
            Task { [weak self] in
                let outcome = await TipJarStore.shared.purchase(product, in: self?.view.window?.windowScene)
                if outcome == .thanked {
                    self?.thank()
                }
            }
        case .moreApps:
            _ = Midgar.present(from: self, config: EmbrMidgar.shared.portalConfig)
        case .terms:
            navigationController?.pushViewController(TVTextViewController(title: LegalText.termsTitle, text: LegalText.terms), animated: true)
        case .privacy:
            navigationController?.pushViewController(TVTextViewController(title: LegalText.privacyTitle, text: LegalText.privacy), animated: true)
        case .support, .version:
            break
        }
    }

    private func pickOption<Option: Equatable>(
        title: String,
        options: [Option],
        selected: Option,
        label: @escaping (Option) -> String,
        choose: @escaping (Option) -> Void
    ) {
        let picker = TVOptionsViewController(title: title, options: options.map(label), selected: options.firstIndex(of: selected)) { index in
            choose(options[index])
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: String(localized: "Sign out of Twitch?"),
            message: String(localized: "Your favorites stay. Following and chatting as you stop until you sign in again."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Sign Out"), style: .destructive) { [weak self] _ in
            Task {
                await AppContainer.shared.auth.logout()
                await TVLiveDirectory.shared.refresh()
                self?.refresh()
            }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func thank() {
        let alert = UIAlertController(title: String(localized: "Thank you!"), message: String(localized: "Your tip keeps Embr going."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "You're Welcome"), style: .default))
        present(alert, animated: true)
    }

    private static func title(for size: Settings.ChatTextSize) -> String {
        switch size {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }

    private static func title(for theme: Settings.ThemePreference) -> String {
        switch theme {
        case .system: String(localized: "Automatic")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    private static func title(for provider: EmoteProvider) -> String {
        switch provider {
        case .sevenTV: String(localized: "7TV Emotes")
        case .betterTTV: String(localized: "BetterTTV Emotes")
        case .frankerFaceZ: String(localized: "FrankerFaceZ Emotes")
        default: String(describing: provider)
        }
    }
}

/// A list of choices with a check on the current one; picking returns to the previous screen.
final class TVOptionsViewController: UITableViewController {
    private let options: [String]
    private var selected: Int?
    private let choose: (Int) -> Void

    init(title: String, options: [String], selected: Int?, choose: @escaping (Int) -> Void) {
        self.options = options
        self.selected = selected
        self.choose = choose
        super.init(style: .grouped)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = options[indexPath.row]
        cell.contentConfiguration = content
        cell.accessoryType = indexPath.row == selected ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selected = indexPath.row
        choose(indexPath.row)
        navigationController?.popViewController(animated: true)
    }

    override func indexPathForPreferredFocusedView(in tableView: UITableView) -> IndexPath? {
        selected.map { IndexPath(row: $0, section: 0) }
    }
}

/// A long text the remote scrolls: the terms and the privacy policy.
final class TVTextViewController: UIViewController {
    private let text: String

    init(title: String, text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let textView = UITextView()
        textView.text = text
        textView.font = TVFont.body
        textView.textColor = Theme.primaryText
        textView.backgroundColor = .clear
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            textView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textView.widthAnchor.constraint(equalToConstant: 1200),
        ])
    }
}

/// The users blocked on this Apple TV; selecting one unblocks it.
final class TVBlockedUsersViewController: UITableViewController {
    private var users: [BlockedUserRecord] = []

    init() {
        super.init(style: .grouped)
        title = String(localized: "Blocked Users")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            self?.users = await DatabaseManager.shared.blockedUsers()
            self?.tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(users.count, 1)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        users.isEmpty ? nil : String(localized: "Select a user to unblock them.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = users.isEmpty ? String(localized: "Nobody is blocked") : users[indexPath.row].login
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < users.count else { return }
        let user = users[indexPath.row]
        Task { [weak self] in
            await DatabaseManager.shared.removeBlockedUser(userID: user.userID)
            self?.users = await DatabaseManager.shared.blockedUsers()
            self?.tableView.reloadData()
        }
    }
}
