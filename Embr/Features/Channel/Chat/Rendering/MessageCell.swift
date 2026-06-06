import UIKit
import EmbrCore
import SDWebImage

final class MessageCell: UICollectionViewCell {
    static let reuseID = "MessageCell"

    private let textLabel = UILabel()
    private let replyPreview = ReplyPreviewView()
    private let highlightView = UIView()

    private var emoteViews: [SDAnimatedImageView] = []
    private var badgeViews: [UIImageView] = []
    private var emoteLoadTasks: [Task<Void, Never>] = []
    private var badgeLoadTasks: [Task<Void, Never>] = []
    private var registeredEmoteViews: [SDAnimatedImageView] = []

    private weak var animator: EmoteAnimator?
    private var laidOut: LaidOutMessage?
    private var message: ChatMessage?

    var onTapUser: ((ChatUser) -> Void)?
    var onTapEmote: ((Emote) -> Void)?
    var onTapLink: ((URL) -> Void)?
    var onSwipeReply: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)

        highlightView.isHidden = true
        highlightView.layer.cornerRadius = 4
        contentView.addSubview(highlightView)

        textLabel.numberOfLines = 0
        textLabel.isUserInteractionEnabled = false
        contentView.addSubview(textLabel)

        replyPreview.isHidden = true
        contentView.addSubview(replyPreview)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeReply))
        swipe.direction = .right
        contentView.addGestureRecognizer(swipe)
    }

    @objc private func handleSwipeReply() {
        guard onSwipeReply != nil else { return }
        Haptics.impact(.light)
        UIView.animate(withDuration: 0.12, animations: {
            self.contentView.transform = self.contentView.transform.concatenating(CGAffineTransform(translationX: 16, y: 0))
        }, completion: { _ in
            UIView.animate(withDuration: 0.18) {
                self.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
            }
        })
        onSwipeReply?()
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let laidOut, let message else { return }
        let point = recognizer.location(in: contentView)
        for placement in laidOut.emotePlacements where placement.frame.contains(point) {
            onTapEmote?(placement.emote)
            return
        }
        guard laidOut.textWidth > 0 else { return }
        let local = CGPoint(x: point.x - laidOut.textOrigin.x, y: point.y - laidOut.textOrigin.y)
        guard local.x >= 0, local.y >= 0 else { return }
        let storage = NSTextStorage(attributedString: laidOut.attributedText)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: laidOut.textWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        var fraction: CGFloat = 0
        let glyphIndex = manager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: &fraction)
        let charIndex = manager.characterIndexForGlyph(at: glyphIndex)
        if NSLocationInRange(charIndex, laidOut.usernameRange) {
            onTapUser?(message.author)
            return
        }
        for link in laidOut.links where NSLocationInRange(charIndex, link.range) {
            onTapLink?(link.url)
            return
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with laidOut: LaidOutMessage, message: ChatMessage, images: ImageLoading, animator: EmoteAnimator) {
        self.laidOut = laidOut
        self.message = message
        self.animator = animator

        let highlight = laidOut.mentionsCurrentUser || laidOut.isHighlighted || laidOut.isAnnouncement || laidOut.isCheer
        highlightView.isHidden = !highlight
        if laidOut.mentionsCurrentUser {
            highlightView.backgroundColor = Theme.mentionBackground
        } else if laidOut.isCheer {
            highlightView.backgroundColor = Theme.cheerHighlight
        } else {
            highlightView.backgroundColor = Theme.highlightedMessage
        }

        if message.moderation == .visible {
            textLabel.attributedText = laidOut.attributedText
            contentView.alpha = 1
        } else {
            let muted = NSMutableAttributedString(attributedString: laidOut.attributedText)
            muted.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: muted.length))
            textLabel.attributedText = muted
            contentView.alpha = 0.4
        }

        if let reply = message.reply {
            replyPreview.isHidden = false
            replyPreview.configure(with: reply)
        } else {
            replyPreview.isHidden = true
        }

        configureEmotes(laidOut.emotePlacements, images: images, animator: animator)
        configureBadges(laidOut.badgePlacements, images: images)

        setNeedsLayout()
    }

    /// An upright bitmap of the cell content for a context-menu preview, immune to the
    /// inverted (scaleY:-1) transform. `CALayer.render(in:)` ignores the layer's own
    /// transform (so contentView's flip is dropped → upright) while still drawing
    /// sublayers at their manual frames. Target a NON-flipped container at the cell's
    /// on-screen center.
    func makeUprightContextPreview(in container: UIView, center: CGPoint) -> UITargetedPreview? {
        layoutIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        for view in emoteViews where !view.isHidden {
            if view.layer.contents == nil, let cgImage = view.image?.cgImage {
                view.layer.contents = cgImage
            }
        }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { ctx in
            contentView.layer.render(in: ctx.cgContext)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = bounds
        imageView.alpha = contentView.alpha
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0), cornerRadius: 4)
        return UITargetedPreview(view: imageView, parameters: parameters, target: UIPreviewTarget(container: container, center: center))
    }

    private func configureEmotes(_ placements: [LaidOutMessage.EmotePlacement], images: ImageLoading, animator: EmoteAnimator) {
        ensureEmoteViews(count: placements.count)
        for (index, placement) in placements.enumerated() {
            let view = emoteViews[index]
            view.isHidden = false
            view.image = nil
            let emote = placement.emote
            let task = Task { [weak self, weak view, weak animator] in
                let image = await images.emoteImage(for: emote, scale: .x2)
                guard !Task.isCancelled, let view else { return }
                view.image = image
                guard emote.isAnimated, let animator else { return }
                if let url = emote.images.url(preferring: .x2) {
                    animator.register(view, url: url)
                    self?.registeredEmoteViews.append(view)
                }
            }
            emoteLoadTasks.append(task)
        }
        for index in placements.count..<emoteViews.count {
            emoteViews[index].isHidden = true
            emoteViews[index].image = nil
        }
    }

    private func configureBadges(_ placements: [LaidOutMessage.BadgePlacement], images: ImageLoading) {
        ensureBadgeViews(count: placements.count)
        for (index, placement) in placements.enumerated() {
            let view = badgeViews[index]
            view.isHidden = false
            view.image = nil
            let badge = placement.badge
            let task = Task { [weak view] in
                let image = await images.badgeImage(for: badge, scale: .x2)
                guard !Task.isCancelled, let view else { return }
                view.image = image
            }
            badgeLoadTasks.append(task)
        }
        for index in placements.count..<badgeViews.count {
            badgeViews[index].isHidden = true
            badgeViews[index].image = nil
        }
    }

    private func ensureEmoteViews(count: Int) {
        while emoteViews.count < count {
            let view = SDAnimatedImageView()
            view.contentMode = .scaleAspectFit
            view.autoPlayAnimatedImage = false
            view.isUserInteractionEnabled = false
            contentView.addSubview(view)
            emoteViews.append(view)
        }
    }

    private func ensureBadgeViews(count: Int) {
        while badgeViews.count < count {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.isUserInteractionEnabled = false
            contentView.addSubview(view)
            badgeViews.append(view)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let laidOut else { return }

        highlightView.frame = bounds.insetBy(dx: 2, dy: 0)

        if !replyPreview.isHidden {
            replyPreview.frame = CGRect(x: laidOut.textOrigin.x, y: 2, width: bounds.width - laidOut.textOrigin.x - 8, height: laidOut.replyHeight)
        }

        textLabel.frame = CGRect(
            x: laidOut.textOrigin.x,
            y: laidOut.textOrigin.y,
            width: bounds.width - laidOut.textOrigin.x - 8,
            height: laidOut.height - laidOut.textOrigin.y - 4
        )

        for (index, placement) in laidOut.emotePlacements.enumerated() where index < emoteViews.count {
            emoteViews[index].frame = placement.frame
        }
        for (index, placement) in laidOut.badgePlacements.enumerated() where index < badgeViews.count {
            badgeViews[index].frame = placement.frame
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        for task in emoteLoadTasks { task.cancel() }
        for task in badgeLoadTasks { task.cancel() }
        emoteLoadTasks.removeAll(keepingCapacity: true)
        badgeLoadTasks.removeAll(keepingCapacity: true)

        for view in registeredEmoteViews { animator?.unregister(view) }
        registeredEmoteViews.removeAll(keepingCapacity: true)

        for view in emoteViews {
            view.sd_cancelCurrentImageLoad()
            view.image = nil
            view.isHidden = true
        }
        for view in badgeViews {
            view.image = nil
            view.isHidden = true
        }
        textLabel.attributedText = nil
        replyPreview.isHidden = true
        highlightView.isHidden = true
        contentView.alpha = 1
        laidOut = nil
        message = nil
        animator = nil
        onTapUser = nil
        onTapEmote = nil
        onTapLink = nil
        onSwipeReply = nil
        contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
    }
}
