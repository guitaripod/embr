import UIKit
import EmbrCore

/// The composer's text view: emote names typed or picked show as their images inline while the message stays plain
/// text, Return sends, Escape puts the keyboard away and Tab takes the first suggestion.
@MainActor
final class EmoteTextView: UITextView, UITextViewDelegate {
    var onTextChange: (() -> Void)?
    var onReturn: (() -> Void)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onTab: (() -> Void)?
    /// Told after Dynamic Type changed the text size, since the draft may now take more or fewer lines.
    var onTextSizeChange: (() -> Void)?
    /// Whether Tab takes the first suggestion; otherwise Tab keeps its usual meaning.
    var acceptsTab = false

    private let images: ImageLoading
    private var catalog = EmoteCatalog()
    private var loadTasks: [String: Task<Void, Never>] = [:]
    private var waitingAttachments: [String: [EmoteTextAttachment]] = [:]
    private let placeholderLabel = UILabel()
    private var pendingRetokenize = false
    private var placeholderLeading: NSLayoutConstraint!
    private var placeholderTop: NSLayoutConstraint!
    private var pendingRedraw = false

    init(images: ImageLoading) {
        self.images = images
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        allowsEditingTextAttributes = false
        autocapitalizationType = .none
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        returnKeyType = .send
        enablesReturnKeyAutomatically = true
        backgroundColor = .clear
        textContainer.lineFragmentPadding = 0
        textContainerInset = ChatMetrics.fieldTextInsets
        font = Self.composerFont
        adjustsFontForContentSizeCategory = true
        textColor = Theme.primaryText
        tintColor = Theme.accent
        isScrollEnabled = false
        showsVerticalScrollIndicator = false
        placeholderLabel.font = Self.composerFont
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isAccessibilityElement = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        placeholderLeading = placeholderLabel.leadingAnchor.constraint(equalTo: frameLayoutGuide.leadingAnchor, constant: ChatMetrics.fieldTextInsets.left)
        placeholderTop = placeholderLabel.topAnchor.constraint(equalTo: frameLayoutGuide.topAnchor, constant: ChatMetrics.fieldTextInsets.top)
        NSLayoutConstraint.activate([
            placeholderLeading,
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: frameLayoutGuide.trailingAnchor, constant: -ChatMetrics.fieldTextInsets.right),
            placeholderTop
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Body text a little larger than chat's, following Dynamic Type up to a size the bar can still hold.
    static var composerFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16), maximumPointSize: 24)
    }

    /// Moves the text and the placeholder together, for the composer's bar and floating looks.
    func setTextInsets(_ insets: UIEdgeInsets) {
        textContainerInset = insets
        placeholderLeading.constant = insets.left
        placeholderTop.constant = insets.top
    }

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
            accessibilityHint = placeholder
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismissFromKeyboard))
        escape.discoverabilityTitle = String(localized: "Hide Keyboard")
        guard acceptsTab else { return [escape] }
        let tab = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(acceptSuggestion))
        tab.wantsPriorityOverSystemBehavior = true
        return [escape, tab]
    }

    @objc private func dismissFromKeyboard() {
        resignFirstResponder()
    }

    @objc private func acceptSuggestion() {
        onTab?()
    }

    func setCatalog(_ catalog: EmoteCatalog) {
        self.catalog = catalog
    }

    var plainText: String {
        reconstruct(attributedText, upTo: attributedText.length)
    }

    var plainCaretOffset: Int {
        caretPlainOffset()
    }

    /// Puts a whole draft back, emotes drawn, with the caret at its end.
    func setText(_ plain: String) {
        render(plain: plain, caret: plain.count)
    }

    func reset() {
        attributedText = NSAttributedString(string: "", attributes: defaultAttributes)
        typingAttributes = defaultAttributes
        selectedRange = NSRange(location: 0, length: 0)
        placeholderLabel.isHidden = false
    }

    func replaceCurrentToken(with replacement: String) {
        let source = plainText
        let caret = caretPlainOffset()
        let caretIndex = source.index(source.startIndex, offsetBy: min(caret, source.count))
        let prefix = source[source.startIndex..<caretIndex]
        let tokenStart = prefix.lastIndex(where: { $0.isWhitespace }).map { source.index(after: $0) } ?? source.startIndex
        let rebuilt = String(source[source.startIndex..<tokenStart]) + replacement + String(source[caretIndex...])
        let newCaret = source.distance(from: source.startIndex, to: tokenStart) + replacement.count
        render(plain: rebuilt, caret: newCaret)
    }

    func insertEmoteName(_ text: String) {
        let source = plainText
        let caret = min(caretPlainOffset(), source.count)
        let caretIndex = source.index(source.startIndex, offsetBy: caret)
        let prefix = String(source[source.startIndex..<caretIndex])
        let suffix = String(source[caretIndex...])
        let spacer = (prefix.isEmpty || prefix.hasSuffix(" ")) ? "" : " "
        let inserted = spacer + text + " "
        render(plain: prefix + inserted + suffix, caret: caret + inserted.count)
        onTextChange?()
    }

    func textViewDidChange(_ textView: UITextView) {
        if markedTextRange == nil {
            if pendingRetokenize {
                pendingRetokenize = false
                pendingRedraw = false
                render(plain: plainText, caret: caretPlainOffset())
            } else if pendingRedraw {
                pendingRedraw = false
                redrawAttachments()
            }
        }
        placeholderLabel.isHidden = attributedText.length > 0
        onTextChange?()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" { onReturn?(); return false }
        if text.contains("\n") {
            textView.insertText(text.replacingOccurrences(of: "\n", with: " "))
            return false
        }
        if text.contains(" ") { pendingRetokenize = true }
        return true
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onBeginEditing?()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onEndEditing?()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
        font = Self.composerFont
        placeholderLabel.font = Self.composerFont
        render(plain: plainText, caret: caretPlainOffset())
        onTextSizeChange?()
    }

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: font ?? Self.composerFont, .foregroundColor: textColor ?? Theme.primaryText]
    }

    private func caretPlainOffset() -> Int {
        reconstruct(attributedText, upTo: selectedRange.location).count
    }

    /// An inline emote a little taller than the text, centered on its capitals so it sits on the line like a word.
    private func attachmentBounds(for emote: Emote) -> CGRect {
        let typeface = font ?? Self.composerFont
        let height = ceil(typeface.lineHeight * 1.05)
        let width = max(height, height * CGFloat(emote.aspectRatio))
        return CGRect(x: 0, y: (typeface.capHeight - height) / 2, width: width, height: height)
    }

    private func render(plain: String, caret: Int) {
        let mutable = NSMutableAttributedString()
        var emittedPlain = 0
        var caretLocation = 0
        var caretAssigned = false
        let scanner = TokenScanner(plain)
        while let piece = scanner.next() {
            if !caretAssigned, emittedPlain + piece.count > caret {
                caretLocation = mutable.length + piece.utf16Offset(ofCharacter: caret - emittedPlain, isEmote: catalog.lookup(piece.text) != nil)
                caretAssigned = true
            }
            switch piece {
            case .whitespace(let value):
                mutable.append(NSAttributedString(string: value, attributes: defaultAttributes))
            case .word(let value):
                if let emote = catalog.lookup(value) {
                    let attachment = EmoteTextAttachment(emoteName: emote.name)
                    attachment.bounds = attachmentBounds(for: emote)
                    mutable.append(NSAttributedString(attachment: attachment))
                    loadAttachment(attachment, emote: emote)
                } else {
                    mutable.append(NSAttributedString(string: value, attributes: defaultAttributes))
                }
            }
            emittedPlain += piece.count
        }
        if !caretAssigned { caretLocation = mutable.length }
        attributedText = mutable
        typingAttributes = defaultAttributes
        selectedRange = NSRange(location: min(caretLocation, mutable.length), length: 0)
        placeholderLabel.isHidden = mutable.length > 0
    }

    /// Every copy of an emote in the draft waits on one download and gets the image when it arrives.
    private func loadAttachment(_ attachment: EmoteTextAttachment, emote: Emote) {
        if let url = emote.images.url(preferring: .x2), let cached = images.cachedImage(for: url) {
            attachment.image = cached
            return
        }
        let key = emote.id
        waitingAttachments[key, default: []].append(attachment)
        guard loadTasks[key] == nil else { return }
        loadTasks[key] = Task { [weak self] in
            guard let self else { return }
            let image = await self.images.emoteImage(for: emote, scale: .x2)
            self.loadTasks[key] = nil
            let waiting = self.waitingAttachments.removeValue(forKey: key) ?? []
            guard !Task.isCancelled else { return }
            for attachment in waiting { attachment.image = image }
            self.redrawAttachments()
        }
    }

    private func redrawAttachments() {
        guard markedTextRange == nil else { pendingRedraw = true; return }
        let preservedSelection = selectedRange
        let current = attributedText
        attributedText = current
        selectedRange = preservedSelection
    }

    private func reconstruct(_ attributed: NSAttributedString, upTo location: Int) -> String {
        var result = ""
        let bounded = NSRange(location: 0, length: max(0, min(location, attributed.length)))
        attributed.enumerateAttributes(in: bounded, options: []) { attributes, subRange, _ in
            if let emoteAttachment = attributes[.attachment] as? EmoteTextAttachment {
                result += emoteAttachment.emoteName
            } else {
                result += attributed.attributedSubstring(from: subRange).string
            }
        }
        return result
    }
}

