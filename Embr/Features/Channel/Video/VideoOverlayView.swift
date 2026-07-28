import AVKit
import UIKit

@MainActor
protocol VideoOverlayViewDelegate: AnyObject {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView)
    func videoOverlayDidTapPlayPause(_ overlay: VideoOverlayView)
    func videoOverlayDidTapQuality(_ overlay: VideoOverlayView, from sourceView: UIView)
    func videoOverlayDidTapPictureInPicture(_ overlay: VideoOverlayView)
    func videoOverlayDidTapRetry(_ overlay: VideoOverlayView)
    func videoOverlayDidTapMute(_ overlay: VideoOverlayView)
    func videoOverlayDidTapFullscreen(_ overlay: VideoOverlayView)
    func videoOverlayDidTapAdInfo(_ overlay: VideoOverlayView)
    func videoOverlayDidTapSpeed(_ overlay: VideoOverlayView, from sourceView: UIView)
    func videoOverlayDidBeginScrubbing(_ overlay: VideoOverlayView)
    func videoOverlay(_ overlay: VideoOverlayView, didCommitScrubTo seconds: TimeInterval)
    func videoOverlay(_ overlay: VideoOverlayView, didDoubleTapForward forward: Bool)
}

@MainActor
final class VideoOverlayView: UIView {

    weak var delegate: VideoOverlayViewDelegate?

    private let autoHideInterval: TimeInterval = 5.0
    private var hideTimer: Timer?
    private(set) var controlsVisible = true
    private var isBuffering = false

    private let dimmingView = UIView()
    private let topBar = UIStackView()
    private let bottomBar = UIStackView()

    private let backButton = VideoOverlayView.makeButton(symbol: "chevron.left")
    private let pipButton = VideoOverlayView.makeButton(symbol: "pip.enter")
    private let qualityButton = VideoOverlayView.makeButton(symbol: "slider.horizontal.3")
    private let muteButton = VideoOverlayView.makeButton(symbol: "speaker.wave.2.fill")
    private let fullscreenButton = VideoOverlayView.makeButton(symbol: "arrow.up.left.and.arrow.down.right")
    private let speedButton = VideoOverlayView.makeButton(symbol: "speedometer")
    private let playPauseButton = VideoOverlayView.makeButton(symbol: "pause.fill", pointSize: 34)

    private let routePicker: AVRoutePickerView = {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        picker.prioritizesVideoDevices = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    private let scrubRow = UIStackView()
    private let scrubber = UISlider()
    private let currentTimeLabel = VideoOverlayView.makeTimeLabel()
    private let durationLabel = VideoOverlayView.makeTimeLabel()
    private let seekFlashLabel = VideoOverlayView.makeFlashLabel()
    private var isScrubbing = false
    private var isSeekable = false
    private var knownDuration: TimeInterval = 0
    private var seekFlashCenterX: NSLayoutConstraint?

    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private var bufferingWork: DispatchWorkItem?
    private let bufferingDebounce: TimeInterval = 0.3

    private let reconnectPill = UIView()
    private let reconnectStack = UIStackView()
    private let reconnectSpinner = UIActivityIndicatorView(style: .medium)
    private let reconnectLabel = UILabel()
    private var isReconnecting = false

    private let errorStack = UIStackView()
    private let errorIcon = UIImageView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var errorActive = false
    private var noticeGeneration = 0

    private let adCover = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let adStatusLabel = UILabel()
    private let adInfoButton = UIButton(type: .system)
    private let adBottomStack = UIStackView()
    private let adGameView = AdBreakGameView()

    private let latencyLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .right
        label.text = nil
        return label
    }()

