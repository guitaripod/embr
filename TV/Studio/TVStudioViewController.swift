import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Embr Studio on the Apple TV: the streamer's chat at couch size on one side; on the other the ad clock and the alert
/// feed; the channel's numbers along the top; moments over chat; and along the bottom the link to Twitch and the
/// buttons for quick messages, chat modes, Shield Mode and Settings. Everything is a focus move and a click.
final class TVStudioViewController: UIViewController {
    private let session: StudioSession
    private let settings: StudioSettingsStore
    private let pro: StudioProStore
    private let scale = StudioScale.tv
    private let stage = UIView()
    private let onAir: StudioOnAirStripView
    private let chatWall: TVStudioChatWallView
    private let topMoment: StudioTopMomentView
    private let liveMoment: StudioLiveMomentView
    private let adClock: StudioAdClockView
    private let modCard: TVStudioModerationCard
    private let feed: StudioAlertFeedView
    private let rail = UIStackView()
    private let statusDot = UIView()
    private let statusLabel = UILabel()
    private let tallyLabel = UILabel()
    private let quickButton: UIButton
    private let modesButton: UIButton
    private let shieldButton: UIButton
    private let settingsButton: UIButton
    private let offline: TVStudioOfflineView
    private let sampleRibbon = UILabel()
    private let toast = UILabel()
    private var cancellables = Set<AnyCancellable>()
    private var chatLeading: [NSLayoutConstraint] = []
    private var chatTrailing: [NSLayoutConstraint] = []
    private var chatOnlyConstraints: [NSLayoutConstraint] = []
    private var lastActivity = Date()
    private var burnInTask: Task<Void, Never>?
    private var connection: ConnectionStatus = .connecting
    private var shownLive: Bool?
    private weak var coordinator: TVStudioCoordinating?

    init(session: StudioSession, coordinator: TVStudioCoordinating?, settings: StudioSettingsStore = .shared, pro: StudioProStore = .shared) {
        self.session = session
        self.coordinator = coordinator
        self.settings = settings
        self.pro = pro
        onAir = StudioOnAirStripView(scale: .tv)
        chatWall = TVStudioChatWallView(viewModel: session.chat, scale: .tv)
        topMoment = StudioTopMomentView(scale: .tv)
        liveMoment = StudioLiveMomentView(scale: .tv)
        adClock = StudioAdClockView(scale: .tv)
        modCard = TVStudioModerationCard(scale: .tv)
        feed = StudioAlertFeedView(scale: .tv, limit: 6, fitsWholeRows: true)
        quickButton = StudioButton.make(title: String(localized: "Quick Message", comment: "Studio status line button"), scale: .tv, symbol: "text.bubble")
        modesButton = StudioButton.make(title: String(localized: "Chat Modes", comment: "Studio status line button"), scale: .tv, symbol: "slider.horizontal.3")
        shieldButton = StudioButton.make(title: String(localized: "Shield Mode", comment: "Studio status line button"), scale: .tv, symbol: "shield")
        settingsButton = StudioButton.make(title: String(localized: "Settings", comment: "Studio status line button"), scale: .tv, symbol: "gearshape")
        offline = TVStudioOfflineView(scale: .tv)
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioPalette.background
        build()
        bind()
        applySettings(settings.current)
        render(session.snapshot)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.start()
        chatWall.start()
        startBurnInGuard()
        updateAwake(session.snapshot)
        MidgarLog.info("Studio on screen", category: .studio)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        burnInTask?.cancel()
    }

