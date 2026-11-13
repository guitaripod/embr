import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore
import MidgarPortal
import MidgarUI

/// Studio's coordinator, which Settings asks to change channel, permissions or the sample stream.
@MainActor
protocol TVStudioCoordinating: AnyObject {
    var isShowingSample: Bool { get }
    func openSample()
    func openOwnStudio()
    func chooseChannel(from controller: UIViewController)
    func changePermissions(from controller: UIViewController)
    func didSignOut()
}

/// Settings on the Apple TV: Studio Pro, which channel Studio shows and what it may do, how the screen and alerts
/// behave, chat, the Twitch account, Founding Member, safety, Midgar's other apps and the legal pages.
/// Laid out like the Apple TV's own Settings: the list on the right, and on the left a picture, name and description of
/// the section in focus.
final class TVSettingsViewController: TVSettingsPageViewController, UITableViewDataSource, UITableViewDelegate, UINavigationControllerDelegate {
    private enum Row: Hashable {
        case studioPro
        case restore
        case channel
        case permissions
        case sample
        case chatTextSize
        case chatSide
        case chatOnly
        case showViewers
        case stayAwakeLive
        case stayAwakeOffline
        case burnIn
        case sounds
        case volume
        case adWarnings
        case alertKind(StudioAlertKind)
        case adLength
        case announceAds
        case quickMessages
        case account
        case supporter
        case supporterNames
        case timestamps
        case animatedEmotes
        case emotes(EmoteProvider)
        case filter
        case blocked
        case moreApps
        case terms
        case privacy
        case support
        case version
    }

    private struct Section {
        let title: String?
        let detail: String?
        let picture: TVSettingsHeroView.Picture
        let rows: [Row]
    }

