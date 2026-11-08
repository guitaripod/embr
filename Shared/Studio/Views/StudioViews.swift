import UIKit
import EmbrCore

/// Studio's colors: a dark room lit by Embr's ember, the same on every device and in every app theme, because a studio
/// screen sits beside a stream at night.
enum StudioPalette {
    static let background = UIColor(red: 0.027, green: 0.024, blue: 0.039, alpha: 1)
    static let panel = UIColor(red: 0.071, green: 0.063, blue: 0.090, alpha: 1)
    static let raised = UIColor(red: 0.106, green: 0.094, blue: 0.133, alpha: 1)
    static let line = UIColor(red: 0.165, green: 0.145, blue: 0.200, alpha: 1)
    static let text = UIColor(red: 0.965, green: 0.949, blue: 0.973, alpha: 1)
    static let muted = UIColor(red: 0.616, green: 0.576, blue: 0.671, alpha: 1)
    static let ember = UIColor(red: 1.0, green: 0.42, blue: 0.24, alpha: 1)
    static let emberLight = UIColor(red: 1.0, green: 0.541, blue: 0.239, alpha: 1)
    static let rose = UIColor(red: 1.0, green: 0.31, blue: 0.529, alpha: 1)
    static let violet = UIColor(red: 0.69, green: 0.44, blue: 1.0, alpha: 1)
    static let live = UIColor.systemRed
    static let good = UIColor(red: 0.239, green: 0.863, blue: 0.592, alpha: 1)
    static let gradient = [emberLight, rose, violet]
}

/// Sizes for each kind of screen: a TV read from across the room, an iPad on a stand, an iPhone in the hand.
struct StudioScale: Sendable {
    let title: CGFloat
    let body: CGFloat
    let caption: CGFloat
    let big: CGFloat
    let label: CGFloat
    let corner: CGFloat
    let padding: CGFloat
    let spacing: CGFloat
    let avatar: CGFloat
    let ring: CGFloat
    let icon: CGFloat

    static let tv = StudioScale(title: 38, body: 28, caption: 22, big: 76, label: 22, corner: 26, padding: 28, spacing: 18, avatar: 72, ring: 150, icon: 56)
    static let pad = StudioScale(title: 22, body: 17, caption: 13, big: 44, label: 12, corner: 18, padding: 16, spacing: 12, avatar: 44, ring: 92, icon: 36)
    static let phone = StudioScale(title: 17, body: 15, caption: 12, big: 34, label: 11, corner: 14, padding: 12, spacing: 8, avatar: 34, ring: 70, icon: 30)

    func font(_ size: CGFloat, _ weight: UIFont.Weight = .regular, style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        #if os(tvOS)
        return base
        #else
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: size * 1.6)
        #endif
    }

    func digits(_ size: CGFloat, _ weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #if os(tvOS)
        return base
        #else
        return UIFontMetrics(forTextStyle: .title1).scaledFont(for: base, maximumPointSize: size * 1.4)
        #endif
    }
}

/// A rounded panel in Studio's dark style.
class StudioCard: UIView {
    init(scale: StudioScale) {
        super.init(frame: .zero)
        backgroundColor = StudioPalette.panel
        layer.cornerRadius = scale.corner
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = StudioPalette.line.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// The last half hour of viewer counts as a line with its newest point marked.
final class StudioSparklineView: UIView {
    private let line = CAShapeLayer()
    private let dot = CAShapeLayer()
    private var values: [Int] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        line.fillColor = UIColor.clear.cgColor
        line.strokeColor = StudioPalette.emberLight.cgColor
        line.lineWidth = 2.5
        line.lineJoin = .round
        line.lineCap = .round
        dot.fillColor = StudioPalette.emberLight.cgColor
        layer.addSublayer(line)
        layer.addSublayer(dot)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ values: [Int]) {
        guard values != self.values else { return }
        self.values = values
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width, height = bounds.height
        guard values.count > 1, width > 0, height > 0, let low = values.min(), let high = values.max() else {
            line.path = nil
            dot.path = nil
            return
        }
        let span = max(Double(high - low), 1)
        let inset: CGFloat = 4
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: inset + CGFloat(index) / CGFloat(values.count - 1) * (width - inset * 2),
                y: height - inset - CGFloat(Double(value - low) / span) * (height - inset * 2)
            )
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        line.path = path.cgPath
        if let last = points.last {
            dot.path = UIBezierPath(ovalIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)).cgPath
        }
    }
}

