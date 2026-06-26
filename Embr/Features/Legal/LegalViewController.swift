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

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private static func render(title: String, body: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: title + "\n\n", attributes: [
            .font: UIFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: Theme.primaryText
        ]))

        for paragraph in body.components(separatedBy: "\n\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let isHeading = !trimmed.contains("\n") && trimmed.count < 44 && !trimmed.hasSuffix(".")
            let font: UIFont = isHeading
                ? .systemFont(ofSize: 18, weight: .semibold)
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
        result.append(NSAttributedString(string: "Last updated \(LegalText.lastUpdated).", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: Theme.secondaryText,
            .paragraphStyle: footerStyle
        ]))
        return result
    }
}
