import UIKit
import EmbrCore

@MainActor
protocol ChatInputViewDelegate: AnyObject {
    func chatInput(_ input: ChatInputView, didSubmit text: String)
    func chatInput(_ input: ChatInputView, suggestionsFor token: AutocompleteToken) -> [AutocompleteSuggestion]
    func chatInputDidCancelReply(_ input: ChatInputView)
}

enum AutocompleteToken: Equatable {
    case emote(String)
    case mention(String)
}

@MainActor
final class ChatInputView: UIView {
    weak var delegate: ChatInputViewDelegate?

    private let container = UIStackView()
    private let replyPreview = ReplyComposerBar()
    private let autocomplete: EmoteAutocompleteView
    private let inputRow = UIStackView()
    private let textView: EmoteTextView
    private let emoteButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let dropReasonLabel = UILabel()
    private let dropContainer = UIStackView()

    private let images: ImageLoading
    private var catalog = EmoteCatalog()
    private var showingEmoteKeyboard = false
    private lazy var emoteKeyboard: EmoteKeyboardView = {
        let keyboard = EmoteKeyboardView(images: images)
        keyboard.onInsert = { [weak self] name in self?.insertEmote(name) }
        keyboard.onBackspace = { [weak self] in self?.handleBackspace() }
        keyboard.onSwitchToKeyboard = { [weak self] in self?.switchToSystemKeyboard() }
        return keyboard
    }()
    private var isSending = false {
        didSet { updateSendState() }
    }

