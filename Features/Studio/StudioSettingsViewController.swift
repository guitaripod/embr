import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Opens Embr Studio on iPhone and iPad: for the signed-in streamer's channel or one they moderate, or the sample
/// stream.
@MainActor
enum StudioLauncher {
    static func openSample(from presenter: UIViewController) {
        let chat = ChatViewModel(room: AppContainer.shared.makeChatRoom(channel: StudioSample.channel, loggedIn: false, mode: .sample))
        let session = StudioSession(
            channel: StudioSample.channel,
            role: .broadcaster,
            features: StudioSample.features,
            userID: StudioSample.channel.id,
            isSample: true,
            chat: chat,
            api: SampleStudioAPI(),
            feed: SampleStudioFeed(),
            preferences: StudioSettingsStore.shared.current.effectiveAlerts,
            hasPro: { true }
        )
        present(StudioViewController(session: session, isAnonymous: true, userLogin: nil), from: presenter)
    }

    static func openOwn(from presenter: UIViewController) async {
        guard let user = await AppContainer.shared.auth.currentUser() else { return }
        let settings = StudioSettingsStore.shared.current
        let features = StudioFeature.granted(by: user.scopes)
        let channel: ChannelInfo
        let role: StudioRole
        if settings.role == .moderator, let id = settings.moderatedChannelID, let login = settings.moderatedChannelLogin {
            role = .moderator
            channel = ChannelInfo(id: id, broadcasterLogin: login, broadcasterName: settings.moderatedChannelName ?? login, gameID: "", gameName: "", title: "", language: "")
        } else {
            role = .broadcaster
            let info = try? await AppContainer.shared.api.channelInfo(broadcasterID: user.id)
            channel = info ?? ChannelInfo(id: user.id, broadcasterLogin: user.login, broadcasterName: user.displayName, gameID: "", gameName: "", title: "", language: "")
        }
        let chat = ChatViewModel(room: AppContainer.shared.makeChatRoom(channel: channel, loggedIn: true), currentUserLogin: user.login)
        let session = StudioSession(
            channel: channel,
            role: role,
            features: features,
            userID: user.id,
            isSample: false,
            chat: chat,
            api: StudioAPIClient.shared,
            feed: LiveStudioFeed(),
            preferences: settings.effectiveAlerts,
            hasPro: { StudioProStore.shared.hasPro }
        )
        present(StudioViewController(session: session, isAnonymous: false, userLogin: user.login), from: presenter)
    }

    private static func present(_ controller: StudioViewController, from presenter: UIViewController) {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        navigation.overrideUserInterfaceStyle = .dark
        navigation.navigationBar.tintColor = StudioPalette.emberLight
        presenter.present(navigation, animated: true)
    }

    /// The scopes to ask for: the chosen Studio features', plus Moderator Tools' when the viewer already has them, so a
    /// new sign-in never takes away what they had.
    static func scopes(for features: Set<StudioFeature>, keeping current: [String]) -> [String] {
        var scopes = StudioFeature.scopes(for: features)
        if TwitchScopes.moderatorTools.allSatisfy(current.contains) {
            scopes += TwitchScopes.moderatorTools.filter { !scopes.contains($0) }
        }
        return scopes
    }
}

