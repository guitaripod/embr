import UIKit

struct SliderRowConfiguration: UIContentConfiguration {
    var icon: UIImage?
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var commit: (Double) -> Void

    func makeContentView() -> UIView & UIContentView {
        SliderRowView(self)
    }

    func updated(for state: UIConfigurationState) -> SliderRowConfiguration { self }
}

@MainActor
final class SliderRowView: UIView, UIContentView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var current: SliderRowConfiguration

    var configuration: UIContentConfiguration {
        get { current }
        set {
            guard let config = newValue as? SliderRowConfiguration else { return }
            current = config
            apply(config)
        }
    }

    init(_ configuration: SliderRowConfiguration) {
        self.current = configuration
        super.init(frame: .zero)
        preservesSuperviewLayoutMargins = true
        build()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText

        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.secondaryText
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderCommitted), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [header, slider])
        textStack.axis = .vertical
        textStack.spacing = 6

        let row = UIStackView(arrangedSubviews: [iconView, textStack])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 29),
            iconView.heightAnchor.constraint(equalToConstant: 29),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func apply(_ config: SliderRowConfiguration) {
        iconView.image = config.icon
        titleLabel.text = config.title
        slider.minimumValue = Float(config.range.lowerBound)
        slider.maximumValue = Float(config.range.upperBound)
        slider.value = Float(config.value)
        slider.accessibilityLabel = config.title
        slider.accessibilityValue = config.format(config.value)
        valueLabel.text = config.format(config.value)
    }

    private func snappedValue() -> Double {
        let raw = Double(slider.value)
        let stepped = (raw / current.step).rounded() * current.step
        return min(max(stepped, current.range.lowerBound), current.range.upperBound)
    }

    @objc private func sliderChanged() {
        let formatted = current.format(snappedValue())
        valueLabel.text = formatted
        slider.accessibilityValue = formatted
    }

    @objc private func sliderCommitted() {
        current.commit(snappedValue())
    }
}

struct StepperRowConfiguration: UIContentConfiguration {
    var icon: UIImage?
    var title: String
    var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String
    var commit: (Double) -> Void

    func makeContentView() -> UIView & UIContentView { StepperRowView(self) }
    func updated(for state: UIConfigurationState) -> StepperRowConfiguration { self }
}

@MainActor
final class StepperRowView: UIView, UIContentView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let minusButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private var current: StepperRowConfiguration
    private var liveValue: Double

    var configuration: UIContentConfiguration {
        get { current }
        set {
            guard let config = newValue as? StepperRowConfiguration else { return }
            current = config
            liveValue = config.value
            apply(config)
        }
    }

    init(_ configuration: StepperRowConfiguration) {
        self.current = configuration
        self.liveValue = configuration.value
        super.init(frame: .zero)
        preservesSuperviewLayoutMargins = true
        build()
        apply(configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail

        valueLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold))
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = Theme.primaryText
        valueLabel.textAlignment = .center
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureStepperButton(minusButton, symbol: "minus")
        configureStepperButton(plusButton, symbol: "plus")
        minusButton.addAction(UIAction { [weak self] _ in self?.step(by: -1) }, for: .touchUpInside)
        plusButton.addAction(UIAction { [weak self] _ in self?.step(by: 1) }, for: .touchUpInside)

        let control = UIStackView(arrangedSubviews: [minusButton, valueLabel, plusButton])
        control.axis = .horizontal
        control.alignment = .center
        control.spacing = 2
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.backgroundColor = Theme.surfaceElevated
        control.layer.cornerRadius = 9
        control.layer.cornerCurve = .continuous
        control.isLayoutMarginsRelativeArrangement = true
        control.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)

        let row = UIStackView(arrangedSubviews: [iconView, titleLabel, control])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 29),
            iconView.heightAnchor.constraint(equalToConstant: 29),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            row.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func configureStepperButton(_ button: UIButton, symbol: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.baseForegroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        button.configuration = config
    }

    private func apply(_ config: StepperRowConfiguration) {
        iconView.image = config.icon
        titleLabel.text = config.title
        valueLabel.text = config.format(liveValue)
        minusButton.accessibilityLabel = String(localized: "Decrease \(config.title)")
        plusButton.accessibilityLabel = String(localized: "Increase \(config.title)")
        valueLabel.isAccessibilityElement = true
        valueLabel.accessibilityLabel = config.title
        valueLabel.accessibilityValue = config.format(liveValue)
        updateButtonStates()
    }

    private func step(by direction: Double) {
        let next = min(max(liveValue + current.step * direction, current.range.lowerBound), current.range.upperBound)
        guard next != liveValue else { return }
        liveValue = next
        valueLabel.text = current.format(liveValue)
        valueLabel.accessibilityValue = current.format(liveValue)
        updateButtonStates()
        Haptics.selection()
        current.commit(liveValue)
    }

    private func updateButtonStates() {
        minusButton.isEnabled = liveValue > current.range.lowerBound
        plusButton.isEnabled = liveValue < current.range.upperBound
    }
}