/// A thin bar that fills to a fraction, in the ember gradient.
final class StudioProgressBar: UIView {
    private let fill = CAGradientLayer()
    private var fraction: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white.withAlphaComponent(0.14)
        fill.colors = StudioPalette.gradient.map(\.cgColor)
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(fill)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        CATransaction.begin()
        CATransaction.setDisableActions(UIAccessibility.isReduceMotionEnabled)
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        fill.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }
}

/// The top of the Studio screen: who is on air, for how long, to how many people, and the channel's goal.
final class StudioOnAirStripView: UIView {
    private let scale: StudioScale
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let livePill = UILabel()
    private let uptimeLabel = UILabel()
    private let viewersLabel = UILabel()
    private let viewersCaption = UILabel()
    private let sparkline = StudioSparklineView()
    private let categoryLabel = UILabel()
    private let goalLabel = UILabel()
    private let goalBar = StudioProgressBar()
    private let goalRow = UIStackView()
    private let statsStack = UIStackView()
    private var avatarURL: URL?
    private let images: ImageLoading

    init(scale: StudioScale, images: ImageLoading = AppContainer.shared.images) {
        self.scale = scale
        self.images = images
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// An iPhone's strip keeps only what fits: the viewer count with an eye, no sparkline or category.
    private var isCompact: Bool { scale.title < StudioScale.pad.title }

    func show(_ snapshot: StudioSession.Snapshot, showsViewers: Bool) {
        let prefix = snapshot.role == .moderator ? String(localized: "Moderating ", comment: "Studio, before the channel name in moderator mode") : ""
        nameLabel.text = prefix + snapshot.channel.broadcasterName
        titleLabel.text = snapshot.title
        livePill.text = snapshot.isLive ? String(localized: "LIVE", comment: "Studio live badge") : String(localized: "OFFLINE", comment: "Studio offline badge")
        livePill.backgroundColor = snapshot.isLive ? StudioPalette.live : StudioPalette.raised
        livePill.textColor = snapshot.isLive ? .white : StudioPalette.muted
        uptimeLabel.text = snapshot.startedAt.map { StudioFormat.uptime(since: $0, now: snapshot.now) }
        uptimeLabel.isHidden = !snapshot.isLive
        let viewers = snapshot.viewers
        viewersLabel.text = viewers?.formatted()
        statsStack.isHidden = !snapshot.isLive || viewers == nil || !showsViewers
        sparkline.show(snapshot.viewerHistory)
        categoryLabel.text = snapshot.category
        categoryLabel.isHidden = snapshot.category.isEmpty || isCompact
        sparkline.isHidden = isCompact
        viewersCaption.isHidden = isCompact
        if isCompact, let viewers {
            let text = NSMutableAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: "eye.fill")?.withTintColor(StudioPalette.muted, renderingMode: .alwaysOriginal) ?? UIImage()))
            text.append(NSAttributedString(string: " " + viewers.formatted()))
            viewersLabel.attributedText = text
        }
        if let goal = snapshot.goal {
            goalRow.isHidden = false
            let what = goal.description.isEmpty ? Self.goalName(goal.kind) : goal.description
            goalLabel.text = "\(what) · \(goal.current.formatted()) / \(goal.target.formatted())"
            goalBar.show(goal.fraction)
        } else {
            goalRow.isHidden = true
        }
        loadAvatar(snapshot.avatarURL)
        accessibilityLabel = [nameLabel.text, livePill.text, uptimeLabel.isHidden ? nil : uptimeLabel.text, statsStack.isHidden ? nil : String(localized: "\(viewers ?? 0) viewers", comment: "VoiceOver")]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private static func goalName(_ kind: String) -> String {
        switch kind {
        case "follow": String(localized: "Follower goal", comment: "Studio goal label")
        case "subscription", "subscription_count", "new_subscription", "new_subscription_count": String(localized: "Sub goal", comment: "Studio goal label")
        case "new_bit": String(localized: "Bits goal", comment: "Studio goal label")
        case "new_cheerer": String(localized: "Cheerer goal", comment: "Studio goal label")
        default: String(localized: "Goal", comment: "Studio goal label")
        }
    }

    private func loadAvatar(_ url: URL?) {
        guard url != avatarURL else { return }
        avatarURL = url
        guard let url else { return }
        Task { [weak self] in
            let image = await self?.images.avatarImage(for: url, side: self?.scale.avatar ?? 44, scale: 2)
            guard self?.avatarURL == url else { return }
            self?.avatar.image = image
        }
    }

    private func build() {
        isAccessibilityElement = true
        avatar.backgroundColor = StudioPalette.raised
        avatar.layer.cornerRadius = scale.avatar / 2
        avatar.clipsToBounds = true
        avatar.contentMode = .scaleAspectFill
        avatar.image = UIImage(systemName: "person.fill")
        avatar.tintColor = StudioPalette.muted
        nameLabel.font = scale.font(scale.title, .bold, style: .headline)
        nameLabel.textColor = StudioPalette.text
        titleLabel.font = scale.font(scale.caption, style: .subheadline)
        titleLabel.textColor = StudioPalette.muted
        livePill.font = scale.font(scale.caption, .heavy, style: .caption1)
        livePill.textAlignment = .center
        livePill.layer.cornerRadius = scale.corner / 3
        livePill.clipsToBounds = true
        uptimeLabel.font = scale.digits(scale.body, .semibold)
        uptimeLabel.textColor = StudioPalette.text
        viewersLabel.font = scale.digits(scale.body * 1.3, .bold)
        viewersLabel.textColor = StudioPalette.text
        viewersCaption.text = String(localized: "viewers", comment: "Studio, under the viewer count")
        viewersCaption.font = scale.font(scale.caption, style: .caption1)
        viewersCaption.textColor = StudioPalette.muted
        categoryLabel.font = scale.font(scale.caption, .semibold, style: .caption1)
        categoryLabel.textColor = StudioPalette.muted
        goalLabel.font = scale.font(scale.caption, .semibold, style: .caption1)
        goalLabel.textColor = StudioPalette.muted

        let who = UIStackView(arrangedSubviews: [nameLabel, titleLabel])
        who.axis = .vertical
        who.spacing = 2
        let viewers = UIStackView(arrangedSubviews: [viewersLabel, viewersCaption])
        viewers.axis = .vertical
        viewers.alignment = .trailing
        statsStack.addArrangedSubview(viewers)
        statsStack.addArrangedSubview(sparkline)
        statsStack.spacing = scale.spacing
        statsStack.alignment = .center
        for view in [livePill, uptimeLabel, categoryLabel, viewersLabel, viewersCaption] {
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
        let live = UIStackView(arrangedSubviews: [livePill, uptimeLabel])
        live.spacing = scale.spacing * 0.6
        live.alignment = .center
        let right = UIStackView(arrangedSubviews: [live, statsStack, categoryLabel])
        right.spacing = scale.spacing * 1.4
        right.alignment = .center
        let top = UIStackView(arrangedSubviews: [avatar, who, right])
        top.spacing = scale.spacing
        top.alignment = .center
        who.setContentHuggingPriority(.defaultLow, for: .horizontal)
        who.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        right.setContentHuggingPriority(.required, for: .horizontal)
        right.setContentCompressionResistancePriority(.required, for: .horizontal)
        goalRow.addArrangedSubview(goalLabel)
        goalRow.addArrangedSubview(goalBar)
        goalRow.spacing = scale.spacing
        goalRow.alignment = .center
        goalLabel.setContentHuggingPriority(.required, for: .horizontal)
        let column = UIStackView(arrangedSubviews: [top, goalRow])
        column.axis = .vertical
        column.spacing = scale.spacing * 0.6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatar.widthAnchor.constraint(equalToConstant: scale.avatar),
            avatar.heightAnchor.constraint(equalToConstant: scale.avatar),
            livePill.widthAnchor.constraint(greaterThanOrEqualToConstant: scale.caption * 4),
            livePill.heightAnchor.constraint(equalToConstant: scale.caption * 1.6),
            sparkline.widthAnchor.constraint(equalToConstant: scale.avatar * 2.2),
            sparkline.heightAnchor.constraint(equalToConstant: scale.avatar * 0.8),
            goalBar.heightAnchor.constraint(equalToConstant: max(6, scale.caption * 0.4)),
        ])
    }
}

