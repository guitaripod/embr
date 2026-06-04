import UIKit

@MainActor
protocol VideoOverlayViewDelegate: AnyObject {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView)
    func videoOverlayDidTapPlayPause(_ overlay: VideoOverlayView)
    func videoOverlayDidTapQuality(_ overlay: VideoOverlayView, from sourceView: UIView)
    func videoOverlayDidTapPictureInPicture(_ overlay: VideoOverlayView)
    func videoOverlayDidTapRetry(_ overlay: VideoOverlayView)
    func videoOverlayDidTapMute(_ overlay: VideoOverlayView)
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
    private let playPauseButton = VideoOverlayView.makeButton(symbol: "pause.fill", pointSize: 34)

    private let bufferingIndicator = UIActivityIndicatorView(style: .large)

    private let errorStack = UIStackView()
    private let errorIcon = UIImageView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var errorActive = false

    private let adBadge: PaddedLabel = {
        let label = PaddedLabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        label.textColor = .black
        label.backgroundColor = .systemYellow
        label.layer.cornerRadius = 6
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.isHidden = true
        return label
    }()

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
        playPauseButton.accessibilityLabel = playing ? "Pause" : "Play"
        liveBadge.isHidden = !playing
        if playing {
            liveBadge.addSymbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            liveBadge.removeAllSymbolEffects()
        }
    }

    func setBuffering(_ buffering: Bool) {
        let target = buffering && !errorActive
        guard target != isBuffering else { return }
        isBuffering = target
        if target {
            bufferingIndicator.startAnimating()
        } else {
            bufferingIndicator.stopAnimating()
        }
        UIView.animate(withDuration: 0.2) { self.applyCenterButtonVisibility() }
    }

    private func applyCenterButtonVisibility() {
        let visible = controlsVisible && !isBuffering && !errorActive
        playPauseButton.alpha = visible ? 1.0 : 0.0
        playPauseButton.isUserInteractionEnabled = visible
    }

    func showError(_ message: String, symbol: String, canRetry: Bool) {
        errorActive = true
        setBuffering(false)
        errorIcon.image = UIImage(systemName: symbol)
        errorLabel.text = message
        retryButton.isHidden = !canRetry
        errorStack.isHidden = false
        cancelAutoHide()
        setControls(visible: true, animated: true)
    }

    func clearError() {
        guard errorActive else { return }
        errorActive = false
        errorStack.isHidden = true
        applyCenterButtonVisibility()
    }

    func setLatency(_ latency: TimeInterval?) {
        guard let latency, latency > 0 else {
            latencyLabel.text = nil
            return
        }
        latencyLabel.text = String(format: "%.1fs", latency)
    }

    func setPictureInPictureEnabled(_ enabled: Bool) {
        pipButton.isEnabled = enabled
        pipButton.alpha = enabled ? 1.0 : 0.4
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButton.isHidden = hidden
    }

    func updateAdCountdown(_ remaining: TimeInterval?) {
        guard let remaining else {
            adBadge.isHidden = true
            return
        }
        adBadge.isHidden = false
        adBadge.text = "Ad · \(Int(remaining.rounded(.up)))s"
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

        bottomBar.axis = .horizontal
        bottomBar.alignment = .center
        bottomBar.spacing = 16
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        let bottomSpacer = UIView()
        bottomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomBar.addArrangedSubview(bottomSpacer)
        bottomBar.addArrangedSubview(muteButton)
        bottomBar.addArrangedSubview(qualityButton)
        bottomBar.addArrangedSubview(pipButton)
        addSubview(bottomBar)

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playPauseButton)

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
        retryConfig.title = "Retry"
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

        adBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(adBadge)

        NSLayoutConstraint.activate([
            errorStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            adBadge.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            adBadge.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 44),
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

            playPauseButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            bufferingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            bufferingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            liveBadge.widthAnchor.constraint(equalToConstant: 22),
            liveBadge.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func configureActions() {
        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(didTapPlayPause), for: .touchUpInside)
        qualityButton.addTarget(self, action: #selector(didTapQuality), for: .touchUpInside)
        pipButton.addTarget(self, action: #selector(didTapPip), for: .touchUpInside)
        muteButton.addTarget(self, action: #selector(didTapMute), for: .touchUpInside)

        backButton.accessibilityLabel = "Back"
        playPauseButton.accessibilityLabel = "Play"
        qualityButton.accessibilityLabel = "Quality"
        pipButton.accessibilityLabel = "Picture in Picture"
        muteButton.accessibilityLabel = "Mute"
        liveBadge.isAccessibilityElement = true
        liveBadge.accessibilityLabel = "Live"

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        addGestureRecognizer(tap)
    }

    @objc private func didTapBackground() {
        toggleControls()
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

    func setMuted(_ muted: Bool) {
        let symbol = muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        muteButton.setImage(
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        muteButton.accessibilityLabel = muted ? "Unmute" : "Mute"
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
    }
}

private final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
