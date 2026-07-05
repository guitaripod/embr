import AVKit
import AVFoundation
import Combine
import UIKit
import EmbrCore

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

    private(set) var availableQualities: [StreamQuality] = []
    private(set) var currentQuality: StreamQuality?

    private let playerView = PlayerView()
    private let player = AVPlayer()
    private let stateSubject = CurrentValueSubject<VideoState, Never>(.idle)
    private let latencySubject = CurrentValueSubject<TimeInterval?, Never>(nil)
    private let adBreakSubject = CurrentValueSubject<TimeInterval?, Never>(nil)
    private let progressSubject = CurrentValueSubject<PlaybackProgress, Never>(.empty)
    private var preferredRate: Float = 1.0
    private let logger: AppLogger

    private let metadataCollector = AVPlayerItemMetadataCollector()
    private var adRanges: [AdRange] = []
    private var adTimeObserver: Any?

    private var currentItem: AVPlayerItem?
    private var resolution: PlaybackResolution?
    private var observers: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var latencyTimer: Timer?
    private var pictureInPictureController: AVPictureInPictureController?
    private var isMuted = false
    private var preferredQualityName: String?
    private var pendingResume: PendingResume?
    private var playbackIntended = false
    private var liveLatencyConfigured = false
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

    init(logger: AppLogger = .shared) {
        self.logger = logger
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        playerView.player = player
        metadataCollector.setDelegate(self, queue: .main)
        observeAudioSession()
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
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else { return }
        playbackIntended = false
        player.pause()
    }

    func seekToLive() {
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

        let url = currentQuality?.url ?? resolution.masterPlaylistURL
        let item = AVPlayerItem(url: url)
        applyMutePreference()
        attach(item)
        player.replaceCurrentItem(with: item)
        playbackIntended = true
        player.play()
        startLatencySampling()
        logger.info("HLS load url=\(url.absoluteString) qualities=\(availableQualities.count)", category: .playback)
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

        if isAutoQuality(quality) {
            currentItem?.preferredPeakBitRate = 0
            logger.info("HLS quality -> Auto", category: .playback)
            return
        }

        if let bandwidth = quality.bandwidth, qualityBelongsToMaster(quality), !quality.isAudioOnly {
            currentItem?.preferredPeakBitRate = Double(bandwidth)
            logger.info("HLS quality -> \(quality.name) peakBitRate=\(bandwidth)", category: .playback)
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
        logger.info("HLS teardown", category: .playback)
    }

    /// Detaches or reattaches the AVPlayer from the on-screen AVPlayerLayer.
    /// Detaching while backgrounded is Apple's sanctioned way to keep audio running
    /// when the app leaves the foreground; PiP requires the layer attached, so
    /// callers must not detach while PiP is active.
    func setLayerAttached(_ attached: Bool) {
        let target: AVPlayer? = attached ? player : nil
        guard playerView.player !== target else { return }
        playerView.player = target
        logger.info("HLS layer \(attached ? "attached" : "detached")", category: .playback)
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
        logger.info("HLS audio-only variant applied", category: .playback)
    }

    private func restoreMasterPlaylist() {
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
        logger.info("HLS restore master after audio-only", category: .playback)
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
        get { pictureInPictureController?.delegate }
        set { pictureInPictureController?.delegate = newValue }
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
        logger.info("HLS quality swap variant -> \(quality.name) url=\(quality.url.absoluteString)", category: .playback)
    }

    private func attach(_ item: AVPlayerItem) {
        detachObservers()
        currentItem = item
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
            logger.error("HLS item failed: \(message)", category: .playback)
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
        logger.error("HLS failed to play to end: \(message)", category: .playback)
    }

    private func parseMasterIfNeeded(_ item: AVPlayerItem) {
        guard let url = resolution?.masterPlaylistURL else { return }
        let generation = loadGeneration
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let text = String(data: data, encoding: .utf8) else { return }
            let parsed = HLSPlaylistParser.qualities(text)
            guard !parsed.isEmpty, let self, self.loadGeneration == generation else { return }
            self.availableQualities = parsed
            self.logger.info("HLS parsed master qualities=\(parsed.count)", category: .playback)
            self.applyAudioOnlyVariantIfAvailable()
        }
    }

    private func startLatencySampling() {
        latencyTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleLatency() }
        }
        RunLoop.main.add(timer, forMode: .common)
        latencyTimer = timer
    }

    private func sampleLatency() {
        guard let item = currentItem else {
            latencySubject.send(nil)
            return
        }
        let offset = item.recommendedTimeOffsetFromLive
        guard offset.isValid, offset.isNumeric, offset.seconds > 0 else {
            latencySubject.send(nil)
            return
        }
        latencySubject.send(offset.seconds)
    }

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

    private func configurePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.info("HLS PiP unsupported on device", category: .playback)
            return
        }
        pictureInPictureController = AVPictureInPictureController(playerLayer: playerView.playerLayer)
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true
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
            logger.warn("HLS audio session activate failed: \(error.localizedDescription)", category: .playback)
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
                self.logger.info("HLS metadata labels=\(labels) adRanges=\(ranges.count)", category: .playback)
            }
            self.adRanges = ranges
            self.evaluateAdBreak()
        }
    }
}
