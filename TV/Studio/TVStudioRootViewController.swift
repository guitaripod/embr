import UIKit
import Combine
import EmbrCore
import MidgarCore

/// The Apple TV app's root: the welcome screen until someone signs in, then Studio for their channel or one they
/// moderate, or the sample stream. It builds each Studio session and tears the old one down when the channel, the
/// permissions or the account change.
final class TVStudioRootViewController: UIViewController, TVStudioCoordinating {
    private var current: UIViewController?
    private var studio: TVStudioViewController?
    private var cancellables = Set<AnyCancellable>()
    private var lastUserID: String?
    private var started = false
    private(set) var isShowingSample = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioPalette.background
        overrideUserInterfaceStyle = .dark
        AppContainer.shared.auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.authChanged() }
            .store(in: &cancellables)
        StudioSettingsStore.shared.changes
            .map(\.role)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reopenIfOwn() }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        openOwnStudio()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        current.map { [$0] } ?? []
    }

    private func authChanged() {
        guard started else { return }
        Task { [weak self] in
            let user = await AppContainer.shared.auth.currentUser()
            guard let self, user?.id != self.lastUserID || user?.scopes != nil else { return }
            if user?.id != self.lastUserID, !self.isShowingSample {
                self.openOwnStudio()
            }
        }
    }

    private func reopenIfOwn() {
        guard !isShowingSample else { return }
        openOwnStudio()
    }

    func openSample() {
        isShowingSample = true
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
        show(studioFor: session)
        MidgarLog.info("Studio: sample stream opened", category: .studio)
    }

    func openOwnStudio() {
        isShowingSample = false
        Task { [weak self] in
            guard let user = await AppContainer.shared.auth.currentUser() else {
                self?.lastUserID = nil
                self?.showWelcome()
                return
            }
            self?.lastUserID = user.id
            await self?.openStudio(for: user)
        }
    }

    private func openStudio(for user: AuthenticatedUser) async {
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
        if features.contains(.moderation) {
            SettingsStore.shared.update { $0.moderatorTools = true }
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
        show(studioFor: session)
        MidgarLog.info("Studio: opened \(channel.broadcasterLogin) as \(role) with \(features.count) feature(s)", category: .studio)
    }

    private func show(studioFor session: StudioSession) {
        studio?.shutDown()
        let controller = TVStudioViewController(session: session, coordinator: self)
        studio = controller
        swap(to: controller)
    }

    private func showWelcome() {
        studio?.shutDown()
        studio = nil
        let welcome = TVStudioWelcomeViewController()
        welcome.onSignIn = { [weak self] in
            guard let self else { return }
            self.changePermissions(from: self)
        }
        welcome.onSample = { [weak self] in self?.openSample() }
        swap(to: welcome)
    }

    private func swap(to controller: UIViewController) {
        if let current {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        current = controller
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    func chooseChannel(from controller: UIViewController) {
        Task { [weak self] in
            guard let user = await AppContainer.shared.auth.currentUser() else { return }
            let channels = (try? await StudioAPIClient.shared.moderatedChannels(userID: user.id)) ?? []
            let sheet = UIAlertController(
                title: String(localized: "Which channel?", comment: "Studio channel picker"),
                message: channels.isEmpty ? String(localized: "You don't moderate any other channel.", comment: "Studio channel picker") : nil,
                preferredStyle: .actionSheet
            )
            sheet.addAction(UIAlertAction(title: String(localized: "My Channel (\(user.displayName))", comment: "Studio channel picker"), style: .default) { _ in
                StudioSettingsStore.shared.update { $0.role = .broadcaster }
                self?.openOwnStudio()
                controller.dismiss(animated: true)
            })
            for channel in channels.prefix(12) where channel.id != user.id {
                sheet.addAction(UIAlertAction(title: String(localized: "Moderate \(channel.name)", comment: "Studio channel picker"), style: .default) { _ in
                    StudioSettingsStore.shared.update {
                        $0.role = .moderator
                        $0.moderatedChannelID = channel.id
                        $0.moderatedChannelLogin = channel.login
                        $0.moderatedChannelName = channel.name
                    }
                    self?.openOwnStudio()
                    controller.dismiss(animated: true)
                })
            }
            sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
            controller.present(sheet, animated: true)
        }
    }

    func changePermissions(from controller: UIViewController) {
        let permissions = TVStudioPermissionsViewController()
        permissions.onDone = { [weak self] in
            self?.openOwnStudio()
        }
        let navigation = UINavigationController(rootViewController: permissions)
        navigation.modalPresentationStyle = .fullScreen
        TVRouter.topmost(from: controller).present(navigation, animated: true)
    }

    func didSignOut() {
        isShowingSample = false
        openOwnStudio()
    }

    #if DEBUG
    func showMomentForScreenshot(_ moment: String) {
        studio?.showMomentForScreenshot(moment)
    }

    func seedHistoryForScreenshot() {
        studio?.seedHistoryForScreenshot()
    }
    #endif
}

/// The first thing someone sees: what Studio is, and the two ways in.
final class TVStudioWelcomeViewController: UIViewController {
    var onSignIn: (() -> Void)?
    var onSample: (() -> Void)?

    private let signIn = TVStudioWelcomeViewController.bigButton(String(localized: "Sign In with Twitch", comment: "Studio welcome button"), symbol: "qrcode")
    private let sample = TVStudioWelcomeViewController.bigButton(String(localized: "Try a Sample Stream", comment: "Studio welcome button"), symbol: "play.rectangle.on.rectangle")

    private static func bigButton(_ title: String, symbol: String) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 16
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 26, leading: 40, bottom: 26, trailing: 40)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: 32, weight: .semibold)
            return updated
        }
        return UIButton(configuration: configuration)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioPalette.background
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [StudioPalette.ember.withAlphaComponent(0.28).cgColor, UIColor.clear.cgColor]
        glow.startPoint = CGPoint(x: 0.85, y: 0.05)
        glow.endPoint = CGPoint(x: 1.6, y: 1.1)
        glow.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        view.layer.addSublayer(glow)

        let eyebrow = UILabel()
        eyebrow.text = String(localized: "EMBR STUDIO", comment: "Studio welcome eyebrow")
        eyebrow.font = .systemFont(ofSize: 26, weight: .heavy)
        eyebrow.textColor = StudioPalette.emberLight
        let title = UILabel()
        title.text = String(localized: "Your stream's control room, on the TV.", comment: "Studio welcome title")
        title.font = .systemFont(ofSize: 76, weight: .heavy)
        title.textColor = StudioPalette.text
        title.numberOfLines = 2
        let body = UILabel()
        body.text = String(localized: "Chat you can read from across the room, the next ad break counting down, and every follow, sub, raid and hype train as it happens. For your own Twitch channel, or one you moderate. Studio shows no video.", comment: "Studio welcome body")
        body.font = .systemFont(ofSize: 32)
        body.textColor = StudioPalette.muted
        body.numberOfLines = 0
        let need = UILabel()
        need.text = String(localized: "You'll want this TV where you can see it while you stream.", comment: "Studio welcome note")
        need.font = .systemFont(ofSize: 26, weight: .semibold)
        need.textColor = StudioPalette.muted
        need.numberOfLines = 0
        signIn.addAction(UIAction { [weak self] _ in self?.onSignIn?() }, for: .primaryActionTriggered)
        sample.addAction(UIAction { [weak self] _ in self?.onSample?() }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [signIn, sample])
        buttons.spacing = 40
        let column = UIStackView(arrangedSubviews: [eyebrow, title, body, need, buttons])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 28
        column.setCustomSpacing(56, after: need)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 160),
            column.widthAnchor.constraint(equalToConstant: 1250),
            column.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        [signIn]
    }
}

