import AVFoundation
import UIKit
import EmbrCore

@MainActor
protocol ClipFeedCellDelegate: AnyObject {
    func clipCellDidTogglePlayback(_ cell: ClipFeedCell)
    func clipCellDidTapShare(_ cell: ClipFeedCell, clip: Clip)
    func clipCellDidTapMore(_ cell: ClipFeedCell, clip: Clip)
    func clipCellDidRequestRetry(_ cell: ClipFeedCell, clip: Clip)
    func clipCell(_ cell: ClipFeedCell, didScrubTo fraction: Double, clip: Clip)
    func clipCell(_ cell: ClipFeedCell, scrollBy direction: UIAccessibilityScrollDirection) -> Bool
}

/// One clip filling the screen: the video fitted to the width over a blurred, enlarged copy of its thumbnail, the
/// thumbnail itself until the first frame is ready, and what the clip is along the bottom with a progress line that
/// can be dragged.
@MainActor
final class ClipFeedCell: UICollectionViewCell {
    static let reuseIdentifier = "ClipFeedCell"

    weak var delegate: ClipFeedCellDelegate?
    private(set) var clip: Clip?

    private let backdrop = UIImageView()
    private let backdropBlur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let playerView = ClipPlayerView()
    private let poster = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let pauseGlyph = UIImageView(image: UIImage(systemName: "play.fill"))
    private let topShade = GradientView(colors: [UIColor.black.withAlphaComponent(0.55), .clear])
    private let bottomShade = GradientView(colors: [.clear, UIColor.black.withAlphaComponent(0.75)])
    private let channelLabel = UILabel()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let shareButton = ClipRailButton(symbol: "square.and.arrow.up", title: String(localized: "Share", comment: "Clip feed button"))
    private let moreButton = ClipRailButton(symbol: "ellipsis", title: String(localized: "More", comment: "Clip feed button"))
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(configuration: .filled())
    private var progressFillWidth: NSLayoutConstraint!
    private var readyObservation: NSKeyValueObservation?
    private var posterTask: Task<Void, Never>?
    private var fraction: Double = 0
    private var scrubbing = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.clipsToBounds = true
        buildViews()
        buildGestures()
        isAccessibilityElement = true
        accessibilityTraits = [.startsMediaSession]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        posterTask?.cancel()
        posterTask = nil
        attach(nil)
        clip = nil
        poster.image = nil
        backdrop.image = nil
        poster.alpha = 1
        setProgress(0)
        showError(false)
        showPaused(false, animated: false)
    }

    /// Shows `clip`. A title the viewer's content filter would hide in chat is replaced by a note, and the clip still plays.
    func configure(with clip: Clip, images: ImageLoading, hidesTitle: Bool) {
        self.clip = clip
        channelLabel.text = clip.broadcasterName
        titleLabel.text = hidesTitle ? String(localized: "Title hidden by your content filter", comment: "Clip feed, filtered title") : clip.title
        metaLabel.text = [
            String(localized: "Clipped by \(clip.creatorName)", comment: "Clip feed, who made the clip"),
            MediaRowCell.views(clip.viewCount),
            MediaRowCell.relative(clip.createdAt),
        ].joined(separator: "  ·  ")
        accessibilityLabel = "\(clip.broadcasterName), \(titleLabel.text ?? "")"
        accessibilityValue = metaLabel.text
        accessibilityHint = String(localized: "Double-tap to pause or play. Swipe up with three fingers for the next clip.", comment: "VoiceOver hint in the clip feed")
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: String(localized: "Share", comment: "Clip feed button")) { [weak self] _ in
                guard let self, let clip = self.clip else { return false }
                self.delegate?.clipCellDidTapShare(self, clip: clip)
                return true
            },
            UIAccessibilityCustomAction(name: String(localized: "More", comment: "Clip feed button")) { [weak self] _ in
                guard let self, let clip = self.clip else { return false }
                self.delegate?.clipCellDidTapMore(self, clip: clip)
                return true
            },
        ]
        spinner.startAnimating()
        guard let url = clip.thumbnailURL else { return }
        if let cached = images.cachedImage(for: url) {
            poster.image = cached
            backdrop.image = cached
            return
        }
        posterTask = Task { [weak self] in
            let image = await images.image(for: url, targetScale: 1)
            guard !Task.isCancelled, let self, self.clip?.id == clip.id else { return }
            self.poster.image = image
            self.backdrop.image = image
        }
    }

    /// Puts a player on screen, or takes it off with nil. The thumbnail stays until the player has a frame to show.
    func attach(_ player: AVPlayer?) {
        readyObservation?.invalidate()
        readyObservation = nil
        playerView.playerLayer.player = player
        guard player != nil else {
            poster.alpha = 1
            return
        }
        readyObservation = playerView.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor in self?.showReady(ready) }
        }
    }

    var hasPlayer: Bool { playerView.playerLayer.player != nil }

    func setProgress(_ value: Double) {
        guard !scrubbing else { return }
        applyProgress(value)
    }

    func showPaused(_ paused: Bool, animated: Bool) {
        let change = { self.pauseGlyph.alpha = paused ? 1 : 0 }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            pauseGlyph.transform = paused ? CGAffineTransform(scaleX: 1.3, y: 1.3) : .identity
            UIView.animate(withDuration: 0.18) {
                change()
                self.pauseGlyph.transform = .identity
            }
        } else {
            change()
        }
        accessibilityTraits = paused ? [.startsMediaSession] : [.startsMediaSession, .updatesFrequently]
    }

    func showError(_ visible: Bool) {
        errorLabel.isHidden = !visible
        retryButton.isHidden = !visible
        if visible { spinner.stopAnimating() }
    }

    override func accessibilityActivate() -> Bool {
        delegate?.clipCellDidTogglePlayback(self)
        return true
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        delegate?.clipCell(self, scrollBy: direction) ?? false
    }

    private func showReady(_ ready: Bool) {
        if ready { spinner.stopAnimating() }
        UIView.animate(withDuration: ready ? 0.15 : 0) {
            self.poster.alpha = ready ? 0 : 1
        }
    }

    private func applyProgress(_ value: Double) {
        fraction = min(max(value, 0), 1)
        progressFillWidth.constant = progressTrack.bounds.width * fraction
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        progressFillWidth.constant = progressTrack.bounds.width * fraction
    }

    private func buildViews() {
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        poster.contentMode = .scaleAspectFit
        playerView.playerLayer.videoGravity = .resizeAspect
        spinner.color = .white
        spinner.hidesWhenStopped = true
        pauseGlyph.tintColor = UIColor.white.withAlphaComponent(0.9)
        pauseGlyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .bold)
        pauseGlyph.alpha = 0
        pauseGlyph.layer.shadowColor = UIColor.black.cgColor
        pauseGlyph.layer.shadowOpacity = 0.4
        pauseGlyph.layer.shadowRadius = 12

        channelLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .bold))
        channelLabel.adjustsFontForContentSizeCategory = true
        channelLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 3
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        metaLabel.numberOfLines = 2
        [channelLabel, titleLabel, metaLabel].forEach {
            $0.layer.shadowColor = UIColor.black.cgColor
            $0.layer.shadowOpacity = 0.35
            $0.layer.shadowRadius = 4
            $0.layer.shadowOffset = .zero
        }

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        progressTrack.layer.cornerRadius = 1.5
        progressFill.backgroundColor = .white
        progressFill.layer.cornerRadius = 1.5

        errorLabel.text = String(localized: "This clip can't be played right now.", comment: "Clip feed error")
        errorLabel.textColor = .white
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        retryButton.configuration?.title = String(localized: "Try Again", comment: "Clip feed retry button")
        retryButton.configuration?.baseBackgroundColor = UIColor.white.withAlphaComponent(0.2)
        retryButton.configuration?.cornerStyle = .capsule
        retryButton.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.clip else { return }
            self.showError(false)
            self.spinner.startAnimating()
            self.delegate?.clipCellDidRequestRetry(self, clip: clip)
        }, for: .primaryActionTriggered)
        showError(false)

        shareButton.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.clip else { return }
            self.delegate?.clipCellDidTapShare(self, clip: clip)
        }, for: .touchUpInside)
        moreButton.addAction(UIAction { [weak self] _ in
            guard let self, let clip = self.clip else { return }
            self.delegate?.clipCellDidTapMore(self, clip: clip)
        }, for: .touchUpInside)

        let info = UIStackView(arrangedSubviews: [channelLabel, titleLabel, metaLabel])
        info.axis = .vertical
        info.spacing = 4
        let rail = UIStackView(arrangedSubviews: [shareButton, moreButton])
        rail.axis = .vertical
        rail.spacing = 18
        rail.alignment = .center
        let errorStack = UIStackView(arrangedSubviews: [errorLabel, retryButton])
        errorStack.axis = .vertical
        errorStack.spacing = 14
        errorStack.alignment = .center

        let all: [UIView] = [backdrop, backdropBlur, playerView, poster, topShade, bottomShade, spinner, pauseGlyph, info, rail, progressTrack, errorStack]
        all.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        progressFillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)

        let guide = contentView.safeAreaLayoutGuide
        let readable = contentView.readableContentGuide
        NSLayoutConstraint.activate(
            [backdrop, backdropBlur, playerView, poster].flatMap { view in
                [
                    view.topAnchor.constraint(equalTo: contentView.topAnchor),
                    view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                    view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                ]
            } + [
                topShade.topAnchor.constraint(equalTo: contentView.topAnchor),
                topShade.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                topShade.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                topShade.heightAnchor.constraint(equalToConstant: 140),
                bottomShade.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                bottomShade.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                bottomShade.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                bottomShade.topAnchor.constraint(equalTo: info.topAnchor, constant: -80),
                spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                pauseGlyph.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                pauseGlyph.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                errorStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                errorStack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
                errorStack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
                progressTrack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
                progressTrack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
                progressTrack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -10),
                progressTrack.heightAnchor.constraint(equalToConstant: 3),
                progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
                progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
                progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
                progressFillWidth,
                info.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
                info.trailingAnchor.constraint(equalTo: rail.leadingAnchor, constant: -16),
                info.bottomAnchor.constraint(equalTo: progressTrack.topAnchor, constant: -18),
                rail.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
                rail.bottomAnchor.constraint(equalTo: info.bottomAnchor),
            ]
        )
    }

    private func buildGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        contentView.addGestureRecognizer(tap)
        let scrub = UIPanGestureRecognizer(target: self, action: #selector(scrubbed(_:)))
        let scrubArea = UIView()
        scrubArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrubArea)
        NSLayoutConstraint.activate([
            scrubArea.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            scrubArea.trailingAnchor.constraint(equalTo: progressTrack.trailingAnchor),
            scrubArea.centerYAnchor.constraint(equalTo: progressTrack.centerYAnchor),
            scrubArea.heightAnchor.constraint(equalToConstant: 36),
        ])
        scrubArea.addGestureRecognizer(scrub)
        tap.require(toFail: scrub)
    }

    @objc private func tapped() {
        delegate?.clipCellDidTogglePlayback(self)
    }

    @objc private func scrubbed(_ gesture: UIPanGestureRecognizer) {
        guard let clip, progressTrack.bounds.width > 0 else { return }
        let x = gesture.location(in: progressTrack).x
        let value = Double(x / progressTrack.bounds.width)
        switch gesture.state {
        case .began:
            scrubbing = true
            Haptics.selection()
            animateTrack(expanded: true)
            applyProgress(value)
        case .changed:
            applyProgress(value)
            delegate?.clipCell(self, didScrubTo: fraction, clip: clip)
        case .ended, .cancelled, .failed:
            delegate?.clipCell(self, didScrubTo: fraction, clip: clip)
            scrubbing = false
            animateTrack(expanded: false)
        default:
            break
        }
    }

    private func animateTrack(expanded: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.progressTrack.transform = expanded ? CGAffineTransform(scaleX: 1, y: 2.4) : .identity
        }
    }
}