/// The ad clock: the next mid-roll counting down with Snooze and Run Ad, the break counting down while ads run, or a
/// line that says why there is nothing to show.
final class StudioAdClockView: StudioCard {
    var onSnooze: (() -> Void)?
    var onRunAd: (() -> Void)?

    private let scale: StudioScale
    private let header = UILabel()
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let ringView = UIView()
    private let timeLabel = UILabel()
    private let detailLabel = UILabel()
    private let snoozeButton: UIButton
    private let runButton: UIButton
    private let buttons = UIStackView()
    private var hot = false

    override init(scale: StudioScale) {
        self.scale = scale
        snoozeButton = StudioButton.make(title: String(localized: "Snooze +5:00", comment: "Studio ad clock button"), scale: scale)
        runButton = StudioButton.make(title: String(localized: "Run Ad", comment: "Studio ad clock button"), scale: scale)
        super.init(scale: scale)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var focusTargets: [UIView] { [snoozeButton, runButton].filter { !$0.isHidden } }

    func show(_ snapshot: StudioSession.Snapshot, hasPro: Bool) {
        let now = snapshot.now
        let clock = snapshot.adClock
        guard snapshot.role == .broadcaster else {
            isHidden = true
            return
        }
        isHidden = false
        guard snapshot.isAffiliate || snapshot.isSample else {
            showMessage(String(localized: "Ads start when you're an Affiliate", comment: "Studio ad clock, channel without ads"))
            return
        }
        guard snapshot.features.contains(.adBreaks) else {
            showMessage(String(localized: "Turn on Ad Breaks in Studio's permissions to see your next ad", comment: "Studio ad clock, permission missing"))
            return
        }
        guard snapshot.isLive else {
            isHidden = true
            return
        }
        let snoozes = clock.snoozesLeft
        let snoozeLine: String = {
            if snoozes > 0 { return String(localized: "\(snoozes) snoozes left", comment: "Studio ad clock") }
            if let refresh = clock.nextSnoozeAt { return String(localized: "Next snooze at \(StudioFormat.clock(refresh))", comment: "Studio ad clock") }
            return String(localized: "No snoozes left", comment: "Studio ad clock")
        }()
        switch clock.state(at: now) {
        case .unknown:
            showMessage(String(localized: "Reading your ad schedule…", comment: "Studio ad clock"))
        case .noneScheduled(let prerollFreeUntil):
            setHot(false)
            header.text = String(localized: "NO AD SCHEDULED", comment: "Studio ad clock header")
            timeLabel.text = "–:––"
            detailLabel.text = prerollFreeUntil.map { String(localized: "Pre-rolls off for \(StudioFormat.countdown($0.timeIntervalSince(now)))", comment: "Studio ad clock") } ?? snoozeLine
            setRing(0)
        case .scheduled(let at, let duration):
            setHot(false)
            header.text = String(localized: "NEXT AD BREAK", comment: "Studio ad clock header")
            timeLabel.text = StudioFormat.countdown(at.timeIntervalSince(now))
            detailLabel.text = String(localized: "\(Int(duration)) s mid-roll · \(snoozeLine)", comment: "Studio ad clock")
            setRing(min(1, at.timeIntervalSince(now) / 900))
        case .imminent(let at, let duration):
            setHot(true)
            header.text = String(localized: "AD BREAK IN", comment: "Studio ad clock header")
            timeLabel.text = StudioFormat.countdown(at.timeIntervalSince(now))
            detailLabel.text = String(localized: "\(Int(duration)) s mid-roll · \(snoozeLine)", comment: "Studio ad clock")
            setRing(at.timeIntervalSince(now) / AdBreakClock.imminentWindow)
        case .running(let endsAt, let duration):
            setHot(true)
            header.text = String(localized: "ADS RUNNING", comment: "Studio ad clock header")
            timeLabel.text = StudioFormat.countdown(endsAt.timeIntervalSince(now))
            detailLabel.text = String(localized: "Viewers back at \(StudioFormat.clock(endsAt))", comment: "Studio ad clock")
            setRing(duration > 0 ? endsAt.timeIntervalSince(now) / duration : 0)
        }
        timeLabel.isHidden = false
        ringView.isHidden = false
        buttons.isHidden = false
        let canSnooze = clock.canSnooze(at: now)
        snoozeButton.isEnabled = canSnooze || !hasPro
        snoozeButton.alpha = snoozeButton.isEnabled ? 1 : 0.45
        let canRun = snapshot.features.contains(.runAds) && clock.canRunAd(at: now)
        runButton.isHidden = !snapshot.features.contains(.runAds)
        runButton.isEnabled = canRun || !hasPro
        runButton.alpha = runButton.isEnabled ? 1 : 0.45
        if !hasPro {
            snoozeButton.configuration?.image = UIImage(systemName: "lock.fill")
            runButton.configuration?.image = UIImage(systemName: "lock.fill")
        } else {
            snoozeButton.configuration?.image = nil
            runButton.configuration?.image = nil
            if let unlocks = clock.runAdUnlocksAt(now: now), snapshot.features.contains(.runAds) {
                runButton.configuration?.title = String(localized: "Run Ad in \(StudioFormat.countdown(unlocks.timeIntervalSince(now)))", comment: "Studio ad clock button, cooling down")
            } else {
                runButton.configuration?.title = String(localized: "Run Ad", comment: "Studio ad clock button")
            }
        }
        accessibilityLabel = [header.text, timeLabel.text, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    private func showMessage(_ text: String) {
        setHot(false)
        header.text = String(localized: "AD BREAKS", comment: "Studio ad clock header")
        detailLabel.text = text
        timeLabel.isHidden = true
        ringView.isHidden = true
        buttons.isHidden = true
    }

    private func setHot(_ value: Bool) {
        guard value != hot else { return }
        hot = value
        layer.borderColor = (value ? StudioPalette.ember : StudioPalette.line).cgColor
        layer.borderWidth = value ? 2 : 1
        header.textColor = value ? StudioPalette.emberLight : StudioPalette.muted
        timeLabel.textColor = value ? StudioPalette.emberLight : StudioPalette.text
        ring.strokeColor = (value ? StudioPalette.ember : StudioPalette.violet).cgColor
    }

    private func setRing(_ fraction: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = CGFloat(min(max(fraction, 0), 1))
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = ringView.bounds.width
        let path = UIBezierPath(arcCenter: CGPoint(x: side / 2, y: side / 2), radius: side / 2 - scale.ring * 0.06, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        ring.path = path
        track.path = path
        ring.lineWidth = scale.ring * 0.085
        track.lineWidth = scale.ring * 0.085
    }

    private func build() {
        isAccessibilityElement = false
        header.font = scale.font(scale.label, .bold, style: .caption1)
        header.textColor = StudioPalette.muted
        timeLabel.font = scale.digits(scale.big, .bold)
        timeLabel.textColor = StudioPalette.text
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.6
        detailLabel.font = scale.font(scale.caption, style: .footnote)
        detailLabel.textColor = StudioPalette.muted
        detailLabel.numberOfLines = 2
        track.fillColor = UIColor.clear.cgColor
        track.strokeColor = StudioPalette.line.cgColor
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = StudioPalette.violet.cgColor
        ring.lineCap = .round
        ringView.layer.addSublayer(track)
        ringView.layer.addSublayer(ring)
        snoozeButton.addAction(UIAction { [weak self] _ in self?.onSnooze?() }, for: .primaryActionTriggered)
        runButton.addAction(UIAction { [weak self] _ in self?.onRunAd?() }, for: .primaryActionTriggered)

        let numbers = UIStackView(arrangedSubviews: [timeLabel, detailLabel])
        numbers.axis = .vertical
        numbers.spacing = scale.spacing * 0.3
        let row = UIStackView(arrangedSubviews: [ringView, numbers])
        row.spacing = scale.spacing * 1.4
        row.alignment = .center
        buttons.addArrangedSubview(snoozeButton)
        buttons.addArrangedSubview(runButton)
        buttons.spacing = scale.spacing
        buttons.distribution = .fillEqually
        let column = UIStackView(arrangedSubviews: [header, row, buttons])
        column.axis = .vertical
        column.spacing = scale.spacing
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: scale.padding),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding),
            ringView.widthAnchor.constraint(equalToConstant: scale.ring),
            ringView.heightAnchor.constraint(equalToConstant: scale.ring),
        ])
    }
}