    private weak var coordinator: TVStudioCoordinating?
    private var sections: [Section] = []
    private var focusedSection = 0
    private var user: AuthenticatedUser?
    private var blockedCount = 0
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: TVStudioCoordinating?) {
        self.coordinator = coordinator
        super.init()
        title = String(localized: "Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.delegate = self
        tableView.dataSource = self
        tableView.delegate = self

        AppContainer.shared.auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        SupporterStore.shared.changes
            .merge(with: StudioProStore.shared.changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.hero.refreshAccent()
                self?.rebuild()
            }
            .store(in: &cancellables)
        SettingsStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        StudioSettingsStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        SupporterStore.shared.loadProduct()
        StudioProStore.shared.loadProducts()
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let ownTitle = viewController is TVSettingsPageViewController || viewController is TVTextViewController
        navigationController.setNavigationBarHidden(ownTitle, animated: animated)
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

    /// Lays the list out again. When only the values changed, the rows are filled in place so focus stays where it is.
    private func rebuild() {
        let previous = sections.map(\.rows)
        sections = makeSections()
        if previous == sections.map(\.rows) {
            tableView.reconfigureRows(at: tableView.indexPathsForVisibleRows ?? [])
        } else {
            tableView.reloadData()
        }
        focusedSection = min(focusedSection, max(0, sections.count - 1))
        showHero(animated: false)
    }

    private func makeSections() -> [Section] {
        let store = SupporterStore.shared
        let supporter = store.isSupporter
        let pro = StudioProStore.shared
        let chatRows: [Row] = [.timestamps, .animatedEmotes, .supporterNames] + [.emotes(.sevenTV), .emotes(.betterTTV), .emotes(.frankerFaceZ)]
        let proDetail: String = {
            if pro.isSubscriber { return String(localized: "Every Studio Pro feature is yours on iPhone, iPad and Apple TV.", comment: "Studio Pro settings") }
            if case .active(let ends) = pro.weekPhase() {
                return String(localized: "Your free week of Studio Pro has \(StudioProWeek.daysLeft(until: ends, now: Date())) days left. Nothing is charged when it ends.", comment: "Studio Pro settings")
            }
            return String(localized: "Snooze and run ad breaks, alert sounds, the stream recap, moderator mode and quick messages, on every device.", comment: "Studio Pro settings")
        }()
        return [
            Section(title: String(localized: "Studio Pro", comment: "Settings section"), detail: proDetail, picture: .symbol("sparkles.tv.fill"), rows: pro.isSubscriber ? [.studioPro] : [.studioPro, .restore]),
            Section(
                title: String(localized: "Your Channel", comment: "Settings section"),
                detail: String(localized: "Studio shows your own channel, or one you moderate. Permissions decide what Studio may read and do on Twitch.", comment: "Settings section"),
                picture: .symbol("person.crop.square.fill"),
                rows: user == nil ? [.sample] : [.channel, .permissions, .sample]
            ),
            Section(
                title: String(localized: "Screen", comment: "Settings section"),
                detail: String(localized: "The Apple TV stays awake while you're live. Burn-in protection moves the screen a little every few minutes and dims chat after ten quiet minutes. Your TV's own sleep timer still applies, so turn it off for long streams.", comment: "Settings section"),
                picture: .symbol("tv.fill"),
                rows: [.chatTextSize, .chatSide, .chatOnly, .showViewers, .stayAwakeLive, .stayAwakeOffline, .burnIn]
            ),
            Section(
                title: String(localized: "Alerts", comment: "Settings section"),
                detail: String(localized: "Sounds play through the TV. If your microphone can hear the TV, keep them off so they don't reach your stream.", comment: "Settings section"),
                picture: .symbol("bell.badge.fill"),
                rows: [.sounds, .volume, .adWarnings] + StudioAlertKind.allCases.map { Row.alertKind($0) }
            ),
            Section(
                title: String(localized: "Ad Breaks", comment: "Settings section"),
                detail: String(localized: "Run Ad uses the length you pick here first. Announcing posts your first quick message a minute before a scheduled break.", comment: "Settings section"),
                picture: .symbol("timer"),
                rows: [.adLength, .announceAds, .quickMessages]
            ),
            Section(title: String(localized: "Chat"), detail: nil, picture: .symbol("bubble.left.and.bubble.right.fill"), rows: chatRows),
            Section(
                title: String(localized: "Twitch Account"),
                detail: user == nil ? String(localized: "Studio needs your Twitch account to show your channel. Embr never sees your password.", comment: "Settings section") : nil,
                picture: .symbol("person.crop.circle"),
                rows: [.account]
            ),
            Section(
                title: SupporterCopy.name(number: nil),
                detail: supporter
                    ? String(localized: "Change your theme, colors, chat font and badge any time.")
                    : String(localized: "One purchase: themes, colors, chat fonts and a flame badge everyone sees. Studio Pro is separate."),
                picture: .flame(supporter ? store.choice.badgeColor : .violet),
                rows: [.supporter]
            ),
            Section(
                title: String(localized: "Safety"),
                detail: String(localized: "Objectionable messages are hidden. Users you block are hidden from your chat and reported to the developer."),
                picture: .symbol("hand.raised.fill"),
                rows: [.filter, .blocked]
            ),
            Section(title: nil, detail: nil, picture: .symbol("square.grid.2x2.fill"), rows: [.moreApps]),
            Section(title: String(localized: "About"), detail: nil, picture: .symbol("info.circle.fill"), rows: [.terms, .privacy, .support, .version]),
        ]
    }

    #if DEBUG
    /// Shows one section in the hero and scrolls to it, for a capture of a section the remote would have to reach.
    func showSectionForScreenshot(_ index: Int) {
        guard sections.indices.contains(index) else { return }
        focusedSection = index
        tableView.scrollToRow(at: IndexPath(row: 0, section: index), at: .middle, animated: false)
        showHero(animated: false)
    }
    #endif

    private func showHero(animated: Bool) {
        guard sections.indices.contains(focusedSection) else { return }
        let section = sections[focusedSection]
        let title = section.title ?? (section.rows.first == .moreApps ? String(localized: "More Apps from Midgar") : "")
        hero.show(TVSettingsHeroView.Content(picture: section.picture, title: title, detail: section.detail), animated: animated)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, didUpdateFocusIn context: UITableViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        guard let indexPath = context.nextFocusedIndexPath, indexPath.section != focusedSection else { return }
        focusedSection = indexPath.section
        showHero(animated: true)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        let settings = SettingsStore.shared.current
        let studio = StudioSettingsStore.shared.current
        cell.accessoryType = .none
        cell.accessibilityHint = sections[indexPath.section].detail
        switch sections[indexPath.section].rows[indexPath.row] {
        case .studioPro:
            let pro = StudioProStore.shared
            content.image = UIImage(systemName: "sparkles")
            content.imageProperties.tintColor = StudioPalette.emberLight
            if pro.isSubscriber {
                content.text = String(localized: "Studio Pro is on", comment: "Studio Pro settings row")
            } else if case .active(let ends) = pro.weekPhase() {
                content.text = String(localized: "Studio Pro week · \(StudioProWeek.daysLeft(until: ends, now: Date())) days left", comment: "Studio Pro settings row")
                content.secondaryText = String(localized: "Keep It", comment: "Studio Pro settings row")
                cell.accessoryType = .disclosureIndicator
            } else {
                content.text = String(localized: "Get Studio Pro", comment: "Studio Pro settings row")
                content.secondaryText = pro.product(StudioProStore.yearlyID).map { String(localized: "\($0.displayPrice) a year", comment: "Studio Pro price") }
                cell.accessoryType = .disclosureIndicator
            }
        case .restore:
            content.text = String(localized: "Restore Purchases")
        case .channel:
            content.text = String(localized: "Channel", comment: "Studio settings row")
            content.secondaryText = studio.role == .moderator
                ? String(localized: "Moderating \(studio.moderatedChannelName ?? studio.moderatedChannelLogin ?? "")", comment: "Studio settings row")
                : String(localized: "My Channel", comment: "Studio settings row")
            cell.accessoryType = .disclosureIndicator
        case .permissions:
            content.text = String(localized: "Permissions", comment: "Studio settings row")
            content.secondaryText = String(localized: "\(StudioFeature.granted(by: user?.scopes ?? []).count) of \(StudioFeature.allCases.count)", comment: "Studio settings, how many permissions are granted")
            cell.accessoryType = .disclosureIndicator
        case .sample:
            content.text = coordinator?.isShowingSample == true
                ? String(localized: "Leave the Sample Stream", comment: "Studio settings row")
                : String(localized: "Try a Sample Stream", comment: "Studio settings row")
        case .chatTextSize:
            content.text = String(localized: "Chat Text Size")
            content.secondaryText = Self.title(for: settings.tvChatTextSizePreference)
        case .chatSide:
            content.text = String(localized: "Chat Side")
            content.secondaryText = studio.chatOnRight ? String(localized: "Right") : String(localized: "Left")
        case .chatOnly:
            toggle(&content, String(localized: "Chat Only", comment: "Studio settings row"), studio.chatOnly)
        case .showViewers:
            toggle(&content, String(localized: "Show Viewer Count", comment: "Studio settings row"), studio.showsViewers)
        case .stayAwakeLive:
            toggle(&content, String(localized: "Stay Awake While Live", comment: "Studio settings row"), studio.stayAwakeWhileLive)
        case .stayAwakeOffline:
            toggle(&content, String(localized: "Stay Awake While Offline", comment: "Studio settings row"), studio.stayAwakeWhileOffline)
        case .burnIn:
            toggle(&content, String(localized: "Burn-In Protection", comment: "Studio settings row"), studio.burnInProtection)
        case .sounds:
            toggle(&content, String(localized: "Alert Sounds", comment: "Studio settings row"), studio.micHearsTV != true)
            if !StudioProStore.shared.hasPro { content.secondaryText = String(localized: "Studio Pro", comment: "Settings, a Pro feature") }
        case .volume:
            content.text = String(localized: "Sound Volume", comment: "Studio settings row")
            content.secondaryText = Self.volumeTitle(studio.soundVolume)
        case .adWarnings:
            toggle(&content, String(localized: "Ad Break Chimes", comment: "Studio settings row"), studio.adWarnings)
        case .alertKind(let kind):
            toggle(&content, Self.title(for: kind), studio.alerts.shown.contains(kind))
        case .adLength:
            content.text = String(localized: "Usual Ad Length", comment: "Studio settings row")
            content.secondaryText = String(localized: "\(studio.defaultAdLength) seconds", comment: "Studio settings value")
        case .announceAds:
            toggle(&content, String(localized: "Announce Ad Breaks in Chat", comment: "Studio settings row"), studio.announcesAds)
            if !StudioProStore.shared.hasPro { content.secondaryText = String(localized: "Studio Pro", comment: "Settings, a Pro feature") }
        case .quickMessages:
            content.text = String(localized: "Quick Messages", comment: "Studio settings row")
            content.secondaryText = String(localized: "Edit on iPhone", comment: "Studio settings value")
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
                content.text = SupporterCopy.name(number: store.number)
                content.secondaryText = badgeText(store.badge)
            } else {
                content.text = SupporterCopy.invitation
                content.secondaryText = store.product?.displayPrice
            }
            cell.accessoryType = .disclosureIndicator
        case .supporterNames:
            toggle(&content, String(localized: "Founding Member Name Colors"), settings.supporterNameEffectsEnabled)
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
            content.text = String(localized: "Contact Support")
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let store = SettingsStore.shared
        let studio = StudioSettingsStore.shared
        switch sections[indexPath.section].rows[indexPath.row] {
        case .studioPro:
            guard !StudioProStore.shared.isSubscriber else { return }
            MidgarPaywallMoments.noteShown(placement: .settings)
            present(TVStudioProViewController(), animated: true)
        case .restore:
            Task { [weak self] in
                let restored = await StudioProStore.shared.restore()
                _ = await SupporterStore.shared.restore()
                let alert = UIAlertController(
                    title: restored ? String(localized: "Studio Pro restored", comment: "Restore result") : String(localized: "Nothing to restore", comment: "Restore result"),
                    message: restored ? nil : String(localized: "This Apple Account has no Studio Pro purchase.", comment: "Restore result"),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                self?.present(alert, animated: true)
            }
        case .channel:
            coordinator?.chooseChannel(from: self)
        case .permissions:
            coordinator?.changePermissions(from: self)
        case .sample:
            if coordinator?.isShowingSample == true {
                coordinator?.openOwnStudio()
            } else {
                coordinator?.openSample()
            }
            dismiss(animated: true)
        case .chatTextSize:
            pickOption(
                title: String(localized: "Chat Text Size"),
                symbol: "textformat.size",
                options: Settings.ChatTextSize.allCases,
                selected: store.current.tvChatTextSizePreference,
                label: { Self.title(for: $0) }
            ) { size in store.update { $0.tvChatTextSize = size } }
        case .chatSide:
            studio.update { $0.chatOnRight.toggle() }
        case .chatOnly:
            studio.update { $0.chatOnly.toggle() }
        case .showViewers:
            studio.update { $0.showsViewers.toggle() }
        case .stayAwakeLive:
            studio.update { $0.stayAwakeWhileLive.toggle() }
        case .stayAwakeOffline:
            studio.update { $0.stayAwakeWhileOffline.toggle() }
        case .burnIn:
            studio.update { $0.burnInProtection.toggle() }
        case .sounds:
            guard StudioProStore.shared.hasPro else {
                MidgarPaywallMoments.noteShown(placement: .feature)
                present(TVStudioProViewController(), animated: true)
                return
            }
            studio.update { $0.micHearsTV = $0.micHearsTV == true ? false : true }
        case .volume:
            let levels: [Float] = [0.35, 0.7, 1]
            pickOption(
                title: String(localized: "Sound Volume", comment: "Studio settings row"),
                symbol: "speaker.wave.2.fill",
                options: levels,
                selected: levels.min { abs($0 - studio.current.soundVolume) < abs($1 - studio.current.soundVolume) } ?? 0.7,
                label: { Self.volumeTitle($0) }
            ) { level in
                studio.update { $0.soundVolume = level }
                StudioChimes.shared.play(.subscription, volume: level)
            }
        case .adWarnings:
            studio.update { $0.adWarnings.toggle() }
        case .alertKind(let kind):
            studio.update {
                if $0.alerts.shown.contains(kind) { $0.alerts.shown.remove(kind) } else { $0.alerts.shown.insert(kind) }
            }
        case .adLength:
            pickOption(
                title: String(localized: "Usual Ad Length", comment: "Studio settings row"),
                symbol: "timer",
                options: AdBreakClock.lengths,
                selected: studio.current.defaultAdLength,
                label: { String(localized: "\($0) seconds", comment: "Studio settings value") }
            ) { length in studio.update { $0.defaultAdLength = length } }
        case .announceAds:
            guard StudioProStore.shared.hasPro else {
                MidgarPaywallMoments.noteShown(placement: .feature)
                present(TVStudioProViewController(), animated: true)
                return
            }
            studio.update { $0.announcesAds.toggle() }
        case .quickMessages:
            navigationController?.pushViewController(
                TVTextViewController(title: String(localized: "Quick Messages", comment: "Studio settings row"), text: studio.quickMessages.map { "• \($0)" }.joined(separator: "\n\n") + "\n\n" + String(localized: "Write your own in Embr on iPhone or iPad: Settings > Embr Studio > Quick Messages. They reach the Apple TV through iCloud.", comment: "Studio quick messages help")),
                animated: true
            )
        case .account:
            if user != nil {
                confirmSignOut()
            } else {
                coordinator?.changePermissions(from: self)
            }
        case .supporter:
            navigationController?.pushViewController(TVSupporterViewController(), animated: true)
        case .supporterNames:
            store.update { $0.supporterNameEffects = !$0.supporterNameEffectsEnabled }
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
        symbol: String,
        options: [Option],
        selected: Option,
        label: @escaping (Option) -> String,
        choose: @escaping (Option) -> Void
    ) {
        let picker = TVOptionsViewController(title: title, symbol: symbol, options: options.map(label), selected: options.firstIndex(of: selected)) { index in
            choose(options[index])
        }
        navigationController?.pushViewController(picker, animated: true)
    }

    private func confirmSignOut() {
        let alert = UIAlertController(
            title: String(localized: "Sign out of Twitch?"),
            message: String(localized: "Studio closes on this Apple TV until you sign in again.", comment: "Studio sign out confirm"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Sign Out"), style: .destructive) { [weak self] _ in
            Task {
                await AppContainer.shared.auth.logout()
                self?.dismiss(animated: true)
                self?.coordinator?.didSignOut()
            }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private static func title(for size: Settings.ChatTextSize) -> String {
        switch size {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .extraLarge: String(localized: "Extra Large")
        }
    }

    private static func volumeTitle(_ volume: Float) -> String {
        switch volume {
        case ..<0.5: String(localized: "Soft", comment: "Studio sound volume")
        case ..<0.85: String(localized: "Medium", comment: "Studio sound volume")
        default: String(localized: "Loud", comment: "Studio sound volume")
        }
    }

    private static func title(for kind: StudioAlertKind) -> String {
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
final class TVOptionsViewController: TVSettingsPageViewController, UITableViewDataSource, UITableViewDelegate {
    private let symbol: String
    private let options: [String]
    private var selected: Int?
    private let choose: (Int) -> Void

    init(title: String, symbol: String, options: [String], selected: Int?, choose: @escaping (Int) -> Void) {
        self.symbol = symbol
        self.options = options
        self.selected = selected
        self.choose = choose
        super.init()
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        hero.show(TVSettingsHeroView.Content(picture: .symbol(symbol), title: title ?? "", detail: nil), animated: false)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.cell()
        content.text = options[indexPath.row]
        cell.contentConfiguration = content
        cell.accessoryType = indexPath.row == selected ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selected = indexPath.row
        choose(indexPath.row)
        navigationController?.popViewController(animated: true)
    }

    func indexPathForPreferredFocusedView(in tableView: UITableView) -> IndexPath? {
        selected.map { IndexPath(row: $0, section: 0) }
    }
}

/// The users blocked on this Apple TV; selecting one unblocks it.
final class TVBlockedUsersViewController: TVSettingsPageViewController, UITableViewDataSource, UITableViewDelegate {
    private var users: [BlockedUserRecord] = []

    override init() {
        super.init()
        title = String(localized: "Blocked Users")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        showHero()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { [weak self] in
            self?.users = await DatabaseManager.shared.blockedUsers()
            self?.tableView.reloadData()
            self?.showHero()
        }
    }

    private func showHero() {
        let detail = users.isEmpty ? nil : String(localized: "Select a user to unblock them.")
        hero.show(TVSettingsHeroView.Content(picture: .symbol("hand.raised.fill"), title: title ?? "", detail: detail), animated: false)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(users.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.cell()
        if users.isEmpty {
            content.text = String(localized: "Nobody is blocked")
        } else {
            content.text = users[indexPath.row].login
            content.image = UIImage(systemName: "person.crop.circle.badge.xmark")
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < users.count else { return }
        let user = users[indexPath.row]
        Task { [weak self] in
            await DatabaseManager.shared.removeBlockedUser(userID: user.userID)
            self?.users = await DatabaseManager.shared.blockedUsers()
            self?.tableView.reloadData()
            self?.showHero()
        }
    }
}