    init(images: ImageLoading) {
        self.images = images
        self.textView = EmoteTextView(images: images)
        self.autocomplete = EmoteAutocompleteView(images: images, onSelect: { _ in })
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCatalog(_ catalog: EmoteCatalog) {
        self.catalog = catalog
        textView.setCatalog(catalog)
    }

    func setSending(_ sending: Bool) {
        isSending = sending
    }

    func setRoomState(_ state: RoomState) {
        textView.placeholder = Self.placeholder(for: state)
    }

    private static func placeholder(for state: RoomState) -> String {
        var parts: [String] = []
        if state.emoteOnly { parts.append(String(localized: "emote-only")) }
        if state.subscribersOnly { parts.append(String(localized: "subs-only")) }
        if let seconds = state.followersOnly {
            parts.append(seconds == 0 ? String(localized: "followers-only") : String(localized: "followers \(seconds)m"))
        }
        if let slow = state.slowMode { parts.append(String(localized: "slow \(slow)s")) }
        if state.uniqueChat { parts.append(String(localized: "unique")) }
        guard !parts.isEmpty else { return String(localized: "Send a message") }
        return String(localized: "Send a message · \(parts.joined(separator: ", "))")
    }

    func showDropReason(_ reason: String?) {
        dropReasonLabel.text = reason
        dropContainer.isHidden = (reason == nil)
    }

    func clear() {
        textView.reset()
        refreshAutocomplete()
        showDropReason(nil)
    }

    func insertEmote(_ name: String) {
        textView.insertEmoteName(name)
        refreshAutocomplete()
    }

    private func handleBackspace() {
        textView.deleteBackward()
        refreshAutocomplete()
    }

    @objc private func emoteTapped() {
        if showingEmoteKeyboard {
            switchToSystemKeyboard()
        } else {
            showEmoteKeyboard()
        }
    }

    private func showEmoteKeyboard() {
        showingEmoteKeyboard = true
        emoteKeyboard.setCatalog(catalog)
        textView.inputView = emoteKeyboard
        updateEmoteButtonIcon()
        if textView.isFirstResponder {
            textView.reloadInputViews()
        } else {
            textView.becomeFirstResponder()
        }
    }

    private func switchToSystemKeyboard() {
        guard showingEmoteKeyboard else { return }
        showingEmoteKeyboard = false
        textView.inputView = nil
        updateEmoteButtonIcon()
        if textView.isFirstResponder { textView.reloadInputViews() }
    }

    private func updateEmoteButtonIcon() {
        emoteButton.configuration?.image = UIImage(systemName: showingEmoteKeyboard ? "keyboard" : "face.smiling")
        emoteButton.accessibilityLabel = showingEmoteKeyboard ? String(localized: "Keyboard") : String(localized: "Emotes")
    }

    func showReply(displayName: String, text: String) {
        replyPreview.configure(displayName: displayName, text: text)
        replyPreview.isHidden = false
    }

    func hideReply() {
        replyPreview.isHidden = true
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    private func setUp() {
        backgroundColor = Glass.isAvailable ? .clear : Theme.surface

        let glass = Glass.view()
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        container.translatesAutoresizingMaskIntoConstraints = false
        container.axis = .vertical
        container.spacing = 0
        addSubview(container)

        autocomplete.isHidden = true
        autocomplete.setSelectionHandler { [weak self] suggestion in
            self?.insertSuggestion(suggestion)
        }

        dropReasonLabel.font = .systemFont(ofSize: 12, weight: .regular)
        dropReasonLabel.textColor = .systemRed
        dropReasonLabel.numberOfLines = 2

        dropContainer.addArrangedSubview(dropReasonLabel)
        dropContainer.isLayoutMarginsRelativeArrangement = true
        dropContainer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14)
        dropContainer.isHidden = true

        replyPreview.isHidden = true
        replyPreview.onCancel = { [weak self] in
            guard let self else { return }
            self.delegate?.chatInputDidCancelReply(self)
        }

        configureInputRow()

        container.addArrangedSubview(replyPreview)
        container.addArrangedSubview(autocomplete)
        container.addArrangedSubview(dropContainer)
        container.addArrangedSubview(inputRow)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            autocomplete.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func configureInputRow() {
        inputRow.axis = .horizontal
        inputRow.alignment = .bottom
        inputRow.spacing = 8
        inputRow.isLayoutMarginsRelativeArrangement = true
        inputRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)

        textView.backgroundColor = Theme.surfaceElevated
        textView.layer.cornerRadius = 16
        textView.layer.cornerCurve = .continuous
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = Theme.primaryText
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        textView.onTextChange = { [weak self] in self?.refreshAutocomplete() }
        textView.onReturn = { [weak self] in self?.sendTapped() }
        textView.onEndEditing = { [weak self] in self?.switchToSystemKeyboard() }
        textView.placeholder = String(localized: "Send a message")
        textView.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "paperplane.fill")
        sendButton.configuration = config
        sendButton.tintColor = Theme.accent
        sendButton.isEnabled = false
        sendButton.alpha = 0.35
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let sendContainer = UIView()
        sendContainer.translatesAutoresizingMaskIntoConstraints = false
        sendContainer.addSubview(sendButton)
        sendContainer.addSubview(spinner)

        var emoteConfig = UIButton.Configuration.plain()
        emoteConfig.image = UIImage(systemName: "face.smiling")
        emoteButton.configuration = emoteConfig
        emoteButton.tintColor = Theme.secondaryText
        emoteButton.translatesAutoresizingMaskIntoConstraints = false
        emoteButton.accessibilityLabel = String(localized: "Emotes")
        emoteButton.addTarget(self, action: #selector(emoteTapped), for: .touchUpInside)

        inputRow.addArrangedSubview(emoteButton)
        inputRow.addArrangedSubview(textView)
        inputRow.addArrangedSubview(sendContainer)

        NSLayoutConstraint.activate([
            emoteButton.widthAnchor.constraint(equalToConstant: 38),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            textView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
            sendContainer.widthAnchor.constraint(equalToConstant: 44),
            sendContainer.heightAnchor.constraint(equalToConstant: 44),
            sendButton.centerXAnchor.constraint(equalTo: sendContainer.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendContainer.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: sendContainer.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: sendContainer.centerYAnchor)
        ])
    }

    private func refreshAutocomplete() {
        updateSendAvailability()
        guard let token = currentToken() else {
            autocomplete.update([])
            return
        }
        let suggestions = delegate?.chatInput(self, suggestionsFor: token) ?? []
        autocomplete.update(suggestions)
    }

    private func currentToken() -> AutocompleteToken? {
        let text = textView.plainText
        let caret = min(textView.plainCaretOffset, text.count)
        let caretIndex = text.index(text.startIndex, offsetBy: caret)
        let upToCaret = text[text.startIndex..<caretIndex]
        guard let word = upToCaret.split(whereSeparator: { $0.isWhitespace }).last, word.count >= 2 else { return nil }
        let string = String(word)
        if string.hasPrefix("@") {
            return .mention(String(string.dropFirst()))
        }
        return .emote(string)
    }

    private func insertSuggestion(_ suggestion: AutocompleteSuggestion) {
        if case .emote(let emote) = suggestion { EmoteUsage.record(emote) }
        textView.replaceCurrentToken(with: suggestion.insertionText + " ")
        refreshAutocomplete()
    }

    @objc private func sendTapped() {
        guard !isSending else { return }
        let text = textView.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        showDropReason(nil)
        delegate?.chatInput(self, didSubmit: text)
    }

    private func updateSendState() {
        if isSending {
            spinner.startAnimating()
            sendButton.isHidden = true
        } else {
            spinner.stopAnimating()
            sendButton.isHidden = false
        }
        updateSendAvailability()
    }

    private func updateSendAvailability() {
        let hasText = !textView.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let enabled = hasText && !isSending
        sendButton.isEnabled = enabled
        sendButton.alpha = enabled ? 1 : 0.35
    }
}

@MainActor
private final class ReplyComposerBar: UIView {
    var onCancel: (() -> Void)?
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let cancelButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(displayName: String, text: String) {
        titleLabel.text = String(localized: "Replying to \(displayName)")
        bodyLabel.text = text
    }

