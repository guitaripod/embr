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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with laidOut: LaidOutMessage, message: ChatMessage, images: ImageLoading, animator: EmoteAnimator) {
        self.laidOut = laidOut
        self.animator = animator

        highlightView.isHidden = !laidOut.isHighlighted
        highlightView.backgroundColor = laidOut.isHighlighted ? Theme.highlightedMessage : .clear

        textLabel.attributedText = laidOut.attributedText

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
        laidOut = nil
        animator = nil
    }
}