    func shutDown() {
        chatWall.stop()
        session.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        if !offline.isHidden { return offline.focusTargets }
        if let target = topMoment.focusTargets.first { return [target] }
        if let snooze = adClock.focusTargets.first, !adClock.isHidden { return [snooze] }
        return [settingsButton]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .playPause:
                chatWall.toggleFreeze()
                return
            case .menu where chatWall.isFrozen:
                chatWall.catchUp()
                setNeedsFocusUpdate()
                updateFocusIfNeeded()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func build() {
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        [onAir, chatWall, topMoment, liveMoment, rail, offline, sampleRibbon, toast].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            stage.addSubview($0)
        }
        rail.axis = .vertical
        rail.spacing = scale.spacing
        rail.addArrangedSubview(adClock)
        rail.addArrangedSubview(modCard)
        rail.addArrangedSubview(feed)

        statusDot.layer.cornerRadius = 8
        statusDot.backgroundColor = StudioPalette.good
        statusLabel.font = scale.font(scale.caption)
        statusLabel.textColor = StudioPalette.muted
        tallyLabel.font = scale.font(scale.caption)
        tallyLabel.textColor = StudioPalette.muted
        tallyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let status = UIStackView(arrangedSubviews: [statusDot, statusLabel, tallyLabel, UIView(), quickButton, modesButton, shieldButton, settingsButton])
        status.spacing = scale.spacing
        status.alignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(status)

        sampleRibbon.text = String(localized: "SAMPLE STREAM", comment: "Studio sample stream ribbon")
        sampleRibbon.font = scale.font(scale.caption, .heavy)
        sampleRibbon.textColor = UIColor(white: 0.06, alpha: 1)
        sampleRibbon.backgroundColor = StudioPalette.emberLight
        sampleRibbon.textAlignment = .center
        sampleRibbon.layer.cornerRadius = 12
        sampleRibbon.clipsToBounds = true
        sampleRibbon.isHidden = true

        toast.font = scale.font(scale.body, .semibold)
        toast.textColor = UIColor(white: 0.06, alpha: 1)
        toast.backgroundColor = StudioPalette.text
        toast.textAlignment = .center
        toast.layer.cornerRadius = 30
        toast.clipsToBounds = true
        toast.alpha = 0
        toast.numberOfLines = 2

        let inset: CGFloat = 80
        let chatWidth = chatWall.widthAnchor.constraint(equalTo: stage.widthAnchor, multiplier: 0.56)
        chatLeading = [chatWall.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: inset), rail.leadingAnchor.constraint(equalTo: chatWall.trailingAnchor, constant: 40), rail.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -inset), chatWidth]
        chatTrailing = [chatWall.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -inset), rail.trailingAnchor.constraint(equalTo: chatWall.leadingAnchor, constant: -40), rail.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: inset), chatWall.widthAnchor.constraint(equalTo: stage.widthAnchor, multiplier: 0.56)]
        chatOnlyConstraints = [chatWall.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: inset), chatWall.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -inset)]

        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.topAnchor),
            stage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            onAir.topAnchor.constraint(equalTo: stage.topAnchor, constant: 48),
            onAir.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: inset),
            onAir.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -inset),
            chatWall.topAnchor.constraint(equalTo: onAir.bottomAnchor, constant: 28),
            chatWall.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -20),
            rail.topAnchor.constraint(equalTo: chatWall.topAnchor),
            rail.bottomAnchor.constraint(equalTo: chatWall.bottomAnchor),
            topMoment.topAnchor.constraint(equalTo: chatWall.topAnchor, constant: 70),
            topMoment.leadingAnchor.constraint(equalTo: chatWall.leadingAnchor, constant: 20),
            topMoment.trailingAnchor.constraint(equalTo: chatWall.trailingAnchor, constant: -20),
            liveMoment.bottomAnchor.constraint(equalTo: chatWall.bottomAnchor, constant: -20),
            liveMoment.leadingAnchor.constraint(equalTo: chatWall.leadingAnchor, constant: 20),
            liveMoment.trailingAnchor.constraint(equalTo: chatWall.trailingAnchor, constant: -20),
            status.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: inset),
            status.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -inset),
            status.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -40),
            statusDot.widthAnchor.constraint(equalToConstant: 16),
            statusDot.heightAnchor.constraint(equalToConstant: 16),
            offline.topAnchor.constraint(equalTo: onAir.bottomAnchor, constant: 28),
            offline.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: inset),
            offline.trailingAnchor.constraint(equalTo: stage.trailingAnchor, constant: -inset),
            offline.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -20),
            sampleRibbon.topAnchor.constraint(equalTo: stage.topAnchor, constant: 20),
            sampleRibbon.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            sampleRibbon.widthAnchor.constraint(equalToConstant: 300),
            sampleRibbon.heightAnchor.constraint(equalToConstant: 40),
            toast.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -40),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 1100),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
        NSLayoutConstraint.activate(chatLeading)

        adClock.onSnooze = { [weak self] in self?.snooze() }
        adClock.onRunAd = { [weak self] in self?.runAd() }
        chatWall.onSelect = { [weak self] message in self?.showActions(for: message) }
        topMoment.onAction = { [weak self] moment in
            if case .spamWave = moment { self?.setShield(true) }
        }
        topMoment.onDismiss = { [weak self] moment in
            switch moment {
            case .spamWave: self?.session.dismissSpamWarning()
            case .banner: self?.session.dismissBanner()
            case .away: self?.session.dismissAway()
            default: break
            }
            self?.setNeedsFocusUpdate()
        }
        modCard.onResolve = { [weak self] held, allow in self?.session.chat.resolveHeld(held, allow: allow) }
        quickButton.addAction(UIAction { [weak self] _ in self?.showQuickMessages() }, for: .primaryActionTriggered)
        modesButton.addAction(UIAction { [weak self] _ in self?.showChatModes() }, for: .primaryActionTriggered)
        shieldButton.addAction(UIAction { [weak self] _ in self?.toggleShield() }, for: .primaryActionTriggered)
        settingsButton.addAction(UIAction { [weak self] _ in self?.showSettings() }, for: .primaryActionTriggered)
        offline.onSettings = { [weak self] in self?.showSettings() }
    }

    private func bind() {
        session.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.render(snapshot) }
            .store(in: &cancellables)
        session.sounds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sound in self?.play(sound) }
            .store(in: &cancellables)
        session.chat.connectionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.connection = status
                self?.renderStatus()
            }
            .store(in: &cancellables)
        session.chat.moderationSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in self?.modCard.show(queue) }
            .store(in: &cancellables)
        session.chat.activitySubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.noteActivity() }
            .store(in: &cancellables)
        settings.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.applySettings(value) }
            .store(in: &cancellables)
        pro.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.render(self.session.snapshot)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.session.suspend() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.session.resume()
                self?.noteActivity()
            }
            .store(in: &cancellables)
    }

    private func render(_ snapshot: StudioSession.Snapshot) {
        onAir.show(snapshot, showsViewers: settings.current.showsViewers)
        adClock.show(snapshot, hasPro: hasPro)
        modCard.isHidden = !(snapshot.can(.moderation) && snapshot.role == .moderator) && modCard.isEmpty
        let canModerate = snapshot.can(.moderation)
        topMoment.show(StudioTopMoment.current(snapshot), now: snapshot.now, canModerate: canModerate)
        liveMoment.show(snapshot)
        feed.show(snapshot.feed, now: snapshot.now)
        chatWall.showShared(snapshot.sharedChat)
        let onAirNow = snapshot.isLive || snapshot.isSample
        modesButton.isHidden = !canModerate || !onAirNow
        shieldButton.isHidden = !canModerate || !onAirNow
        quickButton.isHidden = !snapshot.features.contains(.chat) || !onAirNow
        shieldButton.configuration?.image = UIImage(systemName: snapshot.shieldMode ? "shield.fill" : "shield")
        shieldButton.configuration?.title = snapshot.shieldMode
            ? String(localized: "Shield Mode On", comment: "Studio status line button")
            : String(localized: "Shield Mode", comment: "Studio status line button")
        sampleRibbon.isHidden = !snapshot.isSample || posesAsLive
        let isLive = snapshot.isLive || snapshot.isSample
        offline.isHidden = isLive
        chatWall.isHidden = !isLive
        rail.isHidden = !isLive || settings.current.chatOnly
        if !isLive { offline.show(snapshot) }
        if shownLive != isLive {
            shownLive = isLive
            updateAwake(snapshot)
            setNeedsFocusUpdate()
            if isLive {
                pro.noteLiveStream(role: snapshot.role, isSample: snapshot.isSample)
            }
        }
        renderTally(snapshot)
        renderStatus()
        if !snapshot.feed.isEmpty || snapshot.banner != nil { noteActivity(at: snapshot.feed.first?.at) }
    }

    private func renderTally(_ snapshot: StudioSession.Snapshot) {
        guard let tally = snapshot.tally, snapshot.isLive else {
            tallyLabel.text = nil
            return
        }
        var parts = [String(localized: "This stream: +\(tally.followers) followers", comment: "Studio status line tally")]
        if tally.subscriptions + tally.giftedSubscriptions > 0 { parts.append(String(localized: "\(tally.subscriptions + tally.giftedSubscriptions) subs", comment: "Studio status line tally")) }
        if tally.raids > 0 { parts.append(String(localized: "\(tally.raids) raids", comment: "Studio status line tally")) }
        if tally.adBreaks > 0 { parts.append(String(localized: "\(tally.adBreaks) ads", comment: "Studio status line tally")) }
        tallyLabel.text = "·  " + parts.joined(separator: " · ")
    }

    /// A DEBUG App Store capture poses the sample as a real live channel.
    private var posesAsLive: Bool {
        #if DEBUG
        TVScreenshotRoute.storeCapture
        #else
        false
        #endif
    }

    private func renderStatus() {
        if session.snapshot.isSample, !posesAsLive {
            statusDot.backgroundColor = StudioPalette.emberLight
            statusLabel.text = String(localized: "Sample stream: nothing here is real", comment: "Studio status line")
            return
        }
        switch connection {
        case .connected:
            statusDot.backgroundColor = StudioPalette.good
            statusLabel.text = String(localized: "Connected to Twitch", comment: "Studio status line")
        case .connecting, .idle:
            statusDot.backgroundColor = StudioPalette.muted
            statusLabel.text = String(localized: "Connecting to Twitch…", comment: "Studio status line")
        case .reconnecting:
            statusDot.backgroundColor = UIColor.systemYellow
            statusLabel.text = String(localized: "Reconnecting to Twitch…", comment: "Studio status line")
        case .disconnected(let reason):
            statusDot.backgroundColor = UIColor.systemRed
            statusLabel.text = reason ?? String(localized: "Twitch isn't answering. Studio keeps trying.", comment: "Studio status line")
        }
    }

    private func applySettings(_ value: StudioSettings) {
        NSLayoutConstraint.deactivate(chatLeading + chatTrailing + chatOnlyConstraints)
        if value.chatOnly {
            NSLayoutConstraint.activate(chatOnlyConstraints)
        } else {
            NSLayoutConstraint.activate(value.chatOnRight ? chatTrailing : chatLeading)
        }
        session.updatePreferences(value.effectiveAlerts)
        chatWall.relayout()
        render(session.snapshot)
    }

    /// Keeps the Apple TV awake while the channel is live, and lets it sleep when offline, as Settings says.
    private func updateAwake(_ snapshot: StudioSession.Snapshot) {
        let live = snapshot.isLive || snapshot.isSample
        UIApplication.shared.isIdleTimerDisabled = live ? settings.current.stayAwakeWhileLive : settings.current.stayAwakeWhileOffline
    }

    /// Whether Pro is open here: bought, in the free week, or the sample stream, which shows everything.
    private var hasPro: Bool {
        pro.hasPro || session.snapshot.isSample
    }

    private func play(_ sound: StudioSound) {
        guard hasPro, settings.current.micHearsTV != true else { return }
        StudioChimes.shared.play(sound, volume: settings.current.soundVolume)
    }

    private func noteActivity(at date: Date? = nil) {
        lastActivity = max(lastActivity, date ?? Date())
        if chatWall.alpha < 1 {
            UIView.animate(withDuration: 0.6) { self.chatWall.alpha = 1 }
        }
    }

    /// Moves the whole screen a few points every three minutes and dims chat after ten quiet minutes, so an OLED TV
    /// doesn't keep a ghost of the layout. The on-air strip and the alerts never dim.
    private func startBurnInGuard() {
        burnInTask?.cancel()
        burnInTask = Task { [weak self] in
            var step = 0
            let offsets: [CGPoint] = [.zero, CGPoint(x: 4, y: 2), CGPoint(x: -3, y: 4), CGPoint(x: 5, y: -3), CGPoint(x: -4, y: -2), CGPoint(x: 2, y: 5)]
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                guard self.settings.current.burnInProtection else {
                    self.stage.transform = .identity
                    continue
                }
                step += 1
                if step % 6 == 0 {
                    let offset = offsets[(step / 6) % offsets.count]
                    UIView.animate(withDuration: 2) { self.stage.transform = CGAffineTransform(translationX: offset.x, y: offset.y) }
                }
                if Date().timeIntervalSince(self.lastActivity) > 600, self.chatWall.alpha == 1 {
                    UIView.animate(withDuration: 2) { self.chatWall.alpha = 0.55 }
                }
            }
        }
    }

    private func showToast(_ text: String) {
        toast.text = "   \(text)   "
        UIAccessibility.post(notification: .announcement, argument: text)
        UIView.animate(withDuration: 0.25) { self.toast.alpha = 1 }
        UIView.animate(withDuration: 0.4, delay: 3.5, options: []) { self.toast.alpha = 0 }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void, success: String?) {
        Task { [weak self] in
            do {
                try await work()
                if let success { self?.showToast(success) }
            } catch StudioSession.ActionError.needsPro {
                self?.showPro()
            } catch StudioSession.ActionError.noSnoozesLeft {
                let refresh = self?.session.snapshot.adClock.nextSnoozeAt
                self?.showToast(refresh.map { String(localized: "No snoozes left. One comes back at \(StudioFormat.clock($0)).", comment: "Studio toast") }
                    ?? String(localized: "No snoozes left right now.", comment: "Studio toast"))
            } catch StudioSession.ActionError.refused(let message) {
                self?.showToast(message)
            } catch {
                self?.showToast(String(localized: "That didn't work. Try again in a moment.", comment: "Studio toast"))
            }
        }
    }

    private func snooze() {
        guard hasPro else { return showPro() }
        perform({ [weak self] in try await self?.session.snooze() }, success: nil)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, let next = self.session.snapshot.adClock.schedule?.nextAdAt else { return }
            self.showToast(String(localized: "Next ad moved to \(StudioFormat.clock(next))", comment: "Studio toast after a snooze"))
        }
    }

    private func runAd() {
        guard hasPro else { return showPro() }
        let sheet = UIAlertController(
            title: String(localized: "Run an Ad Break", comment: "Studio run ad sheet"),
            message: String(localized: "Viewers see ads for the length you pick. Breaks over 90 seconds lose more viewers.", comment: "Studio run ad sheet"),
            preferredStyle: .actionSheet
        )
        for length in AdBreakClock.lengths {
            let title = length == settings.current.defaultAdLength
                ? String(localized: "\(length) seconds (usual)", comment: "Studio run ad length")
                : String(localized: "\(length) seconds", comment: "Studio run ad length")
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.perform({ [weak self] in try await self?.session.runAd(length: length) },
                              success: String(localized: "Ad break started", comment: "Studio toast"))
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func showActions(for message: ChatMessage) {
        let snapshot = session.snapshot
        let actions = TVStudioMessageActions(message: message, session: session, canModerate: snapshot.can(.moderation), channelLogin: snapshot.channel.broadcasterLogin) { [weak self] text in
            self?.showToast(text)
        }
        present(actions.sheet(), animated: true)
    }

    private func showQuickMessages() {
        let messages = settings.quickMessages
        let sheet = UIAlertController(
            title: String(localized: "Quick Message", comment: "Studio quick messages sheet"),
            message: String(localized: "Write your own in Embr on iPhone: Settings > Embr Studio.", comment: "Studio quick messages sheet"),
            preferredStyle: .actionSheet
        )
        let usable = hasPro ? messages : Array(messages.prefix(1))
        for text in usable {
            sheet.addAction(UIAlertAction(title: text, style: .default) { [weak self] _ in
                self?.perform({ [weak self] in _ = try await self?.session.chat.send(text) }, success: String(localized: "Sent to chat", comment: "Studio toast"))
            })
        }
        if !hasPro, messages.count > 1 {
            sheet.addAction(UIAlertAction(title: String(localized: "More with Studio Pro…", comment: "Studio quick messages"), style: .default) { [weak self] _ in self?.showPro() })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func showChatModes() {
        let state = chatWall.currentRoomState ?? RoomState()
        let sheet = UIAlertController(title: String(localized: "Chat Modes", comment: "Studio chat modes sheet"), message: nil, preferredStyle: .actionSheet)
        let followersOn = (state.followersOnly ?? -1) >= 0
        let slowOn = (state.slowMode ?? 0) > 0
        let entries: [(String, ChatModeChange)] = [
            (state.emoteOnly ? String(localized: "Turn Off Emote-Only") : String(localized: "Turn On Emote-Only"), .emoteOnly(!state.emoteOnly)),
            (followersOn ? String(localized: "Turn Off Followers-Only") : String(localized: "Followers-Only, 10 Minutes"), .followersOnly(minutes: followersOn ? nil : 10)),
            (slowOn ? String(localized: "Turn Off Slow Mode") : String(localized: "Slow Mode, 10 Seconds"), .slow(seconds: slowOn ? nil : 10)),
            (state.subscribersOnly ? String(localized: "Turn Off Subscribers-Only") : String(localized: "Turn On Subscribers-Only"), .subscribersOnly(!state.subscribersOnly)),
        ]
        for (title, change) in entries {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.perform({ [weak self] in try await self?.session.changeChatMode(change) }, success: String(localized: "Chat mode changed", comment: "Studio toast"))
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func toggleShield() {
        setShield(!session.snapshot.shieldMode)
    }

    private func setShield(_ active: Bool) {
        let sheet = UIAlertController(
            title: active ? String(localized: "Turn On Shield Mode?", comment: "Studio shield confirm") : String(localized: "Turn Off Shield Mode?", comment: "Studio shield confirm"),
            message: active ? String(localized: "Twitch applies your Shield Mode settings to chat at once.", comment: "Studio shield confirm") : nil,
            preferredStyle: .alert
        )
        sheet.addAction(UIAlertAction(title: active ? String(localized: "Turn On", comment: "Studio shield confirm") : String(localized: "Turn Off", comment: "Studio shield confirm"), style: active ? .destructive : .default) { [weak self] _ in
            self?.perform({ [weak self] in try await self?.session.setShieldMode(active) },
                          success: active ? String(localized: "Shield Mode is on", comment: "Studio toast") : String(localized: "Shield Mode is off", comment: "Studio toast"))
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func showSettings() {
        let navigation = UINavigationController(rootViewController: TVSettingsViewController(coordinator: coordinator))
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func showPro() {
        MidgarPaywallMoments.noteShown(placement: .feature)
        present(TVStudioProViewController(), animated: true)
    }

    #if DEBUG
    /// Puts the sample stream at one moment for a screenshot.
    /// Fills the alert feed with the half hour before the moment, so a store capture shows a stream in full swing.
    func seedHistoryForScreenshot() {
        let now = Date()
        let history: [(TimeInterval, StudioEvent)] = [
            (-1500, .subscription(StudioSubscription(id: "shot-sub-1", userID: "sample-fernwick", userName: "fernwick", kind: .resub(months: 14), tier: .one, isPrime: false, message: "still the comfiest stream"))),
            (-1140, .cheer(StudioCheer(id: "shot-cheer", userID: "sample-quill", userName: "quillandmoss", bits: 500, message: "Cheer500 for the lighthouse fund"))),
            (-840, .redemption(StudioRedemption(id: "shot-redeem", userID: "sample-pebble", userName: "pebblecat", rewardTitle: "Pick the next colour", cost: 2000, input: "teal"))),
            (-420, .subscription(StudioSubscription(id: "shot-sub-2", userID: "sample-kite", userName: "kitebright", kind: .new, tier: .one, isPrime: true, message: ""))),
            (-180, .follow(StudioFollow(userID: "sample-driftwood", userName: "driftwooddan", followedAt: now.addingTimeInterval(-180)))),
        ]
        for (offset, event) in history {
            session.apply(event, at: now.addingTimeInterval(offset))
        }
    }

    func showMomentForScreenshot(_ moment: String) {
        let now = Date()
        switch moment {
        case "raid":
            session.apply(.raid(StudioRaid(raiderID: "sample-nightjar", raiderName: "Nightjar", raiderLogin: "nightjar", viewers: 312, profileImageURL: nil)), at: now)
        case "gift":
            session.apply(.giftBomb(StudioGiftBomb(id: "shot-gift", gifterID: "sample-copperlark", gifterName: "copperlark", count: 10, tier: .one)), at: now)
        case "hype":
            session.apply(.hypeTrain(StudioHypeTrain(id: "shot-hype", phase: .running, level: 3, progress: 680, goal: 1000, total: 2680, expiresAt: now.addingTimeInterval(221), topContributors: [StudioContributor(userName: "copperlark", kind: .subscription, total: 5000), StudioContributor(userName: "quillandmoss", kind: .bits, total: 500)], isGolden: false)), at: now)
        case "poll":
            session.apply(.poll(StudioPoll(id: "shot-poll", title: "Next painting?", choices: [StudioChoice(id: "a", title: "Stormy harbour", votes: 58), StudioChoice(id: "b", title: "Northern lights", votes: 31), StudioChoice(id: "c", title: "Foggy forest", votes: 11)], endsAt: now.addingTimeInterval(80), phase: .open)), at: now)
        case "prediction":
            session.apply(.prediction(StudioPrediction(id: "shot-prediction", title: "Does the lighthouse get its light tonight?", outcomes: [StudioChoice(id: "y", title: "Yes", votes: 41_200), StudioChoice(id: "n", title: "Not yet", votes: 18_900)], locksAt: now.addingTimeInterval(95), phase: .open)), at: now)
        case "adsoon":
            session.seedAdForScreenshot(nextIn: 48)
        case "adrun":
            session.apply(.adBreakBegan(StudioAdBreak(startedAt: now.addingTimeInterval(-18), duration: 90, isAutomatic: true)), at: now)
        case "offline":
            session.showOfflineForScreenshot()
        case "actions":
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, let message = self.latestMessageForScreenshot() else { return }
                self.showActions(for: message)
            }
        default:
            break
        }
    }

    private func latestMessageForScreenshot() -> ChatMessage? {
        ChatMessage(
            id: "shot-message",
            channelID: session.snapshot.channel.id,
            timestamp: Date(),
            author: ChatUser(id: "sample-quill", login: "quillandmoss", displayName: "quillandmoss"),
            fragments: [.text("@MossAndMirrors the reflection in the water 💛")],
            badges: []
        )
    }
    #endif
}