/// Embr Studio's page in Settings on iPhone and iPad: open it or the sample stream, pick the channel and what Studio
/// may do, Studio Pro, quick messages, alerts and the screen.
@MainActor
final class StudioSettingsViewController: SettingsPageViewController {
    private let refresh = PassthroughSubject<Void, Never>()
    private var user: AuthenticatedUser?
    private var moderated: [ModeratedChannel] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        let refresh = refresh
        let changes = StudioSettingsStore.shared.changes.map { _ in () }
            .merge(with: StudioProStore.shared.changes, refresh)
            .eraseToAnyPublisher()
        super.init(title: String(localized: "Embr Studio", comment: "Settings page"), changes: changes) { page in
            (page as? StudioSettingsViewController)?.sections() ?? []
        }
        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        StudioProStore.shared.loadProducts()
        AuthService.shared.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
            .store(in: &cancellables)
    }

    private func load() {
        Task { [weak self] in
            let user = await AppContainer.shared.auth.currentUser()
            self?.user = user
            self?.refresh.send()
            guard let user, user.scopes.contains("user:read:moderated_channels") else { return }
            self?.moderated = ((try? await StudioAPIClient.shared.moderatedChannels(userID: user.id)) ?? []).filter { $0.id != user.id }
            self?.refresh.send()
        }
    }

    private func sections() -> [SettingsSection] {
        let settings = StudioSettingsStore.shared
        let pro = StudioProStore.shared
        var open: [SettingsItem] = []
        if user != nil {
            open.append(SettingsItem(id: "studio.open", title: String(localized: "Open Studio", comment: "Studio settings"), icon: SettingsIcon(symbol: "sparkles.tv.fill", color: StudioPalette.ember), kind: .action(role: .accent) { presenter, _ in
                Task { await StudioLauncher.openOwn(from: presenter) }
            }))
        } else {
            open.append(SettingsItem(id: "studio.login", title: String(localized: "Log In with Twitch for Studio", comment: "Studio settings"), icon: SettingsIcon(symbol: "person.crop.circle.badge.plus", color: .systemPurple), kind: .action(role: .accent) { [weak self] presenter, _ in
                self?.askTwitch(for: Set(StudioFeature.allCases), from: presenter)
            }))
        }
        open.append(SettingsItem(id: "studio.sample", title: String(localized: "Try a Sample Stream", comment: "Studio settings"), icon: SettingsIcon(symbol: "play.rectangle.on.rectangle.fill", color: .systemOrange), kind: .action(role: .normal) { presenter, _ in
            StudioLauncher.openSample(from: presenter)
        }))
        var result = [SettingsSection(id: "studio.open", footer: String(localized: "A screen for your own Twitch channel while you're live: your chat, the next ad break, and every follow, sub, raid and hype train. It works on Apple TV too.", comment: "Studio settings footer"), items: open)]

        if let user {
            let current = settings.current
            var choices = [SettingsChoice(title: String(localized: "My Channel", comment: "Studio channel"), isSelected: current.role == .broadcaster) {
                settings.update { $0.role = .broadcaster }
            }]
            for channel in moderated.prefix(20) {
                choices.append(SettingsChoice(title: channel.name, isSelected: current.role == .moderator && current.moderatedChannelID == channel.id) {
                    settings.update {
                        $0.role = .moderator
                        $0.moderatedChannelID = channel.id
                        $0.moderatedChannelLogin = channel.login
                        $0.moderatedChannelName = channel.name
                    }
                })
            }
            let channelValue = current.role == .moderator ? (current.moderatedChannelName ?? "") : String(localized: "My Channel", comment: "Studio channel")
            let granted = StudioFeature.granted(by: user.scopes)
            result.append(SettingsSection(id: "studio.channel", header: String(localized: "Your Channel", comment: "Studio settings header"), items: [
                SettingsItem(id: "studio.channel.pick", title: String(localized: "Channel", comment: "Studio settings"), kind: .menu(value: channelValue, choices: choices)),
                SettingsItem(id: "studio.permissions", title: String(localized: "Permissions", comment: "Studio settings"), kind: .link(value: String(localized: "\(granted.count) of \(StudioFeature.allCases.count)", comment: "Studio permissions count")) { [weak self] presenter in
                    guard let self else { return }
                    presenter.navigationController?.pushViewController(StudioPermissionsViewController(granted: granted) { chosen, from in
                        self.askTwitch(for: chosen, from: from)
                    }, animated: true)
                }),
            ]))
        }

        let proItem: SettingsItem
        if pro.isSubscriber {
            proItem = SettingsItem(id: "studio.pro", title: String(localized: "Studio Pro", comment: "Studio settings"), icon: SettingsIcon(symbol: "sparkles", color: StudioPalette.ember), kind: .value(String(localized: "On", comment: "Studio Pro status")))
        } else {
            let value: String? = {
                if case .active(let ends) = pro.weekPhase() { return String(localized: "\(StudioProWeek.daysLeft(until: ends, now: Date())) days left", comment: "Studio Pro week") }
                return pro.product(StudioProStore.yearlyID).map { String(localized: "\($0.displayPrice) a year", comment: "Studio Pro price") }
            }()
            proItem = SettingsItem(id: "studio.pro", title: String(localized: "Get Studio Pro", comment: "Studio settings"), icon: SettingsIcon(symbol: "sparkles", color: StudioPalette.ember), kind: .link(value: value) { presenter in
                MidgarPaywallMoments.noteShown(placement: .settings)
                presenter.present(UINavigationController(rootViewController: StudioProViewController()), animated: true)
            })
        }
        result.append(SettingsSection(id: "studio.pro", header: String(localized: "Studio Pro", comment: "Studio settings header"), footer: String(localized: "Snooze and run ad breaks, alert sounds, the stream recap, moderator mode and quick messages, on iPhone, iPad and Apple TV.", comment: "Studio settings footer"), items: [
            proItem,
            SettingsItem(id: "studio.restore", title: String(localized: "Restore Purchases"), kind: .action(role: .normal) { presenter, _ in
                Task {
                    let restored = await StudioProStore.shared.restore()
                    let alert = UIAlertController(title: restored ? String(localized: "Studio Pro restored", comment: "Restore result") : String(localized: "Nothing to restore", comment: "Restore result"), message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    presenter.present(alert, animated: true)
                }
            }),
        ]))

        result.append(SettingsSection(id: "studio.quick", header: String(localized: "Chat", comment: "Studio settings header"), footer: String(localized: "Quick messages post to your chat in one tap, from here or the Apple TV, where they arrive through iCloud.", comment: "Studio settings footer"), items: [
            SettingsItem(id: "studio.quickMessages", title: String(localized: "Quick Messages", comment: "Studio settings"), kind: .link(value: settings.quickMessages.count.formatted()) { presenter in
                presenter.navigationController?.pushViewController(StudioQuickMessagesViewController(), animated: true)
            }),
            SettingsItem(id: "studio.announce", title: String(localized: "Announce Ad Breaks in Chat", comment: "Studio settings"), kind: .toggle(isOn: settings.current.announcesAds) { on in
                settings.update { $0.announcesAds = on }
            }),
        ]))

        var alertItems = StudioAlertKind.allCases.map { kind in
            SettingsItem(id: "studio.alert.\(kind.rawValue)", title: Self.title(for: kind), kind: .toggle(isOn: settings.current.alerts.shown.contains(kind)) { on in
                settings.update {
                    if on { $0.alerts.shown.insert(kind) } else { $0.alerts.shown.remove(kind) }
                }
            })
        }
        alertItems.insert(SettingsItem(id: "studio.sounds", title: String(localized: "Alert Sounds", comment: "Studio settings"), kind: .toggle(isOn: settings.current.micHearsTV != true) { on in
            settings.update { $0.micHearsTV = !on }
        }), at: 0)
        alertItems.insert(SettingsItem(id: "studio.adWarnings", title: String(localized: "Ad Break Chimes", comment: "Studio settings"), kind: .toggle(isOn: settings.current.adWarnings) { on in
            settings.update { $0.adWarnings = on }
        }), at: 1)
        result.append(SettingsSection(id: "studio.alerts", header: String(localized: "Alerts", comment: "Studio settings header"), footer: String(localized: "If your microphone can hear this device, turn sounds off so they don't reach your stream.", comment: "Studio settings footer"), items: alertItems))

        result.append(SettingsSection(id: "studio.screen", header: String(localized: "Screen", comment: "Studio settings header"), items: [
            SettingsItem(id: "studio.viewers", title: String(localized: "Show Viewer Count", comment: "Studio settings"), kind: .toggle(isOn: settings.current.showsViewers) { on in
                settings.update { $0.showsViewers = on }
            }),
            SettingsItem(id: "studio.awake", title: String(localized: "Keep the Screen On While Live", comment: "Studio settings"), kind: .toggle(isOn: settings.current.stayAwakeWhileLive) { on in
                settings.update { $0.stayAwakeWhileLive = on }
            }),
        ]))
        return result
    }

    private func askTwitch(for features: Set<StudioFeature>, from presenter: UIViewController) {
        guard let anchor = presenter.view.window else { return }
        Task { [weak self] in
            let current = await AppContainer.shared.auth.currentUser()?.scopes ?? []
            do {
                _ = try await AuthService.shared.login(presentationAnchor: anchor, scopes: StudioLauncher.scopes(for: features, keeping: current))
                if features.contains(.moderation) { SettingsStore.shared.update { $0.moderatorTools = true } }
                MidgarLog.info("Studio permissions granted: \(features.count) feature(s)", category: .studio)
                self?.load()
            } catch {
                MidgarLog.notice("Studio sign-in failed: \(error)", category: .studio)
            }
        }
    }

    static func title(for kind: StudioAlertKind) -> String {
        switch kind {
        case .follows: String(localized: "Follows", comment: "Studio alert kind")
        case .subscriptions: String(localized: "Subscriptions", comment: "Studio alert kind")
        case .giftBombs: String(localized: "Gifted Subs", comment: "Studio alert kind")
        case .cheers: String(localized: "Cheers", comment: "Studio alert kind")
        case .powerUps: String(localized: "Power-ups", comment: "Studio alert kind")
        case .raids: String(localized: "Raids", comment: "Studio alert kind")
        case .redemptions: String(localized: "Channel Point Rewards", comment: "Studio alert kind")
        case .charity: String(localized: "Charity Donations", comment: "Studio alert kind")
        }
    }
}

