import UIKit
import EmbrCore

/// What takes the band over the top of chat right now, most urgent first: a spam wave, a raid or big gift, the ad
/// break, or a note that Studio was away.
enum StudioTopMoment: Equatable {
    case spamWave
    case banner(StudioBanner)
    case adsRunning(endsAt: Date)
    case adSoon(at: Date)
    case away(TimeInterval)

    static func current(_ snapshot: StudioSession.Snapshot) -> StudioTopMoment? {
        if snapshot.spamWave { return .spamWave }
        if let banner = snapshot.banner { return .banner(banner) }
        if snapshot.role == .broadcaster, snapshot.can(.adBreaks) {
            switch snapshot.adClock.state(at: snapshot.now) {
            case .running(let endsAt, _): return .adsRunning(endsAt: endsAt)
            case .imminent(let at, _): return .adSoon(at: at)
            default: break
            }
        }
        if let away = snapshot.awayFor { return .away(away) }
        return nil
    }
}

/// The band over the top of chat.
final class StudioTopMomentView: UIView {
    var onAction: ((StudioTopMoment) -> Void)?
    var onDismiss: ((StudioTopMoment) -> Void)?

    private let scale: StudioScale
    private let gradient = CAGradientLayer()
    private let glass = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let avatar = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton: UIButton
    private let dismissButton: UIButton
    private var moment: StudioTopMoment?
    private let images: ImageLoading

    init(scale: StudioScale, images: ImageLoading = AppContainer.shared.images) {
        self.scale = scale
        self.images = images
        actionButton = StudioButton.make(title: "", scale: scale, prominent: true)
        dismissButton = StudioButton.make(title: String(localized: "Dismiss", comment: "Studio banner button"), scale: scale)
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var focusTargets: [UIView] { [actionButton, dismissButton].filter { !$0.isHidden && !isHidden } }

    func show(_ moment: StudioTopMoment?, now: Date, canModerate: Bool) {
        let changed = moment.map { self.moment.map { Self.kind($0) } != Self.kind($0) } ?? (self.moment != nil)
        self.moment = moment
        guard let moment else {
            if !isHidden { animate(visible: false) }
            return
        }
        avatar.isHidden = true
        actionButton.isHidden = true
        dismissButton.isHidden = true
        switch moment {
        case .spamWave:
            style(.alarm)
            titleLabel.text = String(localized: "Lots of identical messages from different accounts", comment: "Studio spam wave banner")
            subtitleLabel.text = String(localized: "It looks like a bot or hate raid.", comment: "Studio spam wave banner")
            actionButton.configuration?.title = String(localized: "Turn On Shield Mode", comment: "Studio spam wave banner button")
            actionButton.isHidden = !canModerate
            dismissButton.isHidden = false
        case .banner(let banner):
            style(.violet)
            fill(banner.event)
            dismissButton.isHidden = false
        case .adsRunning(let endsAt):
            style(.ember)
            titleLabel.text = String(localized: "Ads running · \(StudioFormat.countdown(endsAt.timeIntervalSince(now)))", comment: "Studio ads running banner")
            subtitleLabel.text = String(localized: "A good moment to stretch or talk to chat.", comment: "Studio ads running banner")
        case .adSoon(let at):
            style(.ember)
            titleLabel.text = String(localized: "Ad break in \(StudioFormat.countdown(at.timeIntervalSince(now)))", comment: "Studio ad soon banner")
            subtitleLabel.text = String(localized: "Snooze it on the ad clock, or let it run.", comment: "Studio ad soon banner")
        case .away(let interval):
            style(.glass)
            titleLabel.text = String(localized: "Away \(StudioFormat.duration(interval))", comment: "Studio away banner")
            subtitleLabel.text = String(localized: "Chat and alerts from that time aren't shown.", comment: "Studio away banner")
            dismissButton.isHidden = false
        }
        accessibilityLabel = [titleLabel.text, subtitleLabel.text].compactMap { $0 }.joined(separator: ", ")
        if isHidden || changed {
            animate(visible: true)
            if changed { UIAccessibility.post(notification: .announcement, argument: titleLabel.text) }
        }
    }

    private func fill(_ event: StudioEvent) {
        switch event {
        case .raid(let raid):
            titleLabel.text = String(localized: "\(raid.raiderName) is raiding with \(raid.viewers.formatted())", comment: "Studio raid banner")
            subtitleLabel.text = String(localized: "Say hi to the new people in chat.", comment: "Studio raid banner")
            if let url = raid.profileImageURL {
                avatar.isHidden = false
                Task { [weak self] in
                    let image = await self?.images.avatarImage(for: url, side: self?.scale.avatar ?? 44, scale: 2)
                    self?.avatar.image = image
                }
            }
        default:
            let text = StudioFormat.alert(StudioFeedItem(id: "", event: event, at: Date(), isBig: true))
            titleLabel.text = text.title
            subtitleLabel.text = text.detail
        }
    }

    private enum Style {
        case ember, violet, alarm, glass
    }

    private func style(_ style: Style) {
        glass.isHidden = style != .glass
        gradient.isHidden = style == .glass
        switch style {
        case .ember: gradient.colors = [StudioPalette.emberLight.cgColor, StudioPalette.rose.cgColor]
        case .violet: gradient.colors = [StudioPalette.violet.cgColor, StudioPalette.rose.cgColor]
        case .alarm: gradient.colors = [UIColor.systemRed.cgColor, StudioPalette.rose.cgColor]
        case .glass: break
        }
        let dark = style == .glass
        titleLabel.textColor = dark ? StudioPalette.text : UIColor(white: 0.05, alpha: 1)
        subtitleLabel.textColor = dark ? StudioPalette.muted : UIColor(white: 0.1, alpha: 0.85)
    }

    private static func kind(_ moment: StudioTopMoment) -> String {
        switch moment {
        case .spamWave: "spam"
        case .banner(let banner): "banner-\(banner.id)"
        case .adsRunning: "ads"
        case .adSoon: "soon"
        case .away: "away"
        }
    }

    private func animate(visible: Bool) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        if visible {
            isHidden = false
            guard !reduce else {
                alpha = 1
                return
            }
            alpha = 0
            transform = CGAffineTransform(translationX: 0, y: -20)
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                self.alpha = 1
                self.transform = .identity
            }
        } else {
            UIView.animate(withDuration: reduce ? 0 : 0.25, animations: { self.alpha = 0 }, completion: { _ in
                if self.moment == nil { self.isHidden = true }
            })
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    private func build() {
        isHidden = true
        isAccessibilityElement = false
        layer.cornerRadius = scale.corner
        layer.cornerCurve = .continuous
        clipsToBounds = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        avatar.layer.cornerRadius = scale.avatar * 0.6
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        titleLabel.font = scale.font(scale.body * 1.25, .heavy, style: .title3)
        titleLabel.numberOfLines = 2
        subtitleLabel.font = scale.font(scale.caption * 1.1, .semibold, style: .subheadline)
        subtitleLabel.numberOfLines = 2
        actionButton.addAction(UIAction { [weak self] _ in
            guard let self, let moment = self.moment else { return }
            self.onAction?(moment)
        }, for: .primaryActionTriggered)
        dismissButton.addAction(UIAction { [weak self] _ in
            guard let self, let moment = self.moment else { return }
            self.onDismiss?(moment)
        }, for: .primaryActionTriggered)
        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 2
        let buttons = UIStackView(arrangedSubviews: [actionButton, dismissButton])
        buttons.spacing = scale.spacing
        for view in [buttons, actionButton, dismissButton] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [avatar, text, buttons])
        row.spacing = scale.spacing
        row.alignment = .center
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: scale.padding * 0.8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding * 0.8),
            avatar.widthAnchor.constraint(equalToConstant: scale.avatar * 1.2),
            avatar.heightAnchor.constraint(equalToConstant: scale.avatar * 1.2),
        ])
    }
}

