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

/// The chat composer: a reply strip, autocomplete, a status line and the field with its emote button beside the send
/// button. The field starts on the chat's text edge, grows with the message up to a few lines, and every part that
/// comes and goes animates with the bar so the chat above follows smoothly.
@MainActor
final class ChatInputView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: ChatInputViewDelegate?
    /// Told when the viewer starts or stops writing, so the screen around the chat can make room for it.
    var onEditingChanged: ((Bool) -> Void)?
    /// Moderators and the broadcaster are not held to slow mode.
    var isExemptFromSlowMode = false {
        didSet { if isExemptFromSlowMode { endCooldown() } }
    }
    /// Told when the emote keyboard comes up or goes away, since dragging the chat cannot pull it down the way it
    /// pulls down the system keyboard.
    var onEmoteKeyboardChanged: ((Bool) -> Void)?

    private let container = UIStackView()
    private let replyPreview = ReplyComposerBar()
    private let autocomplete: EmoteAutocompleteView
    private let statusLabel = UILabel()
    private let statusRow = UIView()
    private let inputRow = UIStackView()
    private let field = UIView()
    private let textView: EmoteTextView
    private let emoteButton = EmoteToggleButton()
    private let sendButton = SendButton()
    private var fieldCap: NSLayoutConstraint!
    private var lastFieldHeight: CGFloat = 0
    private var lastFieldWidth: CGFloat = 0
    private var lastLandscape: Bool?

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
    private var isSending = false
    private var inFlight: String?
    private var dropReason: String?
    private var slowModeSeconds: Int?
    private var cooldownEnds: Date?
    private var cooldownTimer: Timer?

    init(images: ImageLoading) {
        self.images = images
        self.textView = EmoteTextView(images: images)
        self.autocomplete = EmoteAutocompleteView(images: images, onSelect: { _ in })
        super.init(frame: .zero)
        setUp()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCatalog(_ catalog: EmoteCatalog) {
        self.catalog = catalog
        textView.setCatalog(catalog)
    }

    func setEmoteKeyboardPageLeading(_ inset: CGFloat) {
        emoteKeyboard.setPageLeading(inset)
    }

    /// Clears the field the moment a message goes out, so the next one can be typed while it travels.
    func beginSending(_ text: String) {
        isSending = true
        inFlight = text
        dropReason = nil
        textView.reset()
        refreshAutocomplete()
        updateFieldHeight()
    }

    /// The message went through; in slow mode the next one waits for the countdown.
    func sendSucceeded(startsCooldown: Bool = true) {
        isSending = false
        inFlight = nil
        if startsCooldown, let seconds = slowModeSeconds, seconds > 0, !isExemptFromSlowMode {
            startCooldown(seconds)
        }
        updateSendState()
        updateStatus()
    }

    /// The message did not go out: it comes back into the field unless something new was typed meanwhile, and the
    /// reason shows under it.
    func sendFailed(_ reason: String) {
        isSending = false
        if let inFlight {
            let typedMeanwhile = textView.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            textView.setText(typedMeanwhile.isEmpty ? inFlight : inFlight + " " + typedMeanwhile)
            refreshAutocomplete()
            updateFieldHeight()
        }
        inFlight = nil
        showDropReason(reason)
        updateSendState()
    }

    func setRoomState(_ state: RoomState) {
        textView.placeholder = Self.placeholder(for: state)
        slowModeSeconds = state.slowMode
        if state.slowMode == nil { endCooldown() }
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

    /// Shows why a message did not go out, with a shake of the field; nil clears it.
    func showDropReason(_ reason: String?) {
        dropReason = reason
        updateStatus()
        guard let reason else { return }
        shakeField()
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Message not sent. \(reason)"))
    }

    func clear() {
        textView.reset()
        dropReason = nil
        refreshAutocomplete()
        updateFieldHeight()
    }

    func insertEmote(_ name: String) {
        textView.insertEmoteName(name)
        refreshAutocomplete()
    }

    func insertMention(_ login: String) {
        textView.insertEmoteName("@\(login)")
        refreshAutocomplete()
    }

    private func handleBackspace() {
        textView.deleteBackward()
        refreshAutocomplete()
    }

    #if DEBUG
    func showEmoteKeyboardForScreenshot() {
        showEmoteKeyboard()
    }

    /// Types a draft into the field, for a screenshot of the composer at work.
    func typeForScreenshot(_ text: String) {
        textView.insertEmoteName(text)
        refreshAutocomplete()
    }
    #endif

    private func toggleEmoteKeyboard() {
        Haptics.selection()
        if showingEmoteKeyboard {
            switchToSystemKeyboard()
        } else {
            showEmoteKeyboard()
        }
    }

    private func showEmoteKeyboard() {
        showingEmoteKeyboard = true
        emoteKeyboard.setCatalog(catalog)
        emoteKeyboard.fitHeight(landscape: isLandscape)
        textView.inputView = emoteKeyboard
        emoteButton.setShowsKeyboard(true, animated: true)
        onEmoteKeyboardChanged?(true)
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
        emoteButton.setShowsKeyboard(false, animated: true)
        onEmoteKeyboardChanged?(false)
        if textView.isFirstResponder { textView.reloadInputViews() }
    }

    /// The emote keyboard takes the system keyboard's height, so switching between them does not move the chat.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard textView.isFirstResponder, !showingEmoteKeyboard,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let screen = window?.windowScene?.screen,
              frame.minY < screen.bounds.maxY, frame.height > 200 else { return }
        emoteKeyboard.setPreferredHeight(frame.height, landscape: isLandscape)
    }

    private var isLandscape: Bool {
        window?.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
    }

    func showReply(displayName: String, text: String) {
        replyPreview.configure(displayName: displayName, text: text)
        setArrangedHidden(replyPreview, false)
    }

    func hideReply() {
        setArrangedHidden(replyPreview, true)
    }

    /// The unsent message, for showing it where the composer folds away to.
    var draftText: String {
        textView.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the empty field says, room modes included.
    var placeholderText: String {
        textView.placeholder
    }

    /// Opens the composer straight onto the emote keyboard.
    func beginWithEmotes() {
        showEmoteKeyboard()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        textView.resignFirstResponder()
    }

    var isEditing: Bool {
        textView.isFirstResponder
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

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusRow.addSubview(statusLabel)
        statusRow.isHidden = true
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: statusRow.topAnchor, constant: 6),
            statusLabel.bottomAnchor.constraint(equalTo: statusRow.bottomAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor, constant: ChatMetrics.edge + ChatMetrics.fieldTextInsets.left),
            statusLabel.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor, constant: -ChatMetrics.edge)
        ])

        replyPreview.isHidden = true
        replyPreview.onCancel = { [weak self] in
            guard let self else { return }
            self.delegate?.chatInputDidCancelReply(self)
        }

        configureInputRow()

        container.addArrangedSubview(replyPreview)
        container.addArrangedSubview(autocomplete)
        container.addArrangedSubview(statusRow)
        container.addArrangedSubview(inputRow)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        swipeDown.direction = .down
        addGestureRecognizer(swipeDown)
    }

    private func configureInputRow() {
        let sendInset = (ChatMetrics.field - ChatMetrics.sendDiameter) / 2
        inputRow.axis = .horizontal
        inputRow.alignment = .bottom
        inputRow.spacing = ChatMetrics.rowSpacing - sendInset
        inputRow.isLayoutMarginsRelativeArrangement = true
        inputRow.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: ChatMetrics.composerVertical,
            leading: ChatMetrics.edge,
            bottom: ChatMetrics.composerVertical,
            trailing: ChatMetrics.edge - sendInset
        )

        field.backgroundColor = .tertiarySystemFill
        field.layer.cornerRadius = ChatMetrics.field / 2
        field.layer.cornerCurve = .continuous
        field.translatesAutoresizingMaskIntoConstraints = false
        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focusField))
        focusTap.cancelsTouchesInView = false
        focusTap.delegate = self
        field.addGestureRecognizer(focusTap)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.onTextChange = { [weak self] in
            guard let self else { return }
            if self.dropReason != nil { self.dropReason = nil }
            self.refreshAutocomplete()
            self.updateFieldHeight()
        }
        textView.onTextSizeChange = { [weak self] in self?.updateFieldHeight() }
        textView.onReturn = { [weak self] in self?.sendTapped() }
        textView.onBeginEditing = { [weak self] in self?.onEditingChanged?(true) }
        textView.onEndEditing = { [weak self] in
            self?.switchToSystemKeyboard()
            self?.onEditingChanged?(false)
        }
        textView.onTab = { [weak self] in self?.acceptFirstSuggestion() }
        textView.placeholder = String(localized: "Send a message")
        field.addSubview(textView)

        emoteButton.translatesAutoresizingMaskIntoConstraints = false
        emoteButton.addAction(UIAction { [weak self] _ in self?.toggleEmoteKeyboard() }, for: .primaryActionTriggered)
        field.addSubview(emoteButton)

        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .primaryActionTriggered)

        inputRow.addArrangedSubview(field)
        inputRow.addArrangedSubview(sendButton)

        fieldCap = textView.heightAnchor.constraint(equalToConstant: ChatMetrics.fieldMaxHeight)
        let emoteSide = ChatMetrics.field - 4
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: field.topAnchor),
            textView.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: ChatMetrics.field),
            emoteButton.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -2),
            emoteButton.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: -2),
            emoteButton.widthAnchor.constraint(equalToConstant: emoteSide),
            emoteButton.heightAnchor.constraint(equalToConstant: emoteSide)
        ])
    }

    /// The tap that focuses the field from its padding leaves the emote button's own taps alone.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }

    @objc private func focusField() {
        guard !textView.isFirstResponder else { return }
        textView.becomeFirstResponder()
    }

    @objc private func swipedDown() {
        guard textView.isFirstResponder else { return }
        textView.resignFirstResponder()
    }

    /// The field grows a line at a time with the draft, then scrolls inside itself once it reaches its cap.
    private func updateFieldHeight() {
        let width = textView.bounds.width
        guard width > 0 else { return }
        let fitting = ceil(textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let capped = fitting > ChatMetrics.fieldMaxHeight
        if capped != textView.isScrollEnabled {
            textView.isScrollEnabled = capped
            fieldCap.isActive = capped
        }
        if capped {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.textView.scrollRangeToVisible(self.textView.selectedRange)
            }
        }
        let height = min(max(fitting, ChatMetrics.field), ChatMetrics.fieldMaxHeight)
        guard abs(height - lastFieldHeight) > 0.5 else { return }
        let grows = lastFieldHeight > 0
        lastFieldHeight = height
        textView.invalidateIntrinsicContentSize()
        if grows { animateLayout() }
    }

    /// A new width can change how many lines the draft takes, and a new orientation the keyboard height the emote
    /// keyboard matches.
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = textView.bounds.width
        if lastFieldHeight == 0 || abs(width - lastFieldWidth) > 0.5 {
            lastFieldWidth = width
            updateFieldHeight()
        }
        let landscape = isLandscape
        if landscape != lastLandscape {
            lastLandscape = landscape
            if showingEmoteKeyboard, textView.isFirstResponder {
                emoteKeyboard.fitHeight(landscape: landscape)
                textView.reloadInputViews()
            }
        }
    }

    private func refreshAutocomplete() {
        updateSendState()
        updateStatus()
        let suggestions: [AutocompleteSuggestion]
        if let token = currentToken() {
            suggestions = delegate?.chatInput(self, suggestionsFor: token) ?? []
        } else {
            suggestions = []
        }
        let wasHidden = autocomplete.isHidden
        autocomplete.update(suggestions)
        textView.acceptsTab = !suggestions.isEmpty
        if wasHidden != suggestions.isEmpty {
            autocomplete.isHidden = wasHidden
            setArrangedHidden(autocomplete, suggestions.isEmpty)
        }
    }

    private func currentToken() -> AutocompleteToken? {
        let text = textView.plainText
        let caret = min(textView.plainCaretOffset, text.count)
        let caretIndex = text.index(text.startIndex, offsetBy: caret)
        let upToCaret = text[text.startIndex..<caretIndex]
        guard let last = upToCaret.last, !last.isWhitespace,
              let word = upToCaret.split(whereSeparator: { $0.isWhitespace }).last, word.count >= 2 else { return nil }
        let string = String(word)
        if string.hasPrefix("@") {
            return .mention(String(string.dropFirst()))
        }
        return .emote(string)
    }

    private func acceptFirstSuggestion() {
        guard let first = autocomplete.firstSuggestion else { return }
        insertSuggestion(first)
    }

    private func insertSuggestion(_ suggestion: AutocompleteSuggestion) {
        Haptics.selection()
        if case .emote(let emote) = suggestion { EmoteUsage.record(emote) }
        textView.replaceCurrentToken(with: suggestion.insertionText + " ")
        refreshAutocomplete()
        updateFieldHeight()
    }

    private var draft: String {
        textView.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendTapped() {
        let text = draft
        guard !isSending, !text.isEmpty else { return }
        guard cooldownRemaining == 0 || text.hasPrefix("/") else {
            Haptics.notify(.warning)
            return
        }
        guard text.count <= ChatMetrics.messageLimit else {
            Haptics.notify(.error)
            shakeField()
            return
        }
        dropReason = nil
        updateStatus()
        delegate?.chatInput(self, didSubmit: text)
    }

    private func updateSendState() {
        let length = draft.count
        let sendable = length > 0 && length <= ChatMetrics.messageLimit
        if isSending {
            sendButton.setMode(.sending)
        } else if sendable, cooldownRemaining == 0 || draft.hasPrefix("/") {
            sendButton.setMode(.ready)
        } else if cooldownRemaining > 0 {
            sendButton.setMode(.cooldown(cooldownRemaining))
        } else {
            sendButton.setMode(.empty)
        }
    }

    /// One line under the field's text edge for whatever needs saying: why a message failed, how close the draft is
    /// to Twitch's limit, or how long slow mode holds the next message.
    private func updateStatus() {
        let length = draft.count
        let remaining = ChatMetrics.messageLimit - length
        let text: String?
        let color: UIColor
        if let dropReason {
            text = dropReason
            color = Self.errorText
        } else if remaining < 0 {
            text = String(localized: "Over the limit: \(-remaining)")
            color = Self.errorText
        } else if remaining <= ChatMetrics.counterThreshold {
            text = String(localized: "Characters left: \(remaining)")
            color = Theme.secondaryText
        } else if cooldownRemaining > 0 {
            text = String(localized: "Slow mode: you can send again in \(cooldownRemaining)s")
            color = Self.slowModeText
        } else {
            text = nil
            color = Theme.secondaryText
        }
        statusLabel.text = text
        statusLabel.textColor = color
        if statusRow.isHidden != (text == nil) {
            setArrangedHidden(statusRow, text == nil)
        }
    }

    /// Status colors deep enough to read as small text on the light theme, the system hues on the dark one.
    private static let errorText = Theme.dynamic(light: UIColor(red: 0.77, green: 0.12, blue: 0.10, alpha: 1), dark: .systemRed)
    private static let slowModeText = Theme.dynamic(light: UIColor(red: 0.66, green: 0.33, blue: 0.0, alpha: 1), dark: .systemOrange)

    private var cooldownRemaining: Int {
        guard let cooldownEnds else { return 0 }
        return max(0, Int(ceil(cooldownEnds.timeIntervalSinceNow)))
    }

    private func startCooldown(_ seconds: Int) {
        cooldownEnds = Date().addingTimeInterval(TimeInterval(seconds))
        cooldownTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickCooldown() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cooldownTimer = timer
        tickCooldown()
    }

    private func tickCooldown() {
        if cooldownRemaining == 0 {
            endCooldown()
            return
        }
        updateSendState()
        updateStatus()
    }

    private func endCooldown() {
        guard cooldownEnds != nil else { return }
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        cooldownEnds = nil
        updateSendState()
        updateStatus()
    }

    private func shakeField() {
        guard !Motion.reduced else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -9, 8, -6, 4, -2, 0]
        shake.duration = 0.42
        shake.timingFunction = CAMediaTimingFunction(name: .easeOut)
        field.layer.add(shake, forKey: "shake")
    }

    private func setArrangedHidden(_ view: UIView, _ hidden: Bool) {
        guard view.isHidden != hidden else { return }
        guard window != nil, !Motion.reduced else {
            view.isHidden = hidden
            view.alpha = hidden ? 0 : 1
            return
        }
        if !hidden { view.alpha = 0 }
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            view.isHidden = hidden
            view.alpha = hidden ? 0 : 1
            self.superview?.layoutIfNeeded()
        }
    }

    private func animateLayout() {
        guard window != nil, !Motion.reduced else {
            superview?.layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.24, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.superview?.layoutIfNeeded()
        }
    }
}
