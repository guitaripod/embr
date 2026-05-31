import UIKit

protocol VideoOverlayViewDelegate: AnyObject {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView)
    func videoOverlayDidTapPlayPause(_ overlay: VideoOverlayView)
    func videoOverlayDidTapQuality(_ overlay: VideoOverlayView, from sourceView: UIView)
    func videoOverlayDidTapPictureInPicture(_ overlay: VideoOverlayView)
}

final class VideoOverlayView: UIView {

    weak var delegate: VideoOverlayViewDelegate?

    private let autoHideInterval: TimeInterval = 5.0
    private var hideTimer: Timer?
    private(set) var controlsVisible = true

    private let dimmingView = UIView()
    private let topBar = UIStackView()
    private let bottomBar = UIStackView()

    private let backButton = VideoOverlayView.makeButton(symbol: "chevron.left")
    private let pipButton = VideoOverlayView.makeButton(symbol: "pip.enter")
    private let qualityButton = VideoOverlayView.makeButton(symbol: "slider.horizontal.3")
    private let playPauseButton = VideoOverlayView.makeButton(symbol: "pause.fill", pointSize: 34)

    private let bufferingIndicator = UIActivityIndicatorView(style: .large)

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
        liveBadge.isHidden = !playing
        if playing {
            liveBadge.addSymbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            liveBadge.removeAllSymbolEffects()
        }
    }

    func setBuffering(_ buffering: Bool) {
        if buffering {
            bufferingIndicator.startAnimating()
        } else {
            bufferingIndicator.stopAnimating()
        }
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
            self.playPauseButton.alpha = target
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
            self?.hideControls()
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
        bottomBar.addArrangedSubview(qualityButton)
        bottomBar.addArrangedSubview(pipButton)
        addSubview(bottomBar)

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playPauseButton)

        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        bufferingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bufferingIndicator)

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

    deinit {
        hideTimer?.invalidate()
    }
}