    private let liveBadge: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let imageView = UIImageView(image: UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: config))
        imageView.tintColor = .systemRed
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private var isLive = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildHierarchy()
        configureActions()
        scheduleAutoHide()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setPlaying(_ playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        playPauseButton.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        playPauseButton.accessibilityLabel = playing ? String(localized: "Pause") : (isLive ? String(localized: "Go to live") : String(localized: "Play"))
        applyLiveBadge(playing: playing)
    }

    private func applyLiveBadge(playing: Bool) {
        guard isLive else {
            liveBadge.isHidden = true
            liveBadge.removeAllSymbolEffects()
            return
        }
        liveBadge.isHidden = false
        if playing {
            liveBadge.tintColor = .systemRed
            liveBadge.accessibilityLabel = String(localized: "Live")
            if !Motion.reduced {
                liveBadge.addSymbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                liveBadge.removeAllSymbolEffects()
            }
        } else {
            liveBadge.removeAllSymbolEffects()
            liveBadge.tintColor = UIColor.white.withAlphaComponent(0.5)
            liveBadge.accessibilityLabel = String(localized: "Paused — tap play to return to live")
        }
    }

    func setLive(_ live: Bool) {
        isLive = live
        if !live {
            liveBadge.isHidden = true
            liveBadge.removeAllSymbolEffects()
            latencyLabel.text = nil
        }
    }

    func setBuffering(_ buffering: Bool) {
        let target = buffering && !errorActive
        bufferingWork?.cancel()
        bufferingWork = nil
        if target {
            guard !isBuffering else { return }
            let work = DispatchWorkItem { [weak self] in self?.applyBuffering(true) }
            bufferingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + bufferingDebounce, execute: work)
        } else {
            applyBuffering(false)
        }
    }

    private func applyBuffering(_ on: Bool) {
        guard on != isBuffering else { return }
        isBuffering = on
        if on, !isReconnecting {
            bufferingIndicator.startAnimating()
        } else {
            bufferingIndicator.stopAnimating()
        }
        UIView.animate(withDuration: 0.2) { self.applyCenterButtonVisibility() }
    }

    func setReconnecting(_ visible: Bool) {
        guard visible != isReconnecting else { return }
        isReconnecting = visible
        if visible {
            reconnectSpinner.startAnimating()
            bufferingIndicator.stopAnimating()
            reconnectPill.isHidden = false
            reconnectPill.alpha = 0
            UIView.animate(withDuration: 0.2) { self.reconnectPill.alpha = 1 }
        } else {
            reconnectSpinner.stopAnimating()
            if isBuffering, !errorActive { bufferingIndicator.startAnimating() }
            UIView.animate(withDuration: 0.2, animations: { self.reconnectPill.alpha = 0 }) { finished in
                if finished, self.reconnectPill.alpha < 0.01 { self.reconnectPill.isHidden = true }
            }
        }
    }

    private func applyCenterButtonVisibility() {
        let visible = controlsVisible && !isBuffering && !errorActive
        playPauseButton.alpha = visible ? 1.0 : 0.0
        playPauseButton.isUserInteractionEnabled = visible
    }

    func showError(_ message: String, symbol: String, canRetry: Bool, actionTitle: String = String(localized: "Try Again"), tint: UIColor = .systemOrange) {
        presentNotice(message: message, symbol: symbol, tint: tint, actionTitle: canRetry ? actionTitle : nil)
    }

    func showEnded(_ message: String, symbol: String) {
        presentNotice(message: message, symbol: symbol, tint: UIColor.white.withAlphaComponent(0.85), actionTitle: String(localized: "Try Again"))
    }

    private func presentNotice(message: String, symbol: String, tint: UIColor, actionTitle: String?) {
        errorActive = true
        setBuffering(false)
        setReconnecting(false)
        errorIcon.tintColor = tint
        errorIcon.image = UIImage(systemName: symbol)
        errorLabel.text = message
        if let actionTitle {
            var config = retryButton.configuration ?? .tinted()
            config.title = actionTitle
            retryButton.configuration = config
            retryButton.isHidden = false
        } else {
            retryButton.isHidden = true
        }
        noticeGeneration += 1
        errorStack.layer.removeAllAnimations()
        errorStack.isHidden = false
        if errorStack.alpha < 1 {
            UIView.animate(withDuration: 0.22) { self.errorStack.alpha = 1 }
        }
        cancelAutoHide()
        setControls(visible: true, animated: true)
    }

    func clearError() {
        guard errorActive else { return }
        errorActive = false
        noticeGeneration += 1
        let generation = noticeGeneration
        UIView.animate(withDuration: 0.2, animations: { self.errorStack.alpha = 0 }) { finished in
            guard finished, !self.errorActive, generation == self.noticeGeneration else { return }
            self.errorStack.isHidden = true
        }
        applyCenterButtonVisibility()
    }

    func setLatency(_ latency: TimeInterval?) {
        guard isLive, let latency, latency > 0 else {
            latencyLabel.text = nil
            return
        }
        latencyLabel.text = String(format: "%.1fs", latency)
    }

    func setPictureInPictureEnabled(_ enabled: Bool) {
        pipButton.isEnabled = enabled
        pipButton.alpha = enabled ? 1.0 : 0.4
    }

    func setPictureInPictureActive(_ active: Bool) {
        let symbol = active ? "pip.exit" : "pip.enter"
        pipButton.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        pipButton.accessibilityLabel = active ? String(localized: "Exit Picture in Picture") : String(localized: "Picture in Picture")
    }

    func setAirPlayHidden(_ hidden: Bool) {
        routePicker.isHidden = hidden
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButton.isHidden = hidden
    }

    func updateAdCountdown(_ remaining: TimeInterval?) {
        guard let remaining else {
            setAdCoverVisible(false)
            return
        }
        let seconds = max(1, Int(remaining.rounded(.up)))
        let wasShowing = !adCover.isHidden && adCover.alpha > 0.01
        adStatusLabel.text = String(localized: "Ad break · stream resumes in \(seconds)s")
        setAdCoverVisible(true)
        bringSubviewToFront(adCover)
        bringSubviewToFront(topBar)
        if !wasShowing {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Ad break. Tap to play Embr Flyer while the stream resumes."))
        }
    }

    private func setAdCoverVisible(_ visible: Bool) {
        if visible {
            if adCover.isHidden {
                adCover.alpha = 0
                adCover.isHidden = false
                adGameView.activate()
            }
            UIView.animate(withDuration: 0.3) { self.adCover.alpha = 1 }
        } else {
            adGameView.deactivate()
            guard !adCover.isHidden else { return }
            UIView.animate(withDuration: 0.3, animations: { self.adCover.alpha = 0 }) { finished in
                if finished, self.adCover.alpha < 0.01 { self.adCover.isHidden = true }
            }
        }
    }

    func showControls(thenHide: Bool = true) {
        setControls(visible: true, animated: true)
        if thenHide { scheduleAutoHide() }
    }

    func hideControls() {
        setControls(visible: false, animated: true)
        cancelAutoHide()
    }

    func toggleControls() {
        if controlsVisible {
            hideControls()
        } else {
            showControls()
        }
    }

    private func setControls(visible: Bool, animated: Bool) {
        controlsVisible = visible
        let target: CGFloat = visible ? 1.0 : 0.0
        let work = {
            self.dimmingView.alpha = target
            self.topBar.alpha = target
            self.bottomBar.alpha = target
            self.scrubRow.alpha = self.isSeekable ? target : 0
            self.applyCenterButtonVisibility()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: work)
        } else {
            work()
        }
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        let timer = Timer(timeInterval: autoHideInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideControls() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func cancelAutoHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func buildHierarchy() {
        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimmingView)

        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 12
        topBar.translatesAutoresizingMaskIntoConstraints = false
        let topSpacer = UIView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topBar.addArrangedSubview(backButton)
        topBar.addArrangedSubview(liveBadge)
        topBar.addArrangedSubview(topSpacer)
        topBar.addArrangedSubview(latencyLabel)
        addSubview(topBar)

        scrubber.minimumTrackTintColor = .systemRed
        scrubber.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        scrubber.setThumbImage(Self.thumbImage(diameter: 12), for: .normal)
        scrubber.setThumbImage(Self.thumbImage(diameter: 18), for: .highlighted)
        scrubber.isContinuous = true

        scrubRow.axis = .horizontal
        scrubRow.alignment = .center
        scrubRow.spacing = 10
        scrubRow.translatesAutoresizingMaskIntoConstraints = false
        scrubRow.addArrangedSubview(currentTimeLabel)
        scrubRow.addArrangedSubview(scrubber)
        scrubRow.addArrangedSubview(durationLabel)
        scrubRow.isHidden = true
        addSubview(scrubRow)

        bottomBar.axis = .horizontal
        bottomBar.alignment = .center
        bottomBar.spacing = 16
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(bottomSpacer)
        bottomBar.addArrangedSubview(speedButton)
        bottomBar.addArrangedSubview(muteButton)
        bottomBar.addArrangedSubview(qualityButton)
        bottomBar.addArrangedSubview(routePicker)
        bottomBar.addArrangedSubview(pipButton)
        bottomBar.addArrangedSubview(fullscreenButton)
        speedButton.isHidden = true
        addSubview(bottomBar)

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playPauseButton)

        seekFlashLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(seekFlashLabel)

        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        bufferingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bufferingIndicator)

        errorIcon.contentMode = .scaleAspectFit
        errorIcon.tintColor = .white
        errorIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        errorLabel.font = .systemFont(ofSize: 15, weight: .medium)
        errorLabel.textColor = .white
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        var retryConfig = UIButton.Configuration.tinted()
        retryConfig.title = String(localized: "Retry")
        retryConfig.cornerStyle = .large
        retryConfig.baseForegroundColor = .white
        retryButton.configuration = retryConfig
        retryButton.addTarget(self, action: #selector(didTapRetry), for: .touchUpInside)
        errorStack.axis = .vertical
        errorStack.alignment = .center
        errorStack.spacing = 12
        errorStack.isHidden = true
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorStack.addArrangedSubview(errorIcon)
        errorStack.addArrangedSubview(errorLabel)
        errorStack.addArrangedSubview(retryButton)
        addSubview(errorStack)

        buildReconnectPill()
        buildAdCover()

        NSLayoutConstraint.activate([
            reconnectPill.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 52),
            reconnectPill.centerXAnchor.constraint(equalTo: centerXAnchor),
            reconnectStack.topAnchor.constraint(equalTo: reconnectPill.topAnchor),
            reconnectStack.bottomAnchor.constraint(equalTo: reconnectPill.bottomAnchor),
            reconnectStack.leadingAnchor.constraint(equalTo: reconnectPill.leadingAnchor),
            reconnectStack.trailingAnchor.constraint(equalTo: reconnectPill.trailingAnchor),

            errorStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            adCover.topAnchor.constraint(equalTo: topAnchor),
            adCover.leadingAnchor.constraint(equalTo: leadingAnchor),
            adCover.trailingAnchor.constraint(equalTo: trailingAnchor),
            adCover.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),

            bottomBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bottomBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            bottomBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),

            scrubRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 14),
            scrubRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -14),
            scrubRow.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -2),

            seekFlashLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            seekFlashLabel.widthAnchor.constraint(equalToConstant: 72),
            seekFlashLabel.heightAnchor.constraint(equalToConstant: 44),

            playPauseButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            bufferingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            bufferingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            liveBadge.widthAnchor.constraint(equalToConstant: 22),
            liveBadge.heightAnchor.constraint(equalToConstant: 22),

            routePicker.widthAnchor.constraint(equalToConstant: 36),
            routePicker.heightAnchor.constraint(equalToConstant: 36)
        ])

        let flashCenter = seekFlashLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        flashCenter.isActive = true
        seekFlashCenterX = flashCenter
    }

    private static func thumbImage(diameter: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        }
    }

    private func buildReconnectPill() {
        reconnectPill.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        reconnectPill.layer.cornerRadius = 16
        reconnectPill.layer.cornerCurve = .continuous
        reconnectPill.translatesAutoresizingMaskIntoConstraints = false
        reconnectPill.isHidden = true
        addSubview(reconnectPill)

        reconnectSpinner.color = .white
        reconnectSpinner.hidesWhenStopped = false
        reconnectLabel.text = String(localized: "Reconnecting…")
        reconnectLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        reconnectLabel.textColor = .white
        reconnectStack.axis = .horizontal
        reconnectStack.alignment = .center
        reconnectStack.spacing = 8
        reconnectStack.isLayoutMarginsRelativeArrangement = true
        reconnectStack.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 16)
        reconnectStack.translatesAutoresizingMaskIntoConstraints = false
        reconnectStack.addArrangedSubview(reconnectSpinner)
        reconnectStack.addArrangedSubview(reconnectLabel)
        reconnectPill.addSubview(reconnectStack)
        reconnectPill.isAccessibilityElement = true
        reconnectPill.accessibilityLabel = String(localized: "Reconnecting")
    }

    private func buildAdCover() {
        adCover.translatesAutoresizingMaskIntoConstraints = false
        adCover.isHidden = true
        adCover.isUserInteractionEnabled = true
        addSubview(adCover)

        adGameView.translatesAutoresizingMaskIntoConstraints = false
        adCover.contentView.addSubview(adGameView)

        adStatusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        adStatusLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        adStatusLabel.textAlignment = .center
        adStatusLabel.numberOfLines = 1
        adStatusLabel.layer.shadowColor = UIColor.black.cgColor
        adStatusLabel.layer.shadowRadius = 4
        adStatusLabel.layer.shadowOpacity = 0.5
        adStatusLabel.layer.shadowOffset = .zero

        var infoConfig = UIButton.Configuration.gray()
        infoConfig.cornerStyle = .capsule
        infoConfig.image = UIImage(systemName: "info.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        infoConfig.imagePadding = 5
        infoConfig.baseForegroundColor = .white
        infoConfig.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        var infoTitle = AttributedString(String(localized: "Why am I seeing ads?"))
        infoTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        infoConfig.attributedTitle = infoTitle
        adInfoButton.configuration = infoConfig
        adInfoButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.videoOverlayDidTapAdInfo(self)
        }, for: .touchUpInside)

        adBottomStack.addArrangedSubview(adStatusLabel)
        adBottomStack.addArrangedSubview(adInfoButton)
        adBottomStack.axis = .vertical
        adBottomStack.alignment = .center
        adBottomStack.spacing = 8
        adBottomStack.translatesAutoresizingMaskIntoConstraints = false
        adCover.contentView.addSubview(adBottomStack)

        adGameView.onActiveChanged = { [weak self] playing in
            self?.setAdChromeVisible(!playing)
        }

        NSLayoutConstraint.activate([
            adGameView.topAnchor.constraint(equalTo: adCover.contentView.topAnchor),
            adGameView.leadingAnchor.constraint(equalTo: adCover.contentView.leadingAnchor),
            adGameView.trailingAnchor.constraint(equalTo: adCover.contentView.trailingAnchor),
            adGameView.bottomAnchor.constraint(equalTo: adCover.contentView.bottomAnchor),

            adBottomStack.centerXAnchor.constraint(equalTo: adCover.contentView.centerXAnchor),
            adBottomStack.leadingAnchor.constraint(greaterThanOrEqualTo: adCover.contentView.leadingAnchor, constant: 16),
            adBottomStack.trailingAnchor.constraint(lessThanOrEqualTo: adCover.contentView.trailingAnchor, constant: -16),
            adBottomStack.bottomAnchor.constraint(equalTo: adCover.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    private func setAdChromeVisible(_ visible: Bool) {
        adBottomStack.isUserInteractionEnabled = visible
        if visible {
            adBottomStack.isHidden = false
            UIView.animate(withDuration: 0.2) { self.adBottomStack.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.2, animations: { self.adBottomStack.alpha = 0 }) { finished in
                if finished, self.adBottomStack.alpha < 0.01 { self.adBottomStack.isHidden = true }
            }
        }
    }

    private func configureActions() {
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(didTapPlayPause), for: .touchUpInside)
        qualityButton.addTarget(self, action: #selector(didTapQuality), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(didTapPip), for: .touchUpInside)
        muteButton.addTarget(self, action: #selector(didTapMute), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(didTapFullscreen), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(didTapSpeed), for: .touchUpInside)
        scrubber.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        scrubber.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)
        scrubber.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        backButton.accessibilityLabel = String(localized: "Back")
        playPauseButton.accessibilityLabel = String(localized: "Play")
        qualityButton.accessibilityLabel = String(localized: "Quality")
        pipButton.accessibilityLabel = String(localized: "Picture in Picture")
        muteButton.accessibilityLabel = String(localized: "Mute")
        fullscreenButton.accessibilityLabel = String(localized: "Fullscreen")
        speedButton.accessibilityLabel = String(localized: "Playback Speed")
        liveBadge.isAccessibilityElement = true
        liveBadge.accessibilityLabel = String(localized: "Live")

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        tap.delegate = self
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(tap)
        tap.require(toFail: doubleTap)
    }

    @objc private func didTapBackground() {
        toggleControls()
    }

    @objc private func didDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let forward = recognizer.location(in: self).x > bounds.midX
        delegate?.videoOverlay(self, didDoubleTapForward: forward)
    }

    @objc private func didTapBack() {
        delegate?.videoOverlayDidTapBack(self)
    }

    @objc private func didTapPlayPause() {
        scheduleAutoHide()
        delegate?.videoOverlayDidTapPlayPause(self)
    }

    @objc private func didTapQuality() {
        scheduleAutoHide()
        delegate?.videoOverlayDidTapQuality(self, from: qualityButton)
    }

    @objc private func didTapPip() {
        delegate?.videoOverlayDidTapPictureInPicture(self)
    }

    @objc private func didTapRetry() {
        delegate?.videoOverlayDidTapRetry(self)
    }

    @objc private func didTapMute() {
        scheduleAutoHide()
        delegate?.videoOverlayDidTapMute(self)
    }

    @objc private func didTapFullscreen() {
        scheduleAutoHide()
        delegate?.videoOverlayDidTapFullscreen(self)
    }

    @objc private func didTapSpeed() {
        scheduleAutoHide()
        delegate?.videoOverlayDidTapSpeed(self, from: speedButton)
    }

    @objc private func scrubBegan() {
        isScrubbing = true
        cancelAutoHide()
        delegate?.videoOverlayDidBeginScrubbing(self)
    }

    @objc private func scrubChanged() {
        currentTimeLabel.text = Self.formatTime(TimeInterval(scrubber.value) * knownDuration)
    }

    @objc private func scrubEnded() {
        isScrubbing = false
        if knownDuration > 0 {
            delegate?.videoOverlay(self, didCommitScrubTo: TimeInterval(scrubber.value) * knownDuration)
        }
        scheduleAutoHide()
    }

    func isScrubberTouch(_ touch: UITouch) -> Bool {
        guard !scrubRow.isHidden, let touched = touch.view else { return false }
        return touched === scrubber || touched.isDescendant(of: scrubRow)
    }

    func setSeekable(_ seekable: Bool) {
        isSeekable = seekable
        scrubRow.isHidden = !seekable
        speedButton.isHidden = !seekable
    }

    func setProgress(_ progress: PlaybackProgress) {
        guard isSeekable, !isScrubbing else { return }
        knownDuration = progress.duration
        scrubber.isEnabled = progress.duration > 0
        durationLabel.text = Self.formatTime(progress.duration)
        currentTimeLabel.text = Self.formatTime(progress.current)
        if progress.duration > 0 {
            scrubber.value = Float(min(1, max(0, progress.current / progress.duration)))
        }
    }

    func setFullscreen(_ fullscreen: Bool) {
        let symbol = fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fullscreenButton.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
    }

    func setSpeed(_ text: String?) {
        var config = speedButton.configuration ?? .plain()
        config.title = text
        config.attributedTitle = text.map {
            var attr = AttributedString($0)
            attr.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            return attr
        }
        config.imagePadding = 3
        speedButton.configuration = config
    }

    func flashSeek(seconds: Int, forward: Bool) {
        seekFlashLabel.text = (forward ? "+" : "−") + "\(seconds)s"
        seekFlashCenterX?.constant = (forward ? 1 : -1) * bounds.width * 0.28
        seekFlashLabel.layer.removeAllAnimations()
        seekFlashLabel.alpha = 1
        UIView.animate(withDuration: 0.45, delay: 0.2, options: [.curveEaseOut]) {
            self.seekFlashLabel.alpha = 0
        }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func setMuted(_ muted: Bool) {
        let symbol = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        muteButton.accessibilityLabel = muted ? String(localized: "Unmute") : String(localized: "Mute")
    }

    private static func makeTimeLabel() -> UILabel {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.text = "0:00"
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private static func makeFlashLabel() -> UILabel {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 22
        label.layer.masksToBounds = true
        label.alpha = 0
        return label
    }

    private static func makeButton(symbol: String, pointSize: CGFloat = 18) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        )
        configuration.baseForegroundColor = .white
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    isolated deinit {
        hideTimer?.invalidate()
        bufferingWork?.cancel()
    }
}

extension VideoOverlayView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !adCover.isHidden else { return true }
        return !adCover.bounds.contains(touch.location(in: adCover))
    }
}
