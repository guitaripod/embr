import UIKit

@MainActor
protocol VideoOverlayViewDelegate: AnyObject {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView)
    func videoOverlayDidTapRetry(_ overlay: VideoOverlayView)
}

/// Thin chrome drawn over the Twitch embed webview. It only owns the app's own
/// affordances — a back button, a buffering spinner, and an error/retry state.
/// Every other touch passes straight through to Twitch's embedded player so its
/// native controls (play/pause, volume, quality, fullscreen) keep working.
@MainActor
final class VideoOverlayView: UIView {

    weak var delegate: VideoOverlayViewDelegate?

    private let topGradient = GradientView()
    private let backButton = VideoOverlayView.makeButton(symbol: "chevron.left")
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)

    private let errorStack = UIStackView()
    private let errorIcon = UIImageView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var errorActive = false
    private var isBuffering = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Lets touches outside our own controls fall through to the Twitch player webview.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    func setBuffering(_ buffering: Bool) {
        let target = buffering && !errorActive
        guard target != isBuffering else { return }
        isBuffering = target
        if target { bufferingIndicator.startAnimating() } else { bufferingIndicator.stopAnimating() }
    }

    func showError(_ message: String, symbol: String, canRetry: Bool) {
        errorActive = true
        setBuffering(false)
        errorIcon.image = UIImage(systemName: symbol)
        errorLabel.text = message
        retryButton.isHidden = !canRetry
        errorStack.isHidden = false
    }

    func clearError() {
        guard errorActive else { return }
        errorActive = false
        errorStack.isHidden = true
    }

    func setBackButtonHidden(_ hidden: Bool) {
        backButton.isHidden = hidden
        updateTopGradient()
    }

    private func updateTopGradient() {
        topGradient.isHidden = backButton.isHidden
    }

    private func buildHierarchy() {
        topGradient.translatesAutoresizingMaskIntoConstraints = false
        topGradient.isUserInteractionEnabled = false
        addSubview(topGradient)

        backButton.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        backButton.accessibilityLabel = "Back"
        addSubview(backButton)

        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        bufferingIndicator.isUserInteractionEnabled = false
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

        NSLayoutConstraint.activate([
            topGradient.topAnchor.constraint(equalTo: topAnchor),
            topGradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            topGradient.trailingAnchor.constraint(equalTo: trailingAnchor),
            topGradient.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.28),

            backButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            backButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),

            bufferingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            bufferingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            errorStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
        updateTopGradient()
    }

    @objc private func didTapBack() { delegate?.videoOverlayDidTapBack(self) }
    @objc private func didTapRetry() { delegate?.videoOverlayDidTapRetry(self) }

    private static func makeButton(symbol: String, pointSize: CGFloat = 18) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        )
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

@MainActor
private final class GradientView: UIView {
    override static var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [UIColor.black.withAlphaComponent(0.45).cgColor, UIColor.clear.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