/// What Studio may do on Twitch, chosen before Twitch's own page asks to approve exactly that.
@MainActor
final class StudioPermissionsViewController: SettingsPageViewController {
    private let refresh = PassthroughSubject<Void, Never>()
    private var chosen: Set<StudioFeature>
    private let ask: (Set<StudioFeature>, UIViewController) -> Void

    init(granted: Set<StudioFeature>, ask: @escaping (Set<StudioFeature>, UIViewController) -> Void) {
        chosen = granted.count > 1 ? granted : Set(StudioFeature.allCases)
        self.ask = ask
        let refresh = refresh
        super.init(title: String(localized: "Permissions", comment: "Studio permissions page"), changes: refresh.eraseToAnyPublisher()) { page in
            (page as? StudioPermissionsViewController)?.sections() ?? []
        }
        navigationItem.largeTitleDisplayMode = .never
    }

    private func sections() -> [SettingsSection] {
        let items = StudioFeature.allCases.map { feature in
            SettingsItem(id: "permission.\(feature.rawValue)", title: Self.title(feature), subtitle: Self.detail(feature), kind: .toggle(isOn: feature.isRequired || chosen.contains(feature)) { [weak self] on in
                guard let self, !feature.isRequired else {
                    self?.refresh.send()
                    return
                }
                if on { self.chosen.insert(feature) } else { self.chosen.remove(feature) }
                self.refresh.send()
            })
        }
        return [
            SettingsSection(id: "permissions.list", footer: String(localized: "Twitch shows you exactly these permissions to approve. Chat is always on: Studio is built around it.", comment: "Studio permissions footer"), items: items),
            SettingsSection(id: "permissions.ask", items: [
                SettingsItem(id: "permissions.go", title: String(localized: "Ask Twitch for These", comment: "Studio permissions"), kind: .action(role: .accent) { [weak self] presenter, _ in
                    guard let self else { return }
                    self.ask(self.chosen, presenter)
                }),
            ]),
        ]
    }

