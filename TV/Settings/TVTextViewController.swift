import UIKit

/// A long text the remote scrolls: the terms and the privacy policy, set as a document with its section headings.
final class TVTextViewController: UIViewController {
    private let text: String
    private let scrollView = TVReaderScrollView()
    private let page = UIView()
    private let fade = CAGradientLayer()

    init(title: String, text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let column = UIStackView()
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false

        let heading = UILabel()
        heading.text = title
        heading.font = TVFont.bold(.title2)
        heading.textColor = Theme.primaryText
        heading.numberOfLines = 0
        heading.accessibilityTraits = .header
        column.addArrangedSubview(heading)
        column.setCustomSpacing(48, after: heading)

        for block in Self.blocks(of: text) {
            if let title = block.heading {
                let label = Self.label(title, font: TVFont.bold(.headline), color: Theme.primaryText)
                label.accessibilityTraits = .header
                column.addArrangedSubview(label)
                column.setCustomSpacing(10, after: label)
            }
            let body = Self.label(block.body, font: TVFont.body, color: Theme.primaryText)
            column.addArrangedSubview(body)
            column.setCustomSpacing(40, after: body)
        }
        let updated = Self.label(String(localized: "Last updated \(LegalText.lastUpdated)."), font: TVFont.cardSubtitle, color: Theme.secondaryText)
        column.addArrangedSubview(updated)

        scrollView.addSubview(column)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(top: TVMetrics.tabBarClearance, left: 0, bottom: 120, right: 0)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(scrollView)
        page.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page)

        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.05, 0.9, 1]
        page.layer.mask = fade

        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: view.topAnchor),
            page.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: page.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            scrollView.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: 1240),
            column.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 60),
            column.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -60),
            column.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -120),
        ])
        setContentScrollView(scrollView, for: .top)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = page.bounds
        CATransaction.commit()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        [scrollView]
    }

    private struct Block {
        let heading: String?
        let body: String
    }

    /// Splits the text at blank lines; a block whose short first line ends without a full stop is a section heading
    /// above its paragraph.
    private static func blocks(of text: String) -> [Block] {
        text.components(separatedBy: "\n\n").compactMap { paragraph in
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lines = trimmed.split(separator: "\n", maxSplits: 1).map(String.init)
            if lines.count == 2, lines[0].count < 60, !lines[0].hasSuffix(".") {
                return Block(heading: lines[0], body: lines[1])
            }
            return Block(heading: nil, body: trimmed)
        }
    }

    private static func label(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        label.attributedText = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        label.numberOfLines = 0
        return label
    }
}

/// A scroll view that takes focus itself, so the remote can read a page with nothing to select on it: a swipe pans
/// it, a click up or down turns most of a screen, and up at the top moves on to the tab bar as anywhere else. Menu
/// goes back as usual.
final class TVReaderScrollView: UIScrollView {
    private var scrolledPresses: Set<UIPress.PressType> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        showsVerticalScrollIndicator = true
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passed = Set<UIPress>()
        for press in presses {
            if let distance = distance(for: press.type) {
                scrolledPresses.insert(press.type)
                scroll(by: distance)
            } else {
                passed.insert(press)
            }
        }
        if !passed.isEmpty { super.pressesBegan(passed, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passed = presses.filter { !scrolledPresses.contains($0.type) }
        if !passed.isEmpty { super.pressesChanged(passed, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passed = finish(presses)
        if !passed.isEmpty { super.pressesEnded(passed, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passed = finish(presses)
        if !passed.isEmpty { super.pressesCancelled(passed, with: event) }
    }

    /// Forgets the presses this view scrolled for and returns the others, which go on to the next responder.
    private func finish(_ presses: Set<UIPress>) -> Set<UIPress> {
        var passed = Set<UIPress>()
        for press in presses {
            if scrolledPresses.remove(press.type) == nil { passed.insert(press) }
        }
        return passed
    }

    /// How far a press scrolls, or nil when it is not a scrolling press or the page has no more to show that way.
    private func distance(for type: UIPress.PressType) -> CGFloat? {
        let page = bounds.height * 0.7
        let top = -adjustedContentInset.top
        let bottom = max(top, contentSize.height + adjustedContentInset.bottom - bounds.height)
        switch type {
        case .downArrow, .pageDown:
            return contentOffset.y < bottom - 1 ? min(page, bottom - contentOffset.y) : nil
        case .upArrow, .pageUp:
            return contentOffset.y > top + 1 ? -min(page, contentOffset.y - top) : nil
        default:
            return nil
        }
    }

    private func scroll(by distance: CGFloat) {
        let target = CGPoint(x: contentOffset.x, y: contentOffset.y + distance)
        setContentOffset(target, animated: !UIAccessibility.isReduceMotionEnabled)
        flashScrollIndicators()
    }
}
