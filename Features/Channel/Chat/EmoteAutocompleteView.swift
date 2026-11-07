import UIKit
import EmbrCore

enum AutocompleteSuggestion: Hashable {
    case emote(Emote)
    case mention(login: String, displayName: String)

    var insertionText: String {
        switch self {
        case .emote(let emote): return emote.name
        case .mention(let login, _): return "@\(login)"
        }
    }

    var label: String {
        switch self {
        case .emote(let emote): return emote.name
        case .mention(_, let displayName): return "@\(displayName)"
        }
    }
}

@MainActor
final class EmoteAutocompleteView: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let images: ImageLoading
    private var onSelect: (AutocompleteSuggestion) -> Void
    private var suggestions: [AutocompleteSuggestion] = []

    init(images: ImageLoading, onSelect: @escaping (AutocompleteSuggestion) -> Void) {
        self.images = images
        self.onSelect = onSelect
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setSelectionHandler(_ handler: @escaping (AutocompleteSuggestion) -> Void) {
        onSelect = handler
    }

    /// Lines the first chip up with the composer's text.
    func setLeadingInset(_ inset: CGFloat) {
        stack.directionalLayoutMargins.leading = inset
        stack.directionalLayoutMargins.trailing = inset
    }

    /// What Tab or a tap on the first chip would insert.
    var firstSuggestion: AutocompleteSuggestion? {
        suggestions.first
    }

    func update(_ suggestions: [AutocompleteSuggestion]) {
        guard suggestions != self.suggestions else { return }
        self.suggestions = suggestions
        rebuild()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 44))
    }

    private func setUp() {
        backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: ChatMetrics.edge, bottom: 0, trailing: ChatMetrics.edge)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (offset, suggestion) in suggestions.enumerated() {
            let chip = SuggestionChip(suggestion: suggestion, images: images) { [weak self] in
                self?.onSelect(suggestion)
            }
            chip.tag = offset
            stack.addArrangedSubview(chip)
        }
        scrollView.setContentOffset(.zero, animated: false)
    }
}

@MainActor
private final class SuggestionChip: UIControl {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let suggestion: AutocompleteSuggestion
    private let images: ImageLoading
    private let action: () -> Void
    private var loadTask: Task<Void, Never>?

    init(suggestion: AutocompleteSuggestion, images: ImageLoading, action: @escaping () -> Void) {
        self.suggestion = suggestion
        self.images = images
        self.action = action
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func removeFromSuperview() {
        loadTask?.cancel()
        super.removeFromSuperview()
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    private func setUp() {
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = suggestion.label

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .horizontal
        content.spacing = 6
        content.alignment = .center
        content.isUserInteractionEnabled = false
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12)
        addSubview(content)

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .medium), maximumPointSize: 22)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.primaryText
        label.text = suggestion.label

        switch suggestion {
        case .emote:
            content.addArrangedSubview(iconView)
            content.addArrangedSubview(label)
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 26),
                iconView.heightAnchor.constraint(equalToConstant: 26)
            ])
            loadIcon()
        case .mention:
            label.textColor = Theme.accent
            content.directionalLayoutMargins.leading = 12
            content.addArrangedSubview(label)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func loadIcon() {
        guard case .emote(let emote) = suggestion else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            let image = await images.emoteImage(for: emote, scale: .x2)
            if !Task.isCancelled { self.iconView.image = image }
        }
    }

    @objc private func tapped() {
        action()
    }
}
