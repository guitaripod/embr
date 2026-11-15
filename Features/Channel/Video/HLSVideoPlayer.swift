import AVKit
import AVFoundation
import Combine
import UIKit
import EmbrCore
import MidgarCore

@MainActor
final class HLSVideoPlayer: NSObject, VideoPlaying {

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            playerLayer.videoGravity = .resizeAspect
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }

    var view: UIView { playerView }

    var statePublisher: AnyPublisher<VideoState, Never> { stateSubject.eraseToAnyPublisher() }
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { latencySubject.eraseToAnyPublisher() }
    var adBreakPublisher: AnyPublisher<TimeInterval?, Never> { adBreakSubject.eraseToAnyPublisher() }
    var progressPublisher: AnyPublisher<PlaybackProgress, Never> { progressSubject.eraseToAnyPublisher() }
    /// The TV playing the stream while AirPlay or a mirrored or wired display has the picture; nil while it plays here.
    var externalRoutePublisher: AnyPublisher<ExternalRoute?, Never> { externalRouteSubject.eraseToAnyPublisher() }

    private(set) var availableQualities: [StreamQuality] = []
    private(set) var currentQuality: StreamQuality?

    /// The player itself, for `AVPlayerViewController` on Apple TV, which draws the video and the transport controls.
    var avPlayer: AVPlayer { player }

    /// Runs on every item this player creates (a load, a quality swap, a restore), so the Apple TV player can give each
    /// one its title and artwork for the info panel.
    var itemConfigurator: ((AVPlayerItem) -> Void)?

    /// Hyper Low Latency: plays one variant's media playlist instead of the master, because AVPlayer's adaptive
    /// switching reads Hyper's still-growing segments as a slow network and stalls. Auto then means
    /// `LiveLatency.hyperQuality`, and picking a quality swaps variants instead of capping the master's bitrate.
    /// Set before `load(_:)`.
    var pinsVariant = false

    private let playerView = PlayerView()
    private let player = AVPlayer()
    private let stateSubject = CurrentValueSubject<VideoState, Never>(.idle)
    private let latencySubject = CurrentValueSubject<TimeInterval?, Never>(nil)
    private let adBreakSubject = CurrentValueSubject<TimeInterval?, Never>(nil)
    private let progressSubject = CurrentValueSubject<PlaybackProgress, Never>(.empty)
    private let externalRouteSubject = CurrentValueSubject<ExternalRoute?, Never>(nil)
    private var externalPlaybackObservation: NSKeyValueObservation?
    private var preferredRate: Float = 1.0

    private let metadataCollector = AVPlayerItemMetadataCollector()
    private var adRanges: [AdRange] = []
    private var adTimeObserver: Any?

    private var currentItem: AVPlayerItem?
    private var resolution: PlaybackResolution?
    private var observers: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var latencyTimer: Timer?
    private var pictureInPictureController: AVPictureInPictureController?
    private weak var storedPictureInPictureDelegate: AVPictureInPictureControllerDelegate?
    private var isMuted = false
    private var preferredQualityName: String?
    private var pendingResume: PendingResume?
    private var playbackIntended = false
    private var liveLatencyConfigured = false
    private var latencySamples = 0
    private var loadGeneration = 0
    private var appliedAudioOptions: AVAudioSession.CategoryOptions?
    private(set) var isAudioOnly = false
    private var audioOnlyRequested = false
    private var appliedAudioOnlyName: String?
    private var qualityBeforeAudioOnly: StreamQuality?
    private var wasAutoBeforeAudioOnly = false

    private enum PendingResume {
        case time(CMTime)
        case liveEdge
    }

    override init() {
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        playerView.player = player
        metadataCollector.setDelegate(self, queue: .main)
        observeAudioSession()
        observeExternalPlayback()
        configurePictureInPicture()
    }

    private var audioObservers: [NSObjectProtocol] = []

    private func observeAudioSession() {
        let center = NotificationCenter.default
        audioObservers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue) }
        })
        audioObservers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated { self?.handleRouteChange(reasonValue: reasonValue) }
        })
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            player.pause()
        case .ended:
            if let optionsValue, AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
               playbackIntended {
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        reflectExternalPlayback()
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else { return }
        playbackIntended = false
        player.pause()
    }

    /// A mirrored or wired display gets the stream full screen through external playback instead of a copy of the phone,
    /// and the page learns whenever a TV takes the picture or gives it back.
    private func observeExternalPlayback() {
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        externalPlaybackObservation = player.observe(\.isExternalPlaybackActive, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.reflectExternalPlayback() }
        }
    }

    /// Publishes which screen has the picture, named after the AirPlay receiver or display the audio route goes to.
    /// Picture in picture cannot start from a picture a TV is showing, so it does not try to when the app leaves.
    private func reflectExternalPlayback() {
        let route = player.isExternalPlaybackActive ? ExternalRoute(deviceName: Self.externalOutputName()) : nil
        guard route != externalRouteSubject.value else { return }
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = route == nil
        externalRouteSubject.send(route)
        MidgarLog.info("HLS external playback \(route == nil ? "ended" : "on \(route?.deviceName ?? "an unnamed screen")")", category: .playback)
    }

    private static func externalOutputName() -> String? {
        let external: [AVAudioSession.Port] = [.airPlay, .HDMI]
        return AVAudioSession.sharedInstance().currentRoute.outputs.first { external.contains($0.portType) }?.portName
    }

    /// Jumps to the live edge, except during a stitched ad: its playlist is the ad alone until the worker can list the
    /// content after it, and a jump to that edge leaves the player waiting on segments the next playlist no longer has.
    /// The ad's end seeks to live itself.
    func seekToLive() {
        guard adBreakSubject.value == nil else { return }
        guard let item = currentItem,
              let range = item.seekableTimeRanges.last?.timeRangeValue,
              range.duration.seconds > 0 else { return }
        player.seek(to: range.end, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Float) {
        preferredRate = rate
        player.defaultRate = rate
        if player.timeControlStatus == .playing { player.rate = rate }
    }

    func load(_ resolution: PlaybackResolution) {
        load(resolution, playing: true)
    }

    /// Loads a stream, and starts it only when `playing`: a latency switch made while the viewer has the stream paused
    /// or the page stopped keeps it that way.
    func load(_ resolution: PlaybackResolution, playing: Bool) {
        loadGeneration += 1
        self.resolution = resolution
        availableQualities = resolution.qualities
        if let saved = preferredQualityName, let match = availableQualities.first(where: { $0.name == saved }) {
            currentQuality = match
        } else {
            currentQuality = nil
        }
        if audioOnlyRequested {
            isAudioOnly = currentQuality?.isAudioOnly == true
        }
        configureAudioSession()
        stateSubject.send(.loading)
        pendingResume = nil

        if pinsVariant, currentQuality == nil {
            loadPinnedVariant(of: resolution, generation: loadGeneration, playing: playing)
            return
        }
        start(currentQuality?.url ?? resolution.masterPlaylistURL, playing: playing)
    }

    private func start(_ url: URL, playing: Bool) {
        let item = AVPlayerItem(url: url)
        applyMutePreference()
        attach(item)
        player.replaceCurrentItem(with: item)
        playbackIntended = playing
        if playing { player.play() } else { player.pause() }
        startLatencySampling()
        MidgarLog.info("HLS load url=\(url.absoluteString) qualities=\(availableQualities.count)", category: .playback)
    }

    /// Reads the master's qualities before playing and plays the one Hyper Low Latency picks, on its own; the master
    /// plays when it cannot be read or offers no video.
    private func loadPinnedVariant(of resolution: PlaybackResolution, generation: Int, playing: Bool) {
        Task { [weak self] in
            let text = await HLSPlaylistClient().playlist(at: resolution.masterPlaylistURL)
            guard let self, self.loadGeneration == generation else { return }
            let parsed = text.map(HLSPlaylistParser.qualities) ?? []
            if !parsed.isEmpty { self.availableQualities = parsed }
            let pinned = LiveLatency.hyperQuality(from: parsed, preferredName: self.preferredQualityName)
            if let pinned, pinned.name == self.preferredQualityName { self.currentQuality = pinned }
            MidgarLog.info("HLS hyper pins \(pinned?.name ?? "the master")", category: .playback)
            self.start(pinned?.url ?? resolution.masterPlaylistURL, playing: playing)
            self.applyAudioOnlyVariantIfAvailable()
        }
    }

    func play() {
        configureAudioSession()
        playbackIntended = true
        player.play()
    }

    func pause() {
        playbackIntended = false
        player.pause()
    }

    func setQuality(_ quality: StreamQuality) {
        preferredQualityName = isAutoQuality(quality) ? nil : quality.name
        currentQuality = isAutoQuality(quality) ? nil : quality

        if pinsVariant {
            pin(isAutoQuality(quality) ? nil : quality)
            return
        }

        if isAutoQuality(quality) {
            currentItem?.preferredPeakBitRate = 0
            MidgarLog.info("HLS quality -> Auto", category: .playback)
            return
        }

        if let bandwidth = quality.bandwidth, qualityBelongsToMaster(quality), !quality.isAudioOnly {
            currentItem?.preferredPeakBitRate = Double(bandwidth)
            MidgarLog.info("HLS quality -> \(quality.name) peakBitRate=\(bandwidth)", category: .playback)
            return
        }

        swapVariant(to: quality)
    }

    func setMuted(_ muted: Bool) {
        let changed = muted != isMuted
        isMuted = muted
        applyMutePreference()
        if changed { configureAudioSession() }
    }

    func teardown() {
        loadGeneration += 1
        latencyTimer?.invalidate()
        latencyTimer = nil
        pendingResume = nil
        playbackIntended = false
        detachObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        pictureInPictureController = nil
        adBreakSubject.send(nil)
        progressSubject.send(.empty)
        stateSubject.send(.idle)
        deactivateAudioSession()
        MidgarLog.info("HLS teardown", category: .playback)
    }

    /// Detaches or reattaches the AVPlayer from the on-screen AVPlayerLayer.
    /// Detaching while backgrounded is Apple's sanctioned way to keep audio running
    /// when the app leaves the foreground; PiP requires the layer attached, so
    /// callers must not detach while PiP is active.
    func setLayerAttached(_ attached: Bool) {
        let target: AVPlayer? = attached ? player : nil
        guard playerView.player !== target else { return }
        playerView.player = target
        MidgarLog.info("HLS layer \(attached ? "attached" : "detached")", category: .playback)
    }

    var audioOnlyQuality: StreamQuality? {
        availableQualities.first { $0.isAudioOnly }
    }

    /// Switches to the master's audio_only variant to save bandwidth, remembering
    /// the previous selection; switching back restores that variant or the master
    /// playlist (auto) exactly as before.
    func setAudioOnly(_ on: Bool) {
        guard on != audioOnlyRequested else { return }
        audioOnlyRequested = on
        if on {
            applyAudioOnlyVariantIfAvailable()
        } else {
            let previous = qualityBeforeAudioOnly
            let wasAuto = wasAutoBeforeAudioOnly
            qualityBeforeAudioOnly = nil
            let lastApplied = appliedAudioOnlyName
            appliedAudioOnlyName = nil
            guard isAudioOnly else {
                if let lastApplied, preferredQualityName == lastApplied {
                    preferredQualityName = nil
                }
                return
            }
            isAudioOnly = false
            if let previousName = previous?.name, !wasAuto,
               let match = availableQualities.first(where: { $0.name == previousName }) {
                preferredQualityName = match.name
                currentQuality = match
                swapVariant(to: match)
            } else {
                preferredQualityName = nil
                currentQuality = nil
                restoreMasterPlaylist()
            }
        }
    }

    private func applyAudioOnlyVariantIfAvailable() {
        guard audioOnlyRequested, !isAudioOnly, let audio = audioOnlyQuality else { return }
        isAudioOnly = true
        qualityBeforeAudioOnly = currentQuality
        wasAutoBeforeAudioOnly = currentQuality == nil
        appliedAudioOnlyName = audio.name
        preferredQualityName = audio.name
        currentQuality = audio
        swapVariant(to: audio)
        MidgarLog.info("HLS audio-only variant applied", category: .playback)
    }

    /// Hyper Low Latency swaps to the chosen variant, or Auto's pick, instead of capping the master's bitrate, which
    /// would bring adaptive switching back.
    private func pin(_ quality: StreamQuality?) {
        guard let target = quality ?? LiveLatency.hyperQuality(from: availableQualities) else { return }
        swapVariant(to: target)
        MidgarLog.info("HLS hyper quality -> \(quality?.name ?? "Auto (\(target.name))")", category: .playback)
    }

    private func restoreMasterPlaylist() {
        if pinsVariant, let pinned = LiveLatency.hyperQuality(from: availableQualities) {
            swapVariant(to: pinned)
            return
        }
        guard let url = resolution?.masterPlaylistURL else { return }
        let progress = progressSubject.value
        let resumeTime = player.currentTime()
        let item = AVPlayerItem(url: url)
        attach(item)
        pendingResume = progress.current > 0 ? (progress.isLive ? .liveEdge : .time(resumeTime)) : nil
        player.replaceCurrentItem(with: item)
        applyMutePreference()
        playbackIntended = true
        player.play()
        startLatencySampling()
        MidgarLog.info("HLS restore master after audio-only", category: .playback)
    }

    var canStartPictureInPicture: Bool {
        pictureInPictureController?.isPictureInPicturePossible ?? false
    }

    var isPictureInPictureActive: Bool {
        pictureInPictureController?.isPictureInPictureActive ?? false
    }

    func startPictureInPicture() {
        pictureInPictureController?.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pictureInPictureController?.stopPictureInPicture()
    }

    var pictureInPictureDelegate: AVPictureInPictureControllerDelegate? {
        get { storedPictureInPictureDelegate }
        set {
            storedPictureInPictureDelegate = newValue
            pictureInPictureController?.delegate = newValue
        }
    }

    /// Takes picture in picture down while the chat keyboard is up, and brings it back after. While an
    /// AVPictureInPictureController watches the player layer, iOS 26 draws a ghost copy of the keyboard at the top of
    /// the screen as the keyboard slides in, so the controller goes before the keyboard is asked for; leaving the app
    /// while typing therefore does not start picture in picture.
    func setPictureInPictureSuspended(_ suspended: Bool) {
        if suspended {
            guard pictureInPictureController?.isPictureInPictureActive != true else { return }
            pictureInPictureController = nil
        } else if pictureInPictureController == nil {
            configurePictureInPicture()
            pictureInPictureController?.delegate = storedPictureInPictureDelegate
        }
    }

    private func swapVariant(to quality: StreamQuality) {
        let progress = progressSubject.value
        let resumeTime = player.currentTime()
        let item = AVPlayerItem(url: quality.url)
        attach(item)
        if progress.current > 0 {
            pendingResume = progress.isLive ? .liveEdge : .time(resumeTime)
        } else {
            pendingResume = nil
        }
        player.replaceCurrentItem(with: item)
        applyMutePreference()
        playbackIntended = true
        player.play()
        startLatencySampling()
        MidgarLog.info("HLS quality swap variant -> \(quality.name) url=\(quality.url.absoluteString)", category: .playback)
    }

    private func attach(_ item: AVPlayerItem) {
        detachObservers()
        currentItem = item
        itemConfigurator?(item)
        liveLatencyConfigured = false
        item.preferredPeakBitRate = peakBitRate(for: currentQuality)

        item.add(metadataCollector)
        adRanges = []
        adBreakSubject.send(nil)
        installAdTimeObserver()

        observers.append(item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.handleStatus() }
        })
        observers.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            let isEmpty = item.isPlaybackBufferEmpty
            Task { @MainActor in
                if isEmpty { self?.stateSubject.send(.buffering) }
            }
        })
        observers.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let likelyToKeepUp = item.isPlaybackLikelyToKeepUp
            Task { @MainActor in
                if likelyToKeepUp { self?.reflectTimeControlStatus() }
            }
        })
        observers.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.reflectTimeControlStatus() }
        })

        let itemID = ObjectIdentifier(item)
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidPlayToEnd(itemID: itemID) }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "Playback stalled"
            MainActor.assumeIsolated { self?.itemFailedToPlayToEnd(itemID: itemID, message: message) }
        })
    }

    private func handleStatus() {
        guard let item = currentItem else { return }
        switch item.status {
        case .readyToPlay:
            if availableQualities.isEmpty {
                parseMasterIfNeeded(item)
            }
            configureLiveLatencyIfNeeded(item)
            applyPendingResume()
            reflectTimeControlStatus()
        case .failed:
            let message = item.error?.localizedDescription ?? "Playback failed"
            stateSubject.send(.error(message))
            MidgarLog.error("HLS item failed: \(message)", category: .playback)
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func reflectTimeControlStatus() {
        switch player.timeControlStatus {
        case .paused:
            if stateSubject.value != .ended { stateSubject.send(.paused) }
        case .waitingToPlayAtSpecifiedRate:
            stateSubject.send(.buffering)
        case .playing:
            stateSubject.send(.playing)
        @unknown default:
            break
        }
    }

    private func itemDidPlayToEnd(itemID: ObjectIdentifier) {
        guard let currentItem, ObjectIdentifier(currentItem) == itemID else { return }
        stateSubject.send(.ended)
    }

    private func itemFailedToPlayToEnd(itemID: ObjectIdentifier, message: String) {
        guard let currentItem, ObjectIdentifier(currentItem) == itemID else { return }
        stateSubject.send(.error(message))
        MidgarLog.error("HLS failed to play to end: \(message)", category: .playback)
    }

    private func parseMasterIfNeeded(_ item: AVPlayerItem) {
        guard let url = resolution?.masterPlaylistURL else { return }
        let generation = loadGeneration
        Task { [weak self] in
            guard let text = await HLSPlaylistClient().playlist(at: url) else { return }
            let parsed = HLSPlaylistParser.qualities(text)
            guard !parsed.isEmpty, let self, self.loadGeneration == generation else { return }
            self.availableQualities = parsed
            MidgarLog.info("HLS parsed master qualities=\(parsed.count)", category: .playback)
            self.reapplyPreferredQuality()
            self.applyAudioOnlyVariantIfAvailable()
        }
    }

    /// Caps the master at the quality the viewer picked again after a reload, since a resolution never lists qualities
    /// and the pick would otherwise fall back to Auto on every token refresh or latency switch.
    private func reapplyPreferredQuality() {
        guard !pinsVariant, currentQuality == nil, let name = preferredQualityName,
              let match = availableQualities.first(where: { $0.name == name }), !match.isAudioOnly,
              let bandwidth = match.bandwidth else { return }
        currentQuality = match
        currentItem?.preferredPeakBitRate = Double(bandwidth)
        MidgarLog.info("HLS quality restored -> \(match.name)", category: .playback)
    }

    private func startLatencySampling() {
        latencyTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleLatency() }
        }
        RunLoop.main.add(timer, forMode: .common)
        latencyTimer = timer
    }

    /// How far behind the broadcast the picture is: now minus the program date Twitch stamps on the playing segment.
    /// Nil off a live stream, without a date, and for the nonsense an ad segment's date gives around a discontinuity.
    private func sampleLatency() {
        guard let item = currentItem, item.duration.isIndefinite, let date = item.currentDate() else {
            latencySubject.send(nil)
            return
        }
        let latency = Date().timeIntervalSince(date)
        let plausible = Self.plausibleLatency.contains(latency)
        latencySubject.send(plausible ? latency : nil)
        latencySamples += 1
        if plausible, latencySamples % Self.latencyLogEvery == 0, player.timeControlStatus == .playing {
            MidgarLog.info("HLS latency \(String(format: "%.1f", latency))s \(pinsVariant ? "hyper" : "standard")", category: .playback)
        }
    }

    private static let plausibleLatency: ClosedRange<TimeInterval> = 0.1...900
    /// Every 15th two-second sample, so the log shows how far behind a stream plays about twice a minute.
    private static let latencyLogEvery = 15

    private func applyMutePreference() {
        player.isMuted = isMuted
    }

    private func isAutoQuality(_ quality: StreamQuality) -> Bool {
        quality.name.caseInsensitiveCompare("auto") == .orderedSame
    }

    private func peakBitRate(for quality: StreamQuality?) -> Double {
        guard let quality, qualityBelongsToMaster(quality), let bandwidth = quality.bandwidth else { return 0 }
        return Double(bandwidth)
    }

    private func qualityBelongsToMaster(_ quality: StreamQuality?) -> Bool {
        guard let quality else { return false }
        return availableQualities.contains(quality)
    }

    private func applyPendingResume() {
        guard let pendingResume else { return }
        self.pendingResume = nil
        switch pendingResume {
        case .time(let time):
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        case .liveEdge:
            seekToLive()
        }
    }

    private func configureLiveLatencyIfNeeded(_ item: AVPlayerItem) {
        guard !liveLatencyConfigured, item.duration.isIndefinite else { return }
        liveLatencyConfigured = true
        item.automaticallyPreservesTimeOffsetFromLive = true
        let recommended = item.recommendedTimeOffsetFromLive
        let target: TimeInterval
        if recommended.isValid, recommended.isNumeric, recommended.seconds > 0 {
            target = min(recommended.seconds, 6)
        } else {
            target = 6
        }
        item.configuredTimeOffsetFromLive = CMTime(seconds: target, preferredTimescale: 600)
    }

    /// tvOS gets picture in picture from `AVPlayerViewController`, so the inline controller is iOS only.
    private func configurePictureInPicture() {
        #if os(iOS)
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            MidgarLog.info("HLS PiP unsupported on device", category: .playback)
            return
        }
        pictureInPictureController = AVPictureInPictureController(playerLayer: playerView.playerLayer)
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = externalRouteSubject.value == nil
        #endif
    }

    private func configureAudioSession() {
        let options: AVAudioSession.CategoryOptions = isMuted ? [.mixWithOthers] : []
        guard options != appliedAudioOptions else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: options)
            try session.setActive(true)
            appliedAudioOptions = options
        } catch {
            MidgarLog.notice("HLS audio session activate failed: \(error.localizedDescription)", category: .playback)
        }
    }

    private func deactivateAudioSession() {
        appliedAudioOptions = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func installAdTimeObserver() {
        if let adTimeObserver {
            player.removeTimeObserver(adTimeObserver)
            self.adTimeObserver = nil
        }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        adTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.evaluateAdBreak()
                self?.emitProgress(time)
            }
        }
    }

    private func emitProgress(_ time: CMTime) {
        guard let item = currentItem else {
            progressSubject.send(.empty)
            return
        }
        let duration = item.duration
        let hasDuration = duration.isNumeric && duration.seconds.isFinite && duration.seconds > 0
        let current = time.seconds.isFinite ? max(0, time.seconds) : 0
        progressSubject.send(PlaybackProgress(current: current, duration: hasDuration ? duration.seconds : 0, isLive: !hasDuration))
    }

    private func evaluateAdBreak() {
        guard let item = currentItem, let now = item.currentDate() else {
            adBreakSubject.send(nil)
            return
        }
        let active = adRanges.first { range in
            guard let end = range.end else { return false }
            return range.start <= now && now < end
        }
        guard let active, let end = active.end else {
            adBreakSubject.send(nil)
            return
        }
        adBreakSubject.send(max(0, end.timeIntervalSince(now)))
    }

    private func detachObservers() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        if let adTimeObserver {
            player.removeTimeObserver(adTimeObserver)
            self.adTimeObserver = nil
        }
        currentItem?.remove(metadataCollector)
    }

    isolated deinit {
        latencyTimer?.invalidate()
        if let adTimeObserver { player.removeTimeObserver(adTimeObserver) }
        observers.forEach { $0.invalidate() }
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

private let twitchStitchedAdClass = "twitch-stitched-ad"

private struct AdRange: Sendable {
    let start: Date
    let end: Date?
}

extension HLSVideoPlayer: AVPlayerItemMetadataCollectorPushDelegate {
    nonisolated func metadataCollector(
        _ metadataCollector: AVPlayerItemMetadataCollector,
        didCollect metadataGroups: [AVDateRangeMetadataGroup],
        indexesOfNewGroups: IndexSet,
        indexesOfModifiedGroups: IndexSet
    ) {
        let ranges = metadataGroups
            .filter { $0.classifyingLabel == twitchStitchedAdClass }
            .map { AdRange(start: $0.startDate, end: $0.endDate) }
        let labels = Set(metadataGroups.compactMap { $0.classifyingLabel }).sorted()
        MainActor.assumeIsolated {
            if !labels.isEmpty {
                MidgarLog.info("HLS metadata labels=\(labels) adRanges=\(ranges.count)", category: .playback)
            }
            self.adRanges = ranges
            self.evaluateAdBreak()
        }
    }
}
