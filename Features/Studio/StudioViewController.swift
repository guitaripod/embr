import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Embr Studio on iPhone and iPad: the streamer's own chat with its message box and moderation, the channel's numbers,
/// the ad clock and the alert feed. On an iPad or a wide window the alerts sit beside chat; on an iPhone they share the
/// space with chat behind a switch. Moments show over chat as they do on the TV.
final class StudioViewController: UIViewController {
    private let session: StudioSession
    private let settings: StudioSettingsStore
    private let pro: StudioProStore
    private let chatController: ChatViewController
    private var scale: StudioScale
    private let onAir: StudioOnAirStripView
    private let adClock: StudioAdClockView
    private let feed: StudioAlertFeedView
    private let feedScroll = UIScrollView()
    private let topMoment: StudioTopMomentView
    private let liveMoment: StudioLiveMomentView
    private let switcher = UISegmentedControl(items: [String(localized: "Chat", comment: "Studio iPhone switch"), String(localized: "Alerts", comment: "Studio iPhone switch")])
    private let chatArea = UIView()
    private let rail = UIStackView()
    private let offlineLabel = UILabel()
    private let sampleBadge = UILabel()
    private var cancellables = Set<AnyCancellable>()
    private var wide = false
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var shownLive: Bool?

    init(session: StudioSession, isAnonymous: Bool, userLogin: String?, settings: StudioSettingsStore = .shared, pro: StudioProStore = .shared) {
        self.session = session
        self.settings = settings
        self.pro = pro
        let wide = UIDevice.current.userInterfaceIdiom == .pad
        scale = wide ? .pad : .phone
        onAir = StudioOnAirStripView(scale: scale)
        adClock = StudioAdClockView(scale: scale)
        feed = StudioAlertFeedView(scale: scale, limit: 40)
        topMoment = StudioTopMomentView(scale: scale)
        liveMoment = StudioLiveMomentView(scale: scale)
        chatController = ChatViewController(
            viewModel: session.chat,
            isAnonymous: isAnonymous,
            currentUserLogin: userLogin,
            broadcasterLogin: session.snapshot.channel.broadcasterLogin,
            readOnly: session.snapshot.isSample
        )
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioPalette.background
        navigationItem.title = String(localized: "Embr Studio", comment: "Studio screen title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.close() })
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: makeMenu())
        build()
        bind()
        relayout(for: view.bounds.size)
        render(session.snapshot)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.start()
        updateAwake()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in self.relayout(for: size) }
    }

    private func close() {
        session.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        dismiss(animated: true)
    }

    private func build() {
        addChild(chatController)
        chatController.view.translatesAutoresizingMaskIntoConstraints = false
        chatArea.addSubview(chatController.view)
        chatController.didMove(toParent: self)
        chatArea.layer.cornerRadius = scale.corner
        chatArea.layer.cornerCurve = .continuous
        chatArea.clipsToBounds = true
        chatArea.layer.borderWidth = 1
        chatArea.layer.borderColor = StudioPalette.line.cgColor
        [topMoment, liveMoment].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            chatArea.addSubview($0)
        }
        feedScroll.addSubview(feed)
        feed.translatesAutoresizingMaskIntoConstraints = false
        feedScroll.alwaysBounceVertical = true
        rail.axis = .vertical
        rail.spacing = scale.spacing
        rail.addArrangedSubview(adClock)
        switcher.selectedSegmentIndex = 0
        switcher.addAction(UIAction { [weak self] _ in self?.showSegment() }, for: .valueChanged)
        offlineLabel.font = scale.font(scale.body, .semibold, style: .body)
        offlineLabel.textColor = StudioPalette.muted
        offlineLabel.numberOfLines = 0
        offlineLabel.textAlignment = .center
        offlineLabel.isHidden = true
        sampleBadge.text = "  " + String(localized: "SAMPLE STREAM", comment: "Studio sample stream badge") + "  "
        sampleBadge.font = scale.font(scale.caption, .heavy, style: .caption1)
        sampleBadge.backgroundColor = StudioPalette.emberLight
        sampleBadge.textColor = UIColor(white: 0.05, alpha: 1)
        sampleBadge.layer.cornerRadius = 6
        sampleBadge.clipsToBounds = true
        sampleBadge.isHidden = true
        [onAir, sampleBadge, rail, switcher, chatArea, feedScroll, offlineLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            chatController.view.topAnchor.constraint(equalTo: chatArea.topAnchor),
            chatController.view.leadingAnchor.constraint(equalTo: chatArea.leadingAnchor),
            chatController.view.trailingAnchor.constraint(equalTo: chatArea.trailingAnchor),
            chatController.view.bottomAnchor.constraint(equalTo: chatArea.bottomAnchor),
            topMoment.topAnchor.constraint(equalTo: chatArea.topAnchor, constant: scale.spacing),
            topMoment.leadingAnchor.constraint(equalTo: chatArea.leadingAnchor, constant: scale.spacing),
            topMoment.trailingAnchor.constraint(equalTo: chatArea.trailingAnchor, constant: -scale.spacing),
            liveMoment.leadingAnchor.constraint(equalTo: chatArea.leadingAnchor, constant: scale.spacing),
            liveMoment.trailingAnchor.constraint(equalTo: chatArea.trailingAnchor, constant: -scale.spacing),
            liveMoment.bottomAnchor.constraint(equalTo: chatArea.bottomAnchor, constant: -84),
            feed.topAnchor.constraint(equalTo: feedScroll.contentLayoutGuide.topAnchor),
            feed.leadingAnchor.constraint(equalTo: feedScroll.frameLayoutGuide.leadingAnchor),
            feed.trailingAnchor.constraint(equalTo: feedScroll.frameLayoutGuide.trailingAnchor),
            feed.bottomAnchor.constraint(equalTo: feedScroll.contentLayoutGuide.bottomAnchor),
            sampleBadge.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            sampleBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            offlineLabel.centerXAnchor.constraint(equalTo: chatArea.centerXAnchor),
            offlineLabel.centerYAnchor.constraint(equalTo: chatArea.centerYAnchor),
            offlineLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chatArea.leadingAnchor, constant: 24),
        ])
        adClock.onSnooze = { [weak self] in self?.snooze() }
        adClock.onRunAd = { [weak self] in self?.runAd() }
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
        }
    }

    /// Side by side when there is room for a 340-point rail beside a usable chat, stacked otherwise.
    private func relayout(for size: CGSize) {
        wide = size.width >= 760
        NSLayoutConstraint.deactivate(layoutConstraints)
        let guide = view.safeAreaLayoutGuide
        let margin: CGFloat = wide ? 20 : 12
        var constraints = [
            onAir.topAnchor.constraint(equalTo: guide.topAnchor, constant: wide ? 12 : 8),
            onAir.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
            onAir.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
        ]
        if wide {
            constraints += [
                chatArea.topAnchor.constraint(equalTo: onAir.bottomAnchor, constant: 16),
                chatArea.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
                chatArea.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
                rail.topAnchor.constraint(equalTo: chatArea.topAnchor),
                rail.leadingAnchor.constraint(equalTo: chatArea.trailingAnchor, constant: 16),
                rail.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
                rail.widthAnchor.constraint(equalToConstant: 360),
                feedScroll.topAnchor.constraint(equalTo: rail.bottomAnchor, constant: 12),
                feedScroll.leadingAnchor.constraint(equalTo: rail.leadingAnchor),
                feedScroll.trailingAnchor.constraint(equalTo: rail.trailingAnchor),
                feedScroll.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin),
                switcher.topAnchor.constraint(equalTo: onAir.bottomAnchor),
                switcher.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            ]
        } else {
            constraints += [
                rail.topAnchor.constraint(equalTo: onAir.bottomAnchor, constant: 10),
                rail.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
                rail.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
                switcher.topAnchor.constraint(equalTo: rail.bottomAnchor, constant: 10),
                switcher.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
                switcher.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
                chatArea.topAnchor.constraint(equalTo: switcher.bottomAnchor, constant: 10),
                chatArea.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: margin),
                chatArea.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -margin),
                chatArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                feedScroll.topAnchor.constraint(equalTo: chatArea.topAnchor),
                feedScroll.leadingAnchor.constraint(equalTo: chatArea.leadingAnchor),
                feedScroll.trailingAnchor.constraint(equalTo: chatArea.trailingAnchor),
                feedScroll.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            ]
        }
        layoutConstraints = constraints
        NSLayoutConstraint.activate(constraints)
        switcher.isHidden = wide
        showSegment()
    }

    private func showSegment() {
        let alerts = !wide && switcher.selectedSegmentIndex == 1
        chatArea.isHidden = alerts
        feedScroll.isHidden = !wide && !alerts
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
        settings.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.session.updatePreferences(value.effectiveAlerts)
                self.render(self.session.snapshot)
            }
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
            .sink { [weak self] _ in self?.session.resume() }
            .store(in: &cancellables)
    }

    private var hasPro: Bool { pro.hasPro || session.snapshot.isSample }

    private func render(_ snapshot: StudioSession.Snapshot) {
        onAir.show(snapshot, showsViewers: settings.current.showsViewers)
        adClock.show(snapshot, hasPro: hasPro)
        topMoment.show(StudioTopMoment.current(snapshot), now: snapshot.now, canModerate: snapshot.can(.moderation))
        liveMoment.show(snapshot)
        feed.show(snapshot.feed, now: snapshot.now)
        sampleBadge.isHidden = true
        navigationItem.title = snapshot.isSample
            ? String(localized: "Sample Stream", comment: "Studio screen title on the sample stream")
            : String(localized: "Embr Studio", comment: "Studio screen title")
        let live = snapshot.isLive || snapshot.isSample
        rail.isHidden = adClock.isHidden && wide == false
        offlineLabel.isHidden = live
        if !live {
            var lines = [String(localized: "You're offline. Studio comes alive the moment you go live.", comment: "Studio iOS offline")]
            if let segment = snapshot.nextStream {
                lines.append(String(localized: "Next stream: \(StudioFormat.schedule(segment, now: snapshot.now))", comment: "Studio iOS offline"))
            }
            if let recap = snapshot.recap {
                lines.append(String(localized: "Last stream: \(recap.peakViewers.formatted()) peak viewers, +\(recap.followers) followers, \((recap.subscriptions + recap.giftedSubscriptions).formatted()) subs and gifts.", comment: "Studio iOS offline recap"))
            }
            offlineLabel.text = lines.joined(separator: "\n\n")
        }
        chatController.view.alpha = live ? 1 : 0.25
        if shownLive != live {
            shownLive = live
            updateAwake()
            if live { pro.noteLiveStream(role: snapshot.role, isSample: snapshot.isSample) }
        }
        navigationItem.rightBarButtonItem?.menu = makeMenu()
    }

    private func updateAwake() {
        let live = session.snapshot.isLive || session.snapshot.isSample
        UIApplication.shared.isIdleTimerDisabled = live && settings.current.stayAwakeWhileLive
    }

    private func play(_ sound: StudioSound) {
        guard hasPro, settings.current.micHearsTV != true else { return }
        StudioChimes.shared.play(sound, volume: settings.current.soundVolume)
    }

    private func makeMenu() -> UIMenu {
        let snapshot = session.snapshot
        var items: [UIMenuElement] = []
        let quick = settings.quickMessages.enumerated().map { index, text in
            UIAction(title: text, attributes: !hasPro && index > 0 ? [.disabled] : []) { [weak self] _ in
                self?.perform({ [weak self] in _ = try await self?.session.chat.send(text) }, success: String(localized: "Sent to chat", comment: "Studio toast"))
            }
        }
        items.append(UIMenu(title: String(localized: "Quick Message", comment: "Studio menu"), image: UIImage(systemName: "text.bubble"), children: quick))
        if snapshot.can(.moderation) {
            items.append(UIAction(title: String(localized: "Chat Modes", comment: "Studio menu"), image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in self?.showChatModes() })
            items.append(UIAction(
                title: snapshot.shieldMode ? String(localized: "Turn Off Shield Mode", comment: "Studio menu") : String(localized: "Turn On Shield Mode", comment: "Studio menu"),
                image: UIImage(systemName: snapshot.shieldMode ? "shield.slash" : "shield"),
                attributes: snapshot.shieldMode ? [] : .destructive
            ) { [weak self] _ in self?.setShield(!snapshot.shieldMode) })
        }
        items.append(UIAction(title: String(localized: "Studio Settings", comment: "Studio menu"), image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.navigationController?.pushViewController(StudioSettingsViewController(), animated: true)
        })
        return UIMenu(children: items)
    }

    private func showToast(_ text: String) {
        let toast = UILabel()
        toast.text = "  \(text)  "
        toast.font = .preferredFont(forTextStyle: .subheadline)
        toast.textColor = UIColor(white: 0.05, alpha: 1)
        toast.backgroundColor = StudioPalette.text
        toast.layer.cornerRadius = 16
        toast.clipsToBounds = true
        toast.textAlignment = .center
        toast.numberOfLines = 2
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])
        UIAccessibility.post(notification: .announcement, argument: text)
        toast.alpha = 0
        UIView.animate(withDuration: 0.2) { toast.alpha = 1 }
        UIView.animate(withDuration: 0.3, delay: 3, options: [], animations: { toast.alpha = 0 }, completion: { _ in toast.removeFromSuperview() })
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void, success: String?) {
        Task { [weak self] in
            do {
                try await work()
                if let success { self?.showToast(success) }
                Haptics.notify(.success)
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
        sheet.popoverPresentationController?.sourceView = adClock
        present(sheet, animated: true)
    }

    private func showChatModes() {
        let sheet = UIAlertController(title: String(localized: "Chat Modes", comment: "Studio chat modes sheet"), message: nil, preferredStyle: .actionSheet)
        let entries: [(String, ChatModeChange)] = [
            (String(localized: "Emote-Only On"), .emoteOnly(true)), (String(localized: "Emote-Only Off"), .emoteOnly(false)),
            (String(localized: "Followers-Only, 10 Minutes"), .followersOnly(minutes: 10)), (String(localized: "Followers-Only Off"), .followersOnly(minutes: nil)),
            (String(localized: "Slow Mode, 10 Seconds"), .slow(seconds: 10)), (String(localized: "Slow Mode Off"), .slow(seconds: nil)),
            (String(localized: "Subscribers-Only On"), .subscribersOnly(true)), (String(localized: "Subscribers-Only Off"), .subscribersOnly(false)),
        ]
        for (title, change) in entries {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.perform({ [weak self] in try await self?.session.changeChatMode(change) }, success: String(localized: "Chat mode changed", comment: "Studio toast"))
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private func setShield(_ active: Bool) {
        perform({ [weak self] in try await self?.session.setShieldMode(active) },
                success: active ? String(localized: "Shield Mode is on", comment: "Studio toast") : String(localized: "Shield Mode is off", comment: "Studio toast"))
    }

    private func showPro() {
        MidgarPaywallMoments.noteShown(placement: .feature)
        present(UINavigationController(rootViewController: StudioProViewController()), animated: true)
    }

    #if DEBUG
    func showMomentForScreenshot(_ moment: String) {
        let now = Date()
        switch moment {
        case "raid":
            session.apply(.raid(StudioRaid(raiderID: "sample-nightjar", raiderName: "Nightjar", raiderLogin: "nightjar", viewers: 312, profileImageURL: nil)), at: now)
        case "hype":
            session.apply(.hypeTrain(StudioHypeTrain(id: "shot-hype", phase: .running, level: 3, progress: 680, goal: 1000, total: 2680, expiresAt: now.addingTimeInterval(221), topContributors: [StudioContributor(userName: "copperlark", kind: .subscription, total: 5000)], isGolden: false)), at: now)
        case "poll":
            session.apply(.poll(StudioPoll(id: "shot-poll", title: "Next painting?", choices: [StudioChoice(id: "a", title: "Stormy harbour", votes: 58), StudioChoice(id: "b", title: "Northern lights", votes: 31), StudioChoice(id: "c", title: "Foggy forest", votes: 11)], endsAt: now.addingTimeInterval(80), phase: .open)), at: now)
        case "adsoon":
            session.seedAdForScreenshot(nextIn: 48)
        case "alerts":
            switcher.selectedSegmentIndex = 1
            showSegment()
        default:
            break
        }
    }
    #endif
}
