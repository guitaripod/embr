import UIKit
import EmbrCore

@MainActor
final class ChannelEventCardView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let countdownLabel = UILabel()
    private let barsStack = UIStackView()
    private var barRows: [EventBarRow] = []

    private var countdownTarget: Date?
    private var countdownLocked = false
    private var ticker: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Renders the most relevant active event, or hides if there is none.
    /// Prefers a live prediction (richer), then a poll.
    func update(_ events: ChannelEvents) {
        if let prediction = events.prediction {
            configure(prediction: prediction)
            setHidden(false)
        } else if let poll = events.poll {
            configure(poll: poll)
            setHidden(false)
        } else {
            setHidden(true)
        }
    }

    private func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            ticker?.invalidate(); ticker = nil
        } else if ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    private func configure(poll: LivePoll) {
        iconView.image = UIImage(systemName: "chart.bar.fill")
        iconView.tintColor = Theme.accent
        titleLabel.text = poll.title
        countdownTarget = poll.endsAtDate
        countdownLocked = false
        let total = max(1, poll.totalVotes)
        let leadIndex = poll.choices.indices.max(by: { poll.choices[$0].votes < poll.choices[$1].votes })
        setRows(poll.choices.count)
        for (i, choice) in poll.choices.enumerated() {
            let fraction = CGFloat(choice.votes) / CGFloat(total)
            barRows[i].configure(
                title: choice.title,
                value: "\(Int((fraction * 100).rounded()))%",
                fraction: poll.totalVotes == 0 ? 0 : fraction,
                color: Theme.accent,
                emphasized: i == leadIndex
            )
        }
        tick()
    }

    private func configure(prediction: LivePrediction) {
        iconView.image = UIImage(systemName: "chart.line.uptrend.xyaxis")
        iconView.tintColor = Theme.accent
        titleLabel.text = prediction.title
        countdownTarget = prediction.locksAtDate
        countdownLocked = prediction.isLocked
        let total = max(1, prediction.totalPoints)
        let leadIndex = prediction.outcomes.indices.max(by: { prediction.outcomes[$0].points < prediction.outcomes[$1].points })
        setRows(prediction.outcomes.count)
        for (i, outcome) in prediction.outcomes.enumerated() {
            let fraction = CGFloat(outcome.points) / CGFloat(total)
            barRows[i].configure(
                title: outcome.title,
                value: "\(Self.compact(outcome.points)) · \(Self.compact(outcome.users))👤",
                fraction: prediction.totalPoints == 0 ? 0 : fraction,
                color: Self.outcomeColor(outcome.color),
                emphasized: i == leadIndex
            )
        }
        tick()
    }

    private func setRows(_ count: Int) {
        while barRows.count < count {
            let row = EventBarRow()
            barRows.append(row)
            barsStack.addArrangedSubview(row)
        }
        for (i, row) in barRows.enumerated() {
            row.isHidden = i >= count
        }
    }

    private func tick() {
        guard let target = countdownTarget else { countdownLabel.text = nil; return }
        if countdownLocked {
            countdownLabel.text = "Locked"
            return
        }
        let remaining = Int(target.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 {
            countdownLabel.text = "Closing"
        } else {
            countdownLabel.text = String(format: "%d:%02d", remaining / 60, remaining % 60)
        }
    }

    private func build() {
        let glass = Glass.view(cornerRadius: 14)
        addSubview(glass)
        glass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        if !Glass.isAvailable {
            backgroundColor = Theme.surface
            layer.cornerRadius = 14
            layer.cornerCurve = .continuous
        }

        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        countdownLabel.textColor = Theme.accent
        countdownLabel.textAlignment = .right
        countdownLabel.setContentHuggingPriority(.required, for: .horizontal)
        countdownLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [iconView, titleLabel, countdownLabel])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        barsStack.axis = .vertical
        barsStack.spacing = 6

        let content = UIStackView(arrangedSubviews: [header, barsStack])
        content.axis = .vertical
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
    }

    private static func outcomeColor(_ raw: String) -> UIColor {
        switch raw.uppercased() {
        case "BLUE": return UIColor(red: 0.0, green: 0.62, blue: 1.0, alpha: 1.0)
        case "PINK": return UIColor(red: 0.96, green: 0.30, blue: 0.65, alpha: 1.0)
        default: return Theme.accent
        }
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    isolated deinit { ticker?.invalidate() }
}

@MainActor
private final class EventBarRow: UIView {
    private let track = UIView()
    private let fill = UIView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private var fraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = Theme.surfaceElevated
        track.layer.cornerRadius = 7
        track.layer.cornerCurve = .continuous
        track.clipsToBounds = true
        addSubview(track)
        track.addSubview(fill)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, value: String, fraction: CGFloat, color: UIColor, emphasized: Bool) {
        self.fraction = max(0, min(1, fraction))
        titleLabel.text = title
        valueLabel.text = value
        fill.backgroundColor = color.withAlphaComponent(emphasized ? 0.55 : 0.32)
        titleLabel.font = .systemFont(ofSize: 13, weight: emphasized ? .bold : .semibold)
        setNeedsLayout()
        UIView.animate(withDuration: 0.3) { self.layoutIfNeeded() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
    }
}