/// What Studio may do on Twitch, chosen before the sign-in code appears. Only the chosen permissions are asked for;
/// chat is always on because Studio is built around it.
final class TVStudioPermissionsViewController: TVSettingsPageViewController, UITableViewDataSource, UITableViewDelegate {
    var onDone: (() -> Void)?

    private var chosen: Set<StudioFeature>

    override init() {
        let granted = StudioFeature.granted(by: [])
        chosen = granted.isEmpty ? Set(StudioFeature.allCases) : granted
        super.init()
        title = String(localized: "What Studio Can Do", comment: "Studio permissions screen")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        Task { [weak self] in
            if let user = await AppContainer.shared.auth.currentUser() {
                let granted = StudioFeature.granted(by: user.scopes)
                if granted.count > 1 { self?.chosen = granted.union([.chat]) }
                self?.tableView.reloadData()
            }
        }
        hero.show(TVSettingsHeroView.Content(
            picture: .symbol("checkmark.shield.fill"),
            title: title ?? "",
            detail: String(localized: "Pick what Studio may read and do on your channel. Twitch asks you to approve exactly these on your phone. You can change them later in Settings.", comment: "Studio permissions screen")
        ), animated: false)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? StudioFeature.allCases.count : 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        if indexPath.section == 1 {
            content.text = String(localized: "Continue to Sign In", comment: "Studio permissions screen")
            content.image = UIImage(systemName: "qrcode")
            cell.accessoryType = .disclosureIndicator
        } else {
            let feature = StudioFeature.allCases[indexPath.row]
            content.text = Self.title(feature)
            content.secondaryText = feature.isRequired ? String(localized: "Always on", comment: "Studio permissions, chat") : Self.detail(feature)
            cell.accessoryType = chosen.contains(feature) || feature.isRequired ? .checkmark : .none
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else {
            let scopes = StudioFeature.scopes(for: chosen)
            let signIn = TVSignInViewController(scopes: scopes)
            signIn.onSignedIn = { [weak self] in
                self?.dismiss(animated: true)
                self?.onDone?()
            }
            navigationController?.pushViewController(signIn, animated: true)
            return
        }
        let feature = StudioFeature.allCases[indexPath.row]
        guard !feature.isRequired else { return }
        if chosen.contains(feature) { chosen.remove(feature) } else { chosen.insert(feature) }
        tableView.reloadRows(at: [indexPath], with: .none)
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

    static func detail(_ feature: StudioFeature) -> String {
        switch feature {
        case .chat: ""
        case .followers: String(localized: "Followers on your channel or one you moderate", comment: "Studio permission detail")
        case .support: String(localized: "Affiliates and Partners", comment: "Studio permission detail")
        case .adBreaks: String(localized: "The next mid-roll and your snoozes", comment: "Studio permission detail")
        case .runAds: String(localized: "Start a break from the remote", comment: "Studio permission detail")
        case .pollsAndPredictions: String(localized: "Live results over chat", comment: "Studio permission detail")
        case .hypeTrainsAndGoals: String(localized: "Progress as it happens", comment: "Studio permission detail")
        case .channelPoints: String(localized: "Who redeemed what", comment: "Studio permission detail")
        case .moderation: String(localized: "Delete, time out, ban, pin, shout out, chat modes, Shield Mode and AutoMod", comment: "Studio permission detail")
        }
    }
}