/// A view whose layer is an `AVPlayerLayer`, so the video resizes with Auto Layout and animations.
final class ClipPlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else { fatalError("ClipPlayerView's layer is always an AVPlayerLayer") }
        return layer
    }
}

/// A vertical gradient that follows its view's size.
final class GradientView: UIView {
    override static var layerClass: AnyClass { CAGradientLayer.self }

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        (layer as? CAGradientLayer)?.colors = colors.map(\.cgColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// A round glass button with a caption under it, for the feed's side rail.
final class ClipRailButton: UIControl {
    private let circle = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let icon = UIImageView()
    private let caption = UILabel()

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        icon.tintColor = .white
        icon.contentMode = .center
        circle.layer.cornerRadius = 24
        circle.clipsToBounds = true
        circle.isUserInteractionEnabled = false
        caption.text = title
        caption.font = .preferredFont(forTextStyle: .caption2)
        caption.adjustsFontForContentSizeCategory = true
        caption.textColor = .white
        caption.textAlignment = .center
        caption.isUserInteractionEnabled = false
        accessibilityLabel = title
        accessibilityTraits = .button
        isAccessibilityElement = true
        [circle, icon, caption].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: 48),
            circle.heightAnchor.constraint(equalToConstant: 48),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            caption.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 4),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    /// A plain control fires only touch events, so VoiceOver's activation sends the same tap.
    override func accessibilityActivate() -> Bool {
        sendActions(for: .touchUpInside)
        return true
    }
}