    static func title(_ feature: StudioFeature) -> String {
        switch feature {
        case .chat: String(localized: "Read chat and post quick messages", comment: "Studio permission")
        case .followers: String(localized: "See new followers", comment: "Studio permission")
        case .support: String(localized: "See subs, gifts, cheers and Power-ups", comment: "Studio permission")
        case .adBreaks: String(localized: "See and snooze ad breaks", comment: "Studio permission")
        case .runAds: String(localized: "Run ad breaks", comment: "Studio permission")
        case .pollsAndPredictions: String(localized: "Follow polls and predictions", comment: "Studio permission")
        case .hypeTrainsAndGoals: String(localized: "Follow hype trains and goals", comment: "Studio permission")
        case .channelPoints: String(localized: "See channel point rewards", comment: "Studio permission")
        case .moderation: String(localized: "Moderate chat", comment: "Studio permission")
        }
    }

    static func detail(_ feature: StudioFeature) -> String? {
        switch feature {
        case .chat: String(localized: "Always on", comment: "Studio permissions, chat")
        case .support: String(localized: "Affiliates and Partners", comment: "Studio permission detail")
        case .moderation: String(localized: "Delete, time out, ban, pin, shout out, chat modes, Shield Mode and AutoMod", comment: "Studio permission detail")
        default: nil
        }
    }
}

/// The streamer's quick messages: add, edit and remove the lines Studio can post to chat in one tap.
@MainActor
final class StudioQuickMessagesViewController: UITableViewController {
    private var messages: [String] = StudioSettingsStore.shared.quickMessages

    init() {
        super.init(style: .insetGrouped)
        title = String(localized: "Quick Messages", comment: "Studio quick messages page")
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.edit(at: nil) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(localized: "Up to \(StudioSettingsStore.quickMessageLimit). The first one is what an ad break announcement posts. Without Studio Pro, only the first one can be sent.", comment: "Studio quick messages footer")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = messages[indexPath.row]
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        edit(at: indexPath.row)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        messages.remove(at: indexPath.row)
        save()
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    private func edit(at index: Int?) {
        guard index != nil || messages.count < StudioSettingsStore.quickMessageLimit else { return }
        let alert = UIAlertController(title: index == nil ? String(localized: "New Quick Message", comment: "Studio quick messages") : String(localized: "Edit Quick Message", comment: "Studio quick messages"), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = index.map { self.messages[$0] }
            field.placeholder = String(localized: "Ad break in a minute, back in 90 seconds!", comment: "Default Studio quick message")
            field.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Save"), style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            if let index { self.messages[index] = String(text.prefix(ChatMetrics.messageLimit)) } else { self.messages.append(String(text.prefix(ChatMetrics.messageLimit))) }
            self.save()
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func save() {
        StudioSettingsStore.shared.setQuickMessages(messages)
    }
}