    private func setUp() {
        backgroundColor = Theme.surfaceElevated

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = Theme.accent
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        labels.axis = .vertical
        labels.spacing = 2

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark.circle.fill")
        cancelButton.configuration = config
        cancelButton.tintColor = Theme.secondaryText
        cancelButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [labels, cancelButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}

@MainActor
private final class EmoteTextView: UITextView, UITextViewDelegate {
    var onTextChange: (() -> Void)?
    var onReturn: (() -> Void)?
    var onEndEditing: (() -> Void)?

    private let images: ImageLoading
    private var catalog = EmoteCatalog()
    private var loadTasks: [String: Task<Void, Never>] = [:]
    private let placeholderLabel = UILabel()
    private var pendingRetokenize = false
    private var pendingRedraw = false

    init(images: ImageLoading) {
        self.images = images
        super.init(frame: .zero, textContainer: nil)
        delegate = self
        allowsEditingTextAttributes = false
        autocapitalizationType = .sentences
        returnKeyType = .send
        enablesReturnKeyAutomatically = true
        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = Theme.secondaryText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
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

    func textViewDidEndEditing(_ textView: UITextView) {
        onEndEditing?()
    }

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: font ?? .systemFont(ofSize: 16), .foregroundColor: textColor ?? Theme.primaryText]
    }

    private func caretPlainOffset() -> Int {
        reconstruct(attributedText, upTo: selectedRange.location).count
    }

    private func render(plain: String, caret: Int) {
        let mutable = NSMutableAttributedString()
        var emittedPlain = 0
        var caretLocation = 0
        var caretAssigned = false
        let scanner = TokenScanner(plain)
        while let piece = scanner.next() {
            if !caretAssigned, emittedPlain + piece.count > caret {
                caretLocation = mutable.length + (caret - emittedPlain)
                caretAssigned = true
            }
            switch piece {
            case .whitespace(let value):
                mutable.append(NSAttributedString(string: value, attributes: defaultAttributes))
            case .word(let value):
                if let emote = catalog.lookup(value) {
                    let attachment = EmoteTextAttachment(emoteName: emote.name)
                    let emoteWidth = max(20, 20 * CGFloat(emote.aspectRatio))
                    attachment.bounds = CGRect(x: 0, y: -4, width: emoteWidth, height: 20)
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

    private func loadAttachment(_ attachment: EmoteTextAttachment, emote: Emote) {
        if let url = emote.images.url(preferring: .x1), let cached = images.cachedImage(for: url) {
            attachment.image = cached
            return
        }
        let key = emote.id
        loadTasks[key]?.cancel()
        loadTasks[key] = Task { [weak self] in
            guard let self else { return }
            let image = await self.images.emoteImage(for: emote, scale: .x1)
            if Task.isCancelled { return }
            attachment.image = image
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

    var count: Int {
        switch self {
        case .word(let value): return value.count
        case .whitespace(let value): return value.count
        }
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