/// Buttons in Studio's style: on the TV they take the system's focus look, elsewhere a filled capsule.
enum StudioButton {
    static func make(title: String, scale: StudioScale, prominent: Bool = false, symbol: String? = nil) -> UIButton {
        #if os(tvOS)
        var configuration = UIButton.Configuration.bordered()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 22, bottom: 16, trailing: 22)
        #else
        var configuration = prominent ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = prominent ? StudioPalette.ember : StudioPalette.raised
        configuration.baseForegroundColor = prominent ? .white : StudioPalette.text
        #endif
        configuration.title = title
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 8
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = scale.font(scale.caption * 1.05, .semibold, style: .callout)
            return updated
        }
        let button = UIButton(configuration: configuration)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        return button
    }
}

/// The alert feed: the newest events first, big moments in violet, the rest quiet.
final class StudioAlertFeedView: UIView {
    private let scale: StudioScale
    private let stack = UIStackView()
    private let empty = UILabel()
    private let limit: Int
    private var shownIDs: [String] = []

    init(scale: StudioScale, limit: Int) {
        self.scale = scale
        self.limit = limit
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = scale.spacing * 0.7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        empty.text = String(localized: "Follows, subs, raids and cheers show up here.", comment: "Studio alert feed, empty")
        empty.font = scale.font(scale.caption, style: .footnote)
        empty.textColor = StudioPalette.muted
        empty.numberOfLines = 0
        empty.translatesAutoresizingMaskIntoConstraints = false
        addSubview(empty)
        clipsToBounds = true
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            empty.topAnchor.constraint(equalTo: topAnchor, constant: scale.spacing),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ items: [StudioFeedItem], now: Date) {
        let visible = Array(items.prefix(limit))
        empty.isHidden = !visible.isEmpty
        let ids = visible.map { "\($0.id)-\($0.moreFollowers.count)" }
        guard ids != shownIDs else {
            for (row, item) in zip(stack.arrangedSubviews.compactMap { $0 as? StudioAlertRowView }, visible) {
                row.updateTime(item.at, now: now)
            }
            return
        }
        let animate = !shownIDs.isEmpty && !UIAccessibility.isReduceMotionEnabled
        shownIDs = ids
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in visible.enumerated() {
            let row = StudioAlertRowView(scale: scale)
            row.show(item, now: now)
            stack.addArrangedSubview(row)
            if animate, index == 0 {
                row.alpha = 0
                row.transform = CGAffineTransform(translationX: 0, y: -12)
                UIView.animate(withDuration: 0.3) {
                    row.alpha = 1
                    row.transform = .identity
                }
            }
        }
    }
}

