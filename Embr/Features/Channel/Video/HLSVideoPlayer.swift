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

    private(set) var availableQualities: [StreamQuality] = []
    private(set) var currentQuality: StreamQuality?

    private let playerView = PlayerView()
    private let player = AVPlayer()
    private let stateSubject = CurrentValueSubject<VideoState, Never>(.idle)
    private let latencySubject = CurrentValueSubject<TimeInterval?, Never>(nil)
    private let logger: AppLogger

    private var currentItem: AVPlayerItem?
    private var resolution: PlaybackResolution?
    private var observers: [NSKeyValueObservation] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var latencyTimer: Timer?
    private var pictureInPictureController: AVPictureInPictureController?
    private var isMuted = false
    private var preferredQualityName: String?

    init(logger: AppLogger = .shared) {
        self.logger = logger
        super.init()
        player.automaticallyWaitsToMinimizeStalling = true
        playerView.player = player
        configurePictureInPicture()
    }

    func load(_ resolution: PlaybackResolution) {
        self.resolution = resolution
        availableQualities = resolution.qualities
        if let saved = preferredQualityName, let match = availableQualities.first(where: { $0.name == saved }) {
            currentQuality = match
        } else {
            currentQuality = nil
        }
        configureAudioSession()
        stateSubject.send(.loading)

        let url = currentQuality?.url ?? resolution.masterPlaylistURL
        let item = AVPlayerItem(url: url)
        applyMutePreference()
        attach(item)
        player.replaceCurrentItem(with: item)
        player.play()
        startLatencySampling()
        logger.info("HLS load url=\(url.absoluteString) qualities=\(availableQualities.count)", category: .playback)
    }

    func play() {
        player.play()
    }

    func pause() {
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

        if let bandwidth = quality.bandwidth, qualityBelongsToMaster(quality) {
            currentItem?.preferredPeakBitRate = Double(bandwidth)
            logger.info("HLS quality -> \(quality.name) peakBitRate=\(bandwidth)", category: .playback)
            return
        }

        swapVariant(to: quality)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyMutePreference()
    }

    func teardown() {
        latencyTimer?.invalidate()
        latencyTimer = nil
        detachObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        pictureInPictureController = nil
        stateSubject.send(.idle)
        deactivateAudioSession()
        logger.info("HLS teardown", category: .playback)
    }

    var canStartPictureInPicture: Bool {
        pictureInPictureController?.isPictureInPicturePossible ?? false
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
        let item = AVPlayerItem(url: quality.url)
        attach(item)
        player.replaceCurrentItem(with: item)
        applyMutePreference()
        player.play()
        startLatencySampling()
        logger.info("HLS quality swap variant -> \(quality.name) url=\(quality.url.absoluteString)", category: .playback)
    }

    private func attach(_ item: AVPlayerItem) {
        detachObservers()
        currentItem = item
        item.preferredPeakBitRate = peakBitRate(for: currentQuality)

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

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.itemDidPlayToEnd(notification) }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.itemFailedToPlayToEnd(notification) }
        })
    }

    private func handleStatus() {
        guard let item = currentItem else { return }
        switch item.status {
        case .readyToPlay:
            if availableQualities.isEmpty {
                parseMasterIfNeeded(item)
            }
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

    private func itemDidPlayToEnd(_ notification: Notification) {
        guard (notification.object as? AVPlayerItem) === currentItem else { return }
        stateSubject.send(.ended)
    }

    private func itemFailedToPlayToEnd(_ notification: Notification) {
        guard (notification.object as? AVPlayerItem) === currentItem else { return }
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        let message = error?.localizedDescription ?? "Playback stalled"
        stateSubject.send(.error(message))
        logger.error("HLS failed to play to end: \(message)", category: .playback)
    }

    private func parseMasterIfNeeded(_ item: AVPlayerItem) {
        guard let url = resolution?.masterPlaylistURL else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let text = String(data: data, encoding: .utf8) else { return }
            let parsed = HLSPlaylistParser.qualities(text)
            guard !parsed.isEmpty, let self else { return }
            self.availableQualities = parsed
            self.logger.info("HLS parsed master qualities=\(parsed.count)", category: .playback)
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
        guard let quality, let resolution else { return false }
        return resolution.qualities.contains(quality)
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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            logger.warn("HLS audio session activate failed: \(error.localizedDescription)", category: .playback)
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func detachObservers() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
    }

    deinit {
        latencyTimer?.invalidate()
        observers.forEach { $0.invalidate() }
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
