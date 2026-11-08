import UIKit
import Combine
import EmbrCore
import MidgarKit

/// Embr's settings, laid out as the system Settings app: the Twitch account card on top, Founding Supporter, then one
/// row per area opening its own page, a search across every setting, and the More Apps card at the bottom.
@MainActor
final class SettingsViewController: SettingsPageViewController {
    let store: SettingsStore
    private let auth: AuthService
    private let refresh: PassthroughSubject<Void, Never>
    private let pageChanges: AnyPublisher<Void, Never>
    private var authState: AuthState = .anonymous
    private var avatar: UIImage?
    private var avatarUserID: String?
    private var enablingModeratorTools = false
    private var observers = Set<AnyCancellable>()

    init(store: SettingsStore = .shared, auth: AuthService = .shared) {
        self.store = store
        self.auth = auth
        let refresh = PassthroughSubject<Void, Never>()
        self.refresh = refresh
        let changes = store.changes.map { _ in () }
            .merge(with: refresh, TipJarStore.shared.changes, SupporterStore.shared.changes)
            .eraseToAnyPublisher()
        self.pageChanges = changes
        super.init(title: String(localized: "Settings"), changes: changes) { page in
            (page as? SettingsViewController)?.rootSections() ?? []
        }
        navigationItem.largeTitleDisplayMode = .always
        tabBarItem = UITabBarItem(
            title: String(localized: "Settings"),
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )
        searchEntries = { [weak self] in self?.allSearchEntries() ?? [] }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.authState = state
                self.loadAvatar()
                self.refresh.send()
            }
            .store(in: &observers)
        TipJarStore.shared.loadProducts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadAvatar()
    }

    #if DEBUG
    func showSupportForScreenshot() {
        navigationController?.pushViewController(makePage(Page.support), animated: false)
    }

    /// Opens one page for a screenshot, by its name in `Page`, or searches the root for `query`.
    func showPageForScreenshot(_ name: String, query: String?) {
        if let page = Page.allCases.first(where: { "\($0)" == name }) {
            navigationController?.pushViewController(makePage(page), animated: false)
        } else if let query, let search = navigationItem.searchController {
            search.isActive = true
            search.searchBar.text = query
        }
    }
    #endif

    /// The areas with a page of their own, in the order they appear.
    private enum Page: CaseIterable {
        case general, home, chat, video, safety, support, about, account

        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .home: String(localized: "Home")
            case .chat: String(localized: "Chat")
            case .video: String(localized: "Video")
            case .safety: String(localized: "Safety & Moderation")
            case .support: String(localized: "Support Embr")
            case .about: String(localized: "About")
            case .account: String(localized: "Account")
            }
        }

        var icon: SettingsIcon {
            switch self {
            case .general: SettingsIcon(symbol: "gearshape.fill", color: .systemGray)
            case .home: SettingsIcon(symbol: "house.fill", color: .systemBlue)
            case .chat: SettingsIcon(symbol: "bubble.left.and.bubble.right.fill", color: .systemPurple)
            case .video: SettingsIcon(symbol: "play.rectangle.fill", color: .systemRed)
            case .safety: SettingsIcon(symbol: "hand.raised.fill", color: .systemIndigo)
            case .support: SettingsIcon(symbol: "heart.fill", color: .systemPink)
            case .about: SettingsIcon(symbol: "info.circle.fill", color: .systemGray)
            case .account: SettingsIcon(symbol: "person.crop.circle.fill", color: .systemPurple)
            }
        }
    }

    private func sections(for page: Page) -> [SettingsSection] {
        switch page {
        case .general: generalSections()
        case .home: homeSections()
        case .chat: chatSections()
        case .video: videoSections()
        case .safety: safetySections()
        case .support: supportSections()
        case .about: aboutSections()
        case .account: accountSections()
        }
    }

    private func makePage(_ page: Page) -> SettingsPageViewController {
        let controller = SettingsPageViewController(title: page.title, changes: pageChanges) { [weak self] _ in
            self?.sections(for: page) ?? []
        }
        controller.navigationItem.largeTitleDisplayMode = .never
        return controller
    }

    private func pageLink(_ page: Page, value: String? = nil) -> SettingsItem {
        SettingsItem(id: "page.\(page)", title: page.title, icon: page.icon, kind: .link(value: value) { [weak self] presenter in
            guard let self else { return }
            presenter.navigationController?.pushViewController(self.makePage(page), animated: true)
        })
    }

    func push(_ controller: UIViewController, from presenter: UIViewController) {
        presenter.navigationController?.pushViewController(controller, animated: true)
    }

    private func rootSections() -> [SettingsSection] {
        [
            SettingsSection(id: "root.account", items: [accountCard()]),
            SettingsSection(id: "root.more", items: [moreAppsCard()]),
            SettingsSection(id: "root.supporter", items: [supporterItem(), studioItem()]),
            SettingsSection(id: "root.app", items: [pageLink(.general), pageLink(.home), pageLink(.chat), pageLink(.video)]),
            SettingsSection(id: "root.safety", items: [pageLink(.safety)]),
            SettingsSection(id: "root.embr", items: [pageLink(.support), pageLink(.about)]),
        ]
    }

    private func accountCard() -> SettingsItem {
        switch authState {
        case let .authenticated(user):
            return SettingsItem(id: "account.card", title: user.displayName, keywords: [String(localized: "Account"), "Twitch"], kind: .profile(
                name: user.displayName,
                detail: String(localized: "Twitch Account · @\(user.login)"),
                avatar: avatar
            ) { [weak self] presenter in
                guard let self else { return }
                self.push(self.makePage(.account), from: presenter)
            })
        case .anonymous:
            return SettingsItem(id: "account.card", title: String(localized: "Log In with Twitch"), keywords: [String(localized: "Account"), "Twitch"], kind: .profile(
                name: String(localized: "Log In with Twitch"),
                detail: String(localized: "Follow channels, join chat and get live alerts."),
                avatar: nil
            ) { [weak self] presenter in
                self?.login(from: presenter)
            })
        }
    }

    private func supporterItem() -> SettingsItem {
        let supporter = SupporterStore.shared
        let title = supporter.isSupporter
            ? supporter.number.map { String(localized: "Founding Supporter #\($0)") } ?? String(localized: "Founding Supporter")
            : String(localized: "Become a Founding Supporter")
        let subtitle = supporter.isSupporter
            ? String(localized: "Your themes, icons, chat font and badge.")
            : String(localized: "Themes, app icons, chat fonts and a badge everyone sees.")
        return SettingsItem(
            id: "supporter", title: title, subtitle: subtitle,
            icon: SettingsIcon(symbol: "flame.fill", color: .systemOrange),
            keywords: [String(localized: "Themes"), String(localized: "App Icon")],
            kind: .link(value: nil) { [weak self] presenter in
                self?.push(SupporterViewController(), from: presenter)
            }
        )
    }

    private func studioItem() -> SettingsItem {
        SettingsItem(
            id: "studio", title: String(localized: "Embr Studio", comment: "Settings row"),
            subtitle: String(localized: "For streamers: your chat, alerts and ad breaks on one screen.", comment: "Settings row"),
            icon: SettingsIcon(symbol: "sparkles.tv.fill", color: StudioPalette.ember),
            keywords: [String(localized: "Streamer"), String(localized: "Ads"), String(localized: "Alerts"), "Studio Pro"],
            kind: .link(value: nil) { [weak self] presenter in
                self?.push(StudioSettingsViewController(), from: presenter)
            }
        )
    }

    private func moreAppsCard() -> SettingsItem {
        SettingsItem(id: "moreApps", title: String(localized: "More Apps"), kind: .custom {
            let container = UIView()
            MidgarEntryView(config: EmbrMidgar.shared.portalConfig).embed(in: container, verticalInset: 8)
            return container
        })
    }

    private func generalSections() -> [SettingsSection] {
        let settings = store.current
        let themes: [(String, Settings.ThemePreference)] = [
            (String(localized: "System"), .system), (String(localized: "Light"), .light), (String(localized: "Dark"), .dark),
        ]
        return [
            SettingsSection(id: "general.look", items: [
                SettingsItem(id: "theme", title: String(localized: "Theme"), keywords: [String(localized: "Dark"), String(localized: "Light")], kind: .menu(
                    value: themes.first { $0.1 == settings.theme }?.0 ?? "",
                    choices: themes.map { title, theme in
                        SettingsChoice(title: title, isSelected: theme == settings.theme) { [weak self] in self?.store.update { $0.theme = theme } }
                    }
                )),
            ]),
            SettingsSection(id: "general.behavior", footer: String(localized: "Web links open inside Embr, or in your browser when this is off."), items: [
                toggle("openLinksInApp", String(localized: "Open Links In App"), settings.openLinksInApp, keywords: ["Safari"]) { $0.openLinksInApp = $1 },
                toggle("haptics", String(localized: "Haptics"), settings.hapticsEnabled, keywords: [String(localized: "Vibration")]) { $0.hapticsEnabled = $1 },
            ]),
        ]
    }

    private static func title(for tab: Settings.StartTab) -> String {
        switch tab {
        case .following: String(localized: "Following")
        case .favorites: String(localized: "Favorites")
        case .top: String(localized: "Top")
        }
    }

    /// A switch row that writes one setting.
    private func toggle(_ id: String, _ title: String, _ isOn: Bool, keywords: [String] = [], set: @escaping (inout Settings, Bool) -> Void) -> SettingsItem {
        SettingsItem(id: id, title: title, keywords: keywords, kind: .toggle(isOn: isOn) { [weak self] on in
            self?.store.update { set(&$0, on) }
        })
    }

    private func homeSections() -> [SettingsSection] {
        let settings = store.current
        return [
            SettingsSection(id: "home.lists", footer: String(localized: "Choose where Embr opens, what the Top tab shows, and what it remembers."), items: [
                SettingsItem(id: "startTab", title: String(localized: "Open Embr On"), kind: .menu(
                    value: Self.title(for: settings.startTabPreference),
                    choices: Settings.StartTab.allCases.map { tab in
                        SettingsChoice(title: Self.title(for: tab), isSelected: tab == settings.startTabPreference) { [weak self] in self?.store.update { $0.startTab = tab } }
                    }
                )),
                toggle("showRecentlyWatched", String(localized: "Show Recently Watched"), settings.showsRecentlyWatchedEnabled) { $0.showsRecentlyWatched = $1 },
                toggle("favoritesOnlyTop", String(localized: "Only Favorites in Top"), settings.favoritesOnlyTopEnabled) { $0.favoritesOnlyTop = $1 },
            ]),
            SettingsSection(id: "home.history", items: [
                SettingsItem(id: "clearWatchHistory", title: String(localized: "Clear Recently Watched"), kind: .action(role: .destructive) { [weak self] presenter, _ in
                    self?.confirmClearWatchHistory(from: presenter)
                }),
            ]),
        ]
    }

    private func confirmClearWatchHistory(from presenter: UIViewController) {
        let alert = UIAlertController(
            title: String(localized: "Clear Recently Watched?"),
            message: String(localized: "This removes every channel from Recently Watched. Your favorites are not affected."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Clear"), style: .destructive) { _ in
            WatchHistoryStore.shared.clear()
            Haptics.notify(.success)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        presenter.present(alert, animated: true)
    }

    private func chatSections() -> [SettingsSection] {
        let settings = store.current
        let providers: [EmoteProvider] = [.sevenTV, .betterTTV, .frankerFaceZ]
        return [
            SettingsSection(id: "chat.text", header: String(localized: "Text"), items: [
                SettingsItem(id: "messageScale", title: String(localized: "Message Scale"), keywords: [String(localized: "Size")], kind: .slider(
                    value: settings.messageScale, range: 0.75...1.5, step: 0.05, format: { String(format: "%.2fx", $0) }
                ) { [weak self] value in self?.store.update { $0.messageScale = value } }),
                SettingsItem(id: "fontSizeDelta", title: String(localized: "Font Size Adjustment"), keywords: [String(localized: "Size")], kind: .stepper(
                    value: Double(settings.fontSizeDelta), range: -4...8, step: 1, format: { $0 >= 0 ? "+\(Int($0))" : "\(Int($0))" }
                ) { [weak self] value in self?.store.update { $0.fontSizeDelta = Int(value.rounded()) } }),
            ]),
            SettingsSection(id: "chat.messages", header: String(localized: "Messages"), footer: String(localized: "Backfill shows the messages sent just before you joined, loaded from recent-messages.robotty.de."), items: [
                toggle("showTimestamps", String(localized: "Show Timestamps"), settings.showTimestamps) { $0.showTimestamps = $1 },
                toggle("compactChat", String(localized: "Compact Chat"), settings.compactChat) { $0.compactChat = $1 },
                toggle("recentMessagesBackfill", String(localized: "Backfill Recent Messages"), settings.recentMessagesBackfill) { $0.recentMessagesBackfill = $1 },
                toggle("supporterNameEffects", String(localized: "Supporter Name Colors"), settings.supporterNameEffectsEnabled) { $0.supporterNameEffects = $1 },
                SettingsItem(id: "highlights", title: String(localized: "Highlights"), keywords: [String(localized: "Mentions")], kind: .link(value: Self.highlightSummary(settings)) { [weak self] presenter in
                    self?.push(HighlightsViewController(), from: presenter)
                }),
            ]),
            SettingsSection(id: "chat.emotes", header: String(localized: "Emotes"), items: [
                toggle("animateEmotes", String(localized: "Animate Emotes"), settings.animateEmotes) { $0.animateEmotes = $1 },
            ] + providers.map { provider in
                toggle("emotes.\(provider.displayName)", String(localized: "\(provider.displayName) Emotes"), settings.thirdPartyEmotesEnabled(provider)) { $0.showThirdPartyEmotes[provider] = $1 }
            }),
        ]
    }

    /// The Highlights row's value: how many words and people stand out besides mentions, or Off when nothing does.
    private static func highlightSummary(_ settings: Settings) -> String {
        let extra = settings.highlightWordList.count + settings.highlightUserList.count
        if extra > 0 { return extra.formatted() }
        return settings.highlightMentions ? String(localized: "Mentions") : String(localized: "Off")
    }

    private func videoSections() -> [SettingsSection] {
        let settings = store.current
        return [
            SettingsSection(id: "video.playback", footer: String(localized: "Background Audio keeps a stream playing when you leave Embr or lock your iPhone."), items: [
                toggle("backgroundAudio", String(localized: "Background Audio"), settings.backgroundAudio ?? true) { $0.backgroundAudio = $1 },
                toggle("keepScreenAwake", String(localized: "Keep Screen Awake"), settings.keepScreenAwake) { $0.keepScreenAwake = $1 },
            ]),
        ]
    }

    private func safetySections() -> [SettingsSection] {
        let settings = store.current
        let muted = settings.mutedKeywordList.count
        return [
            SettingsSection(id: "safety.filter", footer: String(localized: "Hide objectionable messages, mute specific words, and manage users you've blocked. Blocked and reported users are hidden instantly and sent to the developer for review."), items: [
                toggle("filterObjectionableContent", String(localized: "Filter Objectionable Content"), settings.objectionableFilterEnabled) { $0.filterObjectionableContent = $1 },
                SettingsItem(id: "mutedKeywords", title: String(localized: "Muted Keywords"), kind: .link(
                    value: muted == 0 ? String(localized: "None") : (muted == 1 ? String(localized: "1 word") : String(localized: "\(muted) words"))
                ) { [weak self] presenter in self?.push(MutedKeywordsViewController(), from: presenter) }),
                SettingsItem(id: "blockedUsers", title: String(localized: "Blocked Users"), kind: .link(value: nil) { [weak self] presenter in
                    self?.push(BlockedUsersViewController(), from: presenter)
                }),
            ]),
            SettingsSection(id: "safety.moderation", header: String(localized: "Moderation"), footer: String(localized: "AutoMod's held messages, unban requests and the moderation log in the channels you moderate."), items: [
                SettingsItem(id: "moderatorTools", title: String(localized: "Moderator Tools"), keywords: ["AutoMod"], kind: .toggle(isOn: settings.moderatorToolsEnabled || enablingModeratorTools) { [weak self] on in
                    self?.setModeratorTools(on)
                }),
            ]),
        ]
    }

    /// Turns Moderator Tools on or off. Turning it on first asks Twitch for the moderator scopes when the viewer has
    /// not granted them, and leaves it off if they decline.
    private func setModeratorTools(_ on: Bool) {
        guard on else {
            enablingModeratorTools = false
            store.update { $0.moderatorTools = false }
            refresh.send()
            Task { await EventSubChatHub.shared.refreshModeration() }
            return
        }
        enablingModeratorTools = true
        Task { [weak self] in
            guard let self else { return }
            let user = await self.auth.currentUser()
            guard self.enablingModeratorTools else { return }
            if user?.hasModeratorScopes != true {
                do {
                    guard let anchor = self.navigationController?.view.window ?? self.view.window else { throw CancellationError() }
                    _ = try await self.auth.login(presentationAnchor: anchor, moderator: true)
                } catch {
                    MidgarLog.notice("moderator sign-in failed: \(error)", category: .auth)
                    self.enablingModeratorTools = false
                    self.refresh.send()
                    return
                }
            }
            guard self.enablingModeratorTools else { return }
            await ModerationAccess.shared.forget()
            guard self.enablingModeratorTools else { return }
            self.enablingModeratorTools = false
            self.store.update { $0.moderatorTools = true }
            Haptics.notify(.success)
            await EventSubChatHub.shared.refreshModeration()
        }
    }

    private func accountSections() -> [SettingsSection] {
        guard case let .authenticated(user) = authState else {
            return [SettingsSection(id: "account.signedOut", footer: String(localized: "Sign in with Twitch to follow channels and join chat."), items: [
                SettingsItem(id: "account.login", title: String(localized: "Log In with Twitch"), kind: .action(role: .accent) { [weak self] presenter, _ in
                    self?.login(from: presenter)
                }),
            ])]
        }
        return [
            SettingsSection(id: "account.info", items: [
                SettingsItem(id: "account.name", title: String(localized: "Name"), kind: .value(user.displayName)),
                SettingsItem(id: "account.login", title: String(localized: "Username"), kind: .value("@\(user.login)")),
            ]),
            SettingsSection(id: "account.session", items: [
                SettingsItem(id: "account.logout", title: String(localized: "Log Out"), kind: .action(role: .destructive) { [weak self] presenter, source in
                    self?.confirmLogout(from: presenter, source: source)
                }),
            ]),
            SettingsSection(id: "account.delete", footer: String(localized: "Signs you out, revokes Embr's access to your Twitch account and erases everything Embr keeps on this device."), items: [
                SettingsItem(id: "account.deleteAccount", title: String(localized: "Delete Account"), kind: .action(role: .destructive) { [weak self] presenter, _ in
                    self?.confirmDeleteAccount(from: presenter)
                }),
            ]),
        ]
    }

    /// The account card's picture: the viewer's Twitch avatar, looked up once per signed-in viewer and again on the
    /// next visit when the lookup failed.
    private func loadAvatar() {
        guard case let .authenticated(user) = authState else {
            avatar = nil
            avatarUserID = nil
            return
        }
        guard avatarUserID != user.id else { return }
        avatarUserID = user.id
        avatar = nil
        let scale = traitCollection.displayScale
        Task { [weak self] in
            let url = try? await AppContainer.shared.api.users(ids: [user.id]).first?.profileImageURL
            let image = if let url { await ImageLoader.shared.avatarImage(for: url, side: 60, scale: scale) } else { UIImage?.none }
            guard let self, self.avatarUserID == user.id else { return }
            guard let image else {
                self.avatarUserID = nil
                return
            }
            self.avatar = image
            self.refresh.send()
        }
    }

    private func login(from presenter: UIViewController) {
        guard let anchor = presenter.view.window else { return }
        Task { [weak self, weak presenter] in
            guard let self else { return }
            do {
                _ = try await self.auth.login(presentationAnchor: anchor)
                guard let presenter else { return }
                LiveAlertsPrompt.offerAfterSignIn(from: presenter)
            } catch {
                MidgarLog.notice("login failed: \(error)", category: .auth)
            }
        }
    }

    private func confirmLogout(from presenter: UIViewController, source: UIView?) {
        let alert = UIAlertController(title: String(localized: "Log Out?"), message: String(localized: "You'll return to browsing as a guest."), preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "Log Out"), style: .destructive) { [weak self, weak presenter] _ in
            guard let self else { return }
            Task { await self.auth.logout() }
            presenter?.navigationController?.popToRootViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = source ?? presenter.view
            popover.sourceRect = (source ?? presenter.view).bounds
        }
        presenter.present(alert, animated: true)
    }

    private func confirmDeleteAccount(from presenter: UIViewController) {
        let alert = UIAlertController(
            title: String(localized: "Delete Account?"),
            message: String(localized: "This signs you out and revokes Embr's access to your Twitch account. Your favorites, settings, watch history and caches on this device are erased, and Embr returns to first launch. This can't be undone."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Delete Account"), style: .destructive) { [weak self, weak presenter] _ in
            guard let presenter else { return }
            self?.performAccountDeletion(from: presenter)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        presenter.present(alert, animated: true)
    }

    /// Deletes the account with Settings held in place, so neither Back nor a swipe can leave the page mid-request,
    /// then restarts at first launch or explains the failure on whatever Settings shows.
    private func performAccountDeletion(from presenter: UIViewController) {
        let window = presenter.view.window
        let navigation = presenter.navigationController
        navigation?.view.isUserInteractionEnabled = false
        navigation?.isModalInPresentation = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.auth.deleteAccount()
                navigation?.view.isUserInteractionEnabled = true
                navigation?.isModalInPresentation = false
                (window?.windowScene?.delegate as? SceneDelegate)?.restartToFirstRun()
            } catch {
                MidgarLog.notice("account deletion failed: \(error)", category: .auth)
                navigation?.view.isUserInteractionEnabled = true
                navigation?.isModalInPresentation = false
                let host = navigation?.topViewController ?? presenter
                let alert = UIAlertController(
                    title: String(localized: "Couldn't Delete Account"),
                    message: String(localized: "Embr couldn't reach Twitch to revoke its access. Check your connection and try again. Nothing on this device was erased."),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                host.present(alert, animated: true)
            }
        }
    }

    /// Every setting on every page, each opening its page and flashing its row; the root's own rows open in place.
    private func allSearchEntries() -> [SearchEntry] {
        var entries: [SearchEntry] = []
        for section in rootSections() {
            for item in section.items where Self.isSearchable(item) {
                entries.append(SearchEntry(item: item, path: String(localized: "Settings")) { [weak self] presenter in
                    self?.openRootItem(item, from: presenter)
                })
            }
        }
        for page in Page.allCases where page != .account || authState != .anonymous {
            for section in sections(for: page) {
                for item in section.items where Self.isSearchable(item) {
                    var shown = item
                    if shown.icon == nil { shown.icon = page.icon }
                    entries.append(SearchEntry(item: shown, path: page.title) { [weak self] presenter in
                        guard let self else { return }
                        let controller = self.makePage(page)
                        controller.highlight(item.id)
                        presenter.navigationController?.pushViewController(controller, animated: true)
                    })
                }
            }
        }
        return entries
    }

    private static func isSearchable(_ item: SettingsItem) -> Bool {
        switch item.kind {
        case .custom, .loading: false
        default: true
        }
    }

    private func openRootItem(_ item: SettingsItem, from presenter: UIViewController) {
        switch item.kind {
        case .link(_, let open), .profile(_, _, _, let open): open(presenter)
        default: break
        }
    }
}