private enum InputPiece {
    case word(String)
    case whitespace(String)

    var text: String {
        switch self {
        case .word(let value): return value
        case .whitespace(let value): return value
        }
    }

    var count: Int {
        text.count
    }

    /// Where a caret that many characters into the piece falls in the text view's UTF-16 storage: an emote is one
    /// attachment character, and an emoji or accented letter can take more than one unit.
    func utf16Offset(ofCharacter offset: Int, isEmote: Bool) -> Int {
        if case .word = self, isEmote { return offset > 0 ? 1 : 0 }
        return String(text.prefix(offset)).utf16.count
    }
}

private final class TokenScanner {
    private let characters: [Character]
    private var index = 0

    init(_ string: String) {
        self.characters = Array(string)
    }

    func next() -> InputPiece? {
        guard index < characters.count else { return nil }
        let isSpace = characters[index].isWhitespace
        var buffer = ""
        while index < characters.count, characters[index].isWhitespace == isSpace {
            buffer.append(characters[index])
            index += 1
        }
        return isSpace ? .whitespace(buffer) : .word(buffer)
    }
}

final class EmoteTextAttachment: NSTextAttachment {
    let emoteName: String

    init(emoteName: String) {
        self.emoteName = emoteName
        super.init(data: nil, ofType: nil)
        image = EmoteTextAttachment.transparentPlaceholder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Clear placeholder so the attachment shows nothing (not TextKit's "missing
    /// attachment" document glyph) while the real emote image loads asynchronously.
    private static let transparentPlaceholder: UIImage = {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
    }()
}
