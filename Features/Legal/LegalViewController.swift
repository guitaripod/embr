import UIKit

@MainActor
final class LegalViewController: UIViewController {
    private let titleText: String
    private let bodyText: String

    init(title: String, body: String) {
        self.titleText = title
        self.bodyText = body
        super.init(nibName: nil, bundle: nil)
        self.title = title
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 32, right: 20)
        textView.attributedText = Self.render(title: titleText, body: bodyText)
        textView.adjustsFontForContentSizeCategory = true
        view.addSubview(textView)

        let safeArea = view.safeAreaLayoutGuide
        let readable = view.readableContentGuide
        let safeEdges = [
            textView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
        ]
        let readableEdges = [
            textView.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: readable.trailingAnchor)
        ]
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        applyEdges(safe: safeEdges, readable: readableEdges)
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: LegalViewController, _) in
            controller.applyEdges(safe: safeEdges, readable: readableEdges)
        }
    }

    /// Wide windows keep the text to a readable column; compact ones run it to the safe area.
    private func applyEdges(safe: [NSLayoutConstraint], readable: [NSLayoutConstraint]) {
        let wide = traitCollection.horizontalSizeClass == .regular
        NSLayoutConstraint.deactivate(wide ? safe : readable)
        NSLayoutConstraint.activate(wide ? readable : safe)
    }

    private static func render(title: String, body: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: title + "\n\n", attributes: [
            .font: UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 26, weight: .bold)),
            .foregroundColor: Theme.primaryText
        ]))

        for paragraph in body.components(separatedBy: "\n\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let isHeading = !trimmed.contains("\n") && trimmed.count < 44 && !trimmed.hasSuffix(".")
            let font: UIFont = isHeading
                ? UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 18, weight: .semibold))
                : .preferredFont(forTextStyle: .body)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = isHeading ? 4 : 14
            paragraphStyle.lineSpacing = 2
            result.append(NSAttributedString(string: trimmed + "\n", attributes: [
                .font: font,
                .foregroundColor: isHeading ? Theme.primaryText : Theme.secondaryText,
                .paragraphStyle: paragraphStyle
            ]))
        }

        let footerStyle = NSMutableParagraphStyle()
        footerStyle.paragraphSpacingBefore = 18
        result.append(NSAttributedString(string: String(localized: "Last updated \(LegalText.lastUpdated)."), attributes: [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: Theme.secondaryText,
            .paragraphStyle: footerStyle
        ]))
        return result
    }
}