/// What runs along the bottom of chat while it lasts: a hype train, a poll or a prediction, then its result.
final class StudioLiveMomentView: UIView {
    private let scale: StudioScale
    private let glass = UIView()
    private let titleLabel = UILabel()
    private let trailingLabel = UILabel()
    private let bar = StudioProgressBar()
    private let footLabel = UILabel()
    private let rows = UIStackView()

    init(scale: StudioScale) {
        self.scale = scale
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ snapshot: StudioSession.Snapshot) {
        let now = snapshot.now
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let train = snapshot.hypeTrain {
            isHidden = false
            titleLabel.text = train.phase == .ended
                ? String(localized: "Hype Train ended at level \(train.level)", comment: "Studio hype train")
                : String(localized: "Hype Train · Level \(train.level)", comment: "Studio hype train")
            trailingLabel.text = train.expiresAt.map { String(localized: "\(StudioFormat.countdown($0.timeIntervalSince(now))) left", comment: "Studio hype train time left") }
            bar.isHidden = train.phase == .ended
            bar.show(train.fraction)
            let top = train.topContributors.prefix(2).map { "\($0.userName) \($0.total.formatted())" }.joined(separator: " · ")
            footLabel.text = train.phase == .ended
                ? String(localized: "\(train.total.formatted()) points in all", comment: "Studio hype train result")
                : [String(localized: "\(Int((train.fraction * 100).rounded()))% to level \(train.level + 1)", comment: "Studio hype train progress"), top].filter { !$0.isEmpty }.joined(separator: "   ")
            footLabel.isHidden = false
        } else if let poll = snapshot.poll {
            isHidden = false
            titleLabel.text = poll.phase == .ended
                ? String(localized: "Poll result: \(poll.title)", comment: "Studio poll")
                : String(localized: "Poll: \(poll.title)", comment: "Studio poll")
            trailingLabel.text = poll.phase == .open ? poll.endsAt.map { String(localized: "\(StudioFormat.countdown($0.timeIntervalSince(now))) left", comment: "Studio poll time left") } : nil
            bar.isHidden = true
            footLabel.isHidden = true
            let total = max(poll.totalVotes, 1)
            for choice in poll.choices.prefix(5) {
                rows.addArrangedSubview(choiceRow(choice.title, value: Double(choice.votes) / Double(total), winner: poll.phase == .ended && poll.winner?.id == choice.id))
            }
        } else if let prediction = snapshot.prediction {
            isHidden = false
            switch prediction.phase {
            case .open: titleLabel.text = String(localized: "Prediction: \(prediction.title)", comment: "Studio prediction")
            case .locked: titleLabel.text = String(localized: "Prediction locked: \(prediction.title)", comment: "Studio prediction")
            case .resolved: titleLabel.text = String(localized: "Prediction result: \(prediction.title)", comment: "Studio prediction")
            case .canceled: titleLabel.text = String(localized: "Prediction canceled: \(prediction.title)", comment: "Studio prediction")
            }
            trailingLabel.text = prediction.phase == .open ? prediction.locksAt.map { String(localized: "Locks in \(StudioFormat.countdown($0.timeIntervalSince(now)))", comment: "Studio prediction") } : nil
            bar.isHidden = true
            footLabel.isHidden = true
            let total = max(prediction.totalPoints, 1)
            let winner: String? = if case .resolved(let id) = prediction.phase { id } else { nil }
            for outcome in prediction.outcomes.prefix(4) {
                rows.addArrangedSubview(choiceRow(outcome.title, value: Double(outcome.votes) / Double(total), winner: outcome.id == winner))
            }
        } else {
            isHidden = true
        }
        accessibilityLabel = [titleLabel.text, trailingLabel.text, footLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    private func choiceRow(_ title: String, value: Double, winner: Bool) -> UIView {
        let label = UILabel()
        label.text = winner ? "✓ \(title)" : title
        label.font = scale.font(scale.body * 0.95, winner ? .bold : .regular, style: .body)
        label.textColor = StudioPalette.text
        let percent = UILabel()
        percent.text = "\(Int((value * 100).rounded()))%"
        percent.font = scale.digits(scale.body * 0.95, .semibold)
        percent.textColor = StudioPalette.text
        percent.setContentHuggingPriority(.required, for: .horizontal)
        let top = UIStackView(arrangedSubviews: [label, percent])
        let fill = StudioProgressBar()
        fill.show(value)
        fill.heightAnchor.constraint(equalToConstant: max(6, scale.caption * 0.5)).isActive = true
        let column = UIStackView(arrangedSubviews: [top, fill])
        column.axis = .vertical
        column.spacing = 4
        return column
    }

    private func build() {
        isHidden = true
        isAccessibilityElement = true
        layer.cornerRadius = scale.corner
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = StudioPalette.line.cgColor
        glass.backgroundColor = StudioPalette.raised
        backgroundColor = StudioPalette.raised
        isOpaque = true
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        layer.shadowColor = UIColor.black.cgColor
        titleLabel.font = scale.font(scale.body * 1.1, .heavy, style: .headline)
        titleLabel.textColor = StudioPalette.text
        titleLabel.numberOfLines = 2
        trailingLabel.font = scale.digits(scale.body, .semibold)
        trailingLabel.textColor = StudioPalette.muted
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        trailingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        footLabel.font = scale.font(scale.caption, style: .footnote)
        footLabel.textColor = StudioPalette.muted
        footLabel.numberOfLines = 2
        rows.axis = .vertical
        rows.spacing = scale.spacing * 0.6
        let header = UIStackView(arrangedSubviews: [titleLabel, trailingLabel])
        header.spacing = scale.spacing
        header.alignment = .firstBaseline
        let column = UIStackView(arrangedSubviews: [header, bar, rows, footLabel])
        column.axis = .vertical
        column.spacing = scale.spacing * 0.7
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.topAnchor.constraint(equalTo: topAnchor, constant: scale.padding * 0.8),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding * 0.8),
            bar.heightAnchor.constraint(equalToConstant: max(8, scale.caption * 0.6)),
        ])
    }
}