final class StudioAlertRowView: StudioCard {
    private let scale: StudioScale
    private let icon = UIImageView()
    private let iconTile = UIView()
    private let title = UILabel()
    private let detail = UILabel()
    private let time = UILabel()

    override init(scale: StudioScale) {
        self.scale = scale
        super.init(scale: scale)
        layer.cornerRadius = scale.corner * 0.8
        iconTile.layer.cornerRadius = scale.icon * 0.28
        iconTile.layer.cornerCurve = .continuous
        icon.tintColor = .black
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: scale.icon * 0.42, weight: .bold)
        title.font = scale.font(scale.body, .semibold, style: .body)
        title.textColor = StudioPalette.text
        title.numberOfLines = 2
        detail.font = scale.font(scale.caption, style: .footnote)
        detail.textColor = StudioPalette.muted
        detail.numberOfLines = 2
        time.font = scale.digits(scale.caption, .regular)
        time.textColor = StudioPalette.muted
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)
        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [iconTile, text, time])
        row.spacing = scale.spacing
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: scale.padding * 0.55),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding * 0.7),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding * 0.7),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding * 0.55),
            iconTile.widthAnchor.constraint(equalToConstant: scale.icon),
            iconTile.heightAnchor.constraint(equalToConstant: scale.icon),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
        ])
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ item: StudioFeedItem, now: Date) {
        let text = StudioFormat.alert(item)
        icon.image = UIImage(systemName: text.symbol)
        iconTile.backgroundColor = Self.tint(for: item.event)
        title.text = text.title
        detail.text = text.detail
        detail.isHidden = text.detail == nil
        if item.isBig {
            backgroundColor = StudioPalette.violet.withAlphaComponent(0.18)
            layer.borderColor = StudioPalette.violet.withAlphaComponent(0.8).cgColor
        }
        updateTime(item.at, now: now)
        accessibilityLabel = [text.title, text.detail].compactMap { $0 }.joined(separator: ", ")
    }

    func updateTime(_ at: Date, now: Date) {
        time.text = StudioFormat.clock(at)
    }

    private static func tint(for event: StudioEvent) -> UIColor {
        switch event {
        case .follow: UIColor(red: 0.61, green: 0.83, blue: 1, alpha: 1)
        case .subscription: UIColor(red: 0.79, green: 0.66, blue: 1, alpha: 1)
        case .giftBomb, .charity: StudioPalette.emberLight
        case .cheer, .powerUp: UIColor(red: 1, green: 0.83, blue: 0.42, alpha: 1)
        case .raid: UIColor(red: 1, green: 0.6, blue: 0.66, alpha: 1)
        default: UIColor(red: 0.56, green: 0.94, blue: 0.78, alpha: 1)
        }
    }
}
