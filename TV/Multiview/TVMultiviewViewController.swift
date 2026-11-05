import AVFoundation
import UIKit
import EmbrCore
import MidgarCore

/// Up to four live streams at once. Sound follows focus: move between tiles with the remote and you hear the one you
/// are on. Click a tile to make it large, click it again to go back to the grid; press and hold for its menu (full
/// screen, swap, remove). Play/Pause pauses or resumes every tile; Menu closes multiview.
final class TVMultiviewViewController: UIViewController {
    static func present(starting streams: [LiveStream], from presenter: UIViewController) {
        TVPlaybackCoordinator.endActive()
        let multiview = TVMultiviewViewController(streams: streams)
        multiview.modalPresentationStyle = .fullScreen
        TVRouter.topmost(from: presenter).present(multiview, animated: true)
    }

    private var tiles: [TVMultiviewTile] = []
    private let addTile = TVMultiviewAddTile()
    private var featured: Int?
    private var paused = false
    private let spacing: CGFloat = 20

    init(streams: [LiveStream]) {
        super.init(nibName: nil, bundle: nil)
        for stream in streams.prefix(MultiviewLayout.maximumStreams) {
            tiles.append(makeTile(stream))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        tiles.forEach(view.addSubview)
        view.addSubview(addTile)
        addTile.onSelect = { [weak self] in self?.pickStream(replacing: nil) }
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if tiles.count == 1 {
            pickStream(replacing: nil)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        tiles.forEach { $0.stop() }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTiles(animated: false)
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        tiles.isEmpty ? [addTile] : [tiles[featured ?? 0]]
    }

    private var showsAddTile: Bool {
        tiles.count < MultiviewLayout.maximumStreams
    }

    private func layoutTiles(animated: Bool) {
        let slots = tiles.count + (showsAddTile ? 1 : 0)
        let bounds = view.bounds.insetBy(dx: 60, dy: 40)
        let frames = MultiviewLayout.frames(count: slots, featured: featured, in: bounds, spacing: spacing)
        let apply = {
            for (index, tile) in self.tiles.enumerated() where index < frames.count {
                tile.frame = frames[index]
            }
            self.addTile.isHidden = !self.showsAddTile
            if self.showsAddTile, let last = frames.last {
                self.addTile.frame = last
            }
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            apply()
            return
        }
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: apply)
    }

    private func makeTile(_ stream: LiveStream) -> TVMultiviewTile {
        let tile = TVMultiviewTile(stream: stream)
        tile.onSelect = { [weak self, weak tile] in
            guard let self, let tile else { return }
            self.toggleFeatured(tile)
        }
        tile.onMenu = { [weak self, weak tile] in
            guard let self, let tile else { return }
            self.showMenu(for: tile)
        }
        tile.onFocus = { [weak self, weak tile] focused in
            guard focused, let tile else { return }
            self?.giveSound(to: tile)
        }
        tile.start(qualityCap: qualityCap)
        return tile
    }

    /// Smaller renditions once more streams share the screen, so four decodes stay smooth.
    private var qualityCap: CGSize {
        tiles.count >= 2 ? CGSize(width: 960, height: 540) : CGSize(width: 1280, height: 720)
    }

    private func giveSound(to tile: TVMultiviewTile) {
        for other in tiles {
            other.setAudible(other === tile)
        }
    }

    private func toggleFeatured(_ tile: TVMultiviewTile) {
        guard let index = tiles.firstIndex(where: { $0 === tile }), tiles.count > 1 else { return }
        featured = featured == index ? nil : index
        layoutTiles(animated: true)
    }

    private func add(_ stream: LiveStream, replacing tile: TVMultiviewTile?) {
        if let tile, let index = tiles.firstIndex(where: { $0 === tile }) {
            tile.stop()
            tile.removeFromSuperview()
            let replacement = makeTile(stream)
            tiles[index] = replacement
            view.addSubview(replacement)
        } else if tiles.count < MultiviewLayout.maximumStreams {
            let added = makeTile(stream)
            tiles.append(added)
            view.addSubview(added)
        }
        tiles.forEach { $0.capQuality(qualityCap) }
        layoutTiles(animated: true)
        setNeedsFocusUpdate()
    }

    private func remove(_ tile: TVMultiviewTile) {
        guard let index = tiles.firstIndex(where: { $0 === tile }) else { return }
        tile.stop()
        tile.removeFromSuperview()
        tiles.remove(at: index)
        featured = nil
        if tiles.isEmpty {
            dismiss(animated: true)
            return
        }
        tiles.forEach { $0.capQuality(qualityCap) }
        layoutTiles(animated: true)
        setNeedsFocusUpdate()
    }

    private func pickStream(replacing tile: TVMultiviewTile?) {
        let exclude = Set(tiles.map(\.stream.userID))
        let picker = TVStreamPickerViewController(excluding: exclude) { [weak self] stream in
            self?.add(stream, replacing: tile)
        }
        present(picker, animated: true)
    }

    private func showMenu(for tile: TVMultiviewTile) {
        let stream = tile.stream
        let sheet = UIAlertController(title: stream.userName, message: stream.title, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Watch Full Screen"), style: .default) { [weak self] _ in
            guard let self else { return }
            let presenter = self.presentingViewController
            self.dismiss(animated: true) {
                guard let presenter else { return }
                TVPlaybackCoordinator.play(.live(stream), from: presenter)
            }
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Swap Stream"), style: .default) { [weak self] _ in
            self?.pickStream(replacing: tile)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Remove"), style: .destructive) { [weak self] _ in
            self?.remove(tile)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.contains(where: { $0.type == .playPause }) else {
            super.pressesBegan(presses, with: event)
            return
        }
        paused.toggle()
        tiles.forEach { paused ? $0.pause() : $0.resume() }
    }
}

/// One stream of the multiview: its own player, focusable, with a name tag and a speaker when it has the sound.
final class TVMultiviewTile: UIView {
    let stream: LiveStream
    var onSelect: (() -> Void)?
    var onMenu: (() -> Void)?
    var onFocus: ((Bool) -> Void)?

    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private let nameLabel = TVPaddedLabel()
    private let speaker = UIImageView(image: UIImage(systemName: "speaker.wave.2.fill"))
    private let spinner = UIActivityIndicatorView(style: .large)
    private var resolveTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var readyObservation: NSKeyValueObservation?
    private var cap = CGSize(width: 1280, height: 720)
    private var heldForMenu = false

    init(stream: LiveStream) {
        self.stream = stream
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.08, alpha: 1)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderColor = Theme.accent.cgColor
        layer.borderWidth = 0

        player.isMuted = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        addSubview(spinner)

        nameLabel.text = stream.userName.isEmpty ? stream.userLogin : stream.userName
        nameLabel.font = TVFont.bold(.caption1)
        nameLabel.textColor = .white
        nameLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        nameLabel.layer.cornerRadius = 8
        nameLabel.layer.masksToBounds = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        speaker.tintColor = .white
        speaker.isHidden = true
        speaker.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        speaker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speaker)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            speaker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            speaker.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])

        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor in if ready { self?.spinner.stopAnimating() } }
        }
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        addGestureRecognizer(hold)
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "\(nameLabel.text ?? ""), live")
        accessibilityHint = String(localized: "Click to make it large. Press and hold for options.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { true }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            self.layer.borderWidth = focused ? 6 : 0
            self.transform = focused ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
        }
        if focused || context.previouslyFocusedView === self {
            onFocus?(focused)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard presses.contains(where: { $0.type == .select }) else {
            super.pressesEnded(presses, with: event)
            return
        }
        if heldForMenu {
            heldForMenu = false
        } else {
            onSelect?()
        }
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        heldForMenu = true
        onMenu?()
    }

    func start(qualityCap: CGSize) {
        cap = qualityCap
        resolve()
    }

    func capQuality(_ size: CGSize) {
        cap = size
        player.currentItem?.preferredMaximumResolution = size
    }

    func setAudible(_ audible: Bool) {
        player.isMuted = !audible
        speaker.isHidden = !audible
    }

    func pause() {
        player.pause()
    }

    func resume() {
        if let item = player.currentItem, let edge = item.seekableTimeRanges.last?.timeRangeValue.end {
            player.seek(to: edge)
        }
        player.play()
    }

    func stop() {
        resolveTask?.cancel()
        refreshTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func resolve() {
        resolveTask?.cancel()
        let login = stream.userLogin
        #if DEBUG
        if DemoWorld.isActive {
            playerLayer.contents = DemoArt.stream(key: login, size: CGSize(width: 1280, height: 720), facecam: true).cgImage
            playerLayer.contentsGravity = .resizeAspect
            spinner.stopAnimating()
            return
        }
        #endif
        resolveTask = Task { [weak self] in
            do {
                let resolution = try await AppContainer.shared.playback.resolveLive(channelLogin: login)
                guard !Task.isCancelled, let self else { return }
                let item = AVPlayerItem(url: resolution.masterPlaylistURL)
                item.preferredMaximumResolution = self.cap
                item.automaticallyPreservesTimeOffsetFromLive = true
                self.player.replaceCurrentItem(with: item)
                self.player.play()
                self.scheduleRefresh(resolution.expiresAt)
            } catch {
                MidgarLog.notice("multiview: \(login) failed to resolve: \(error)", category: .playback)
                self?.spinner.stopAnimating()
                self?.nameLabel.text = String(localized: "\(login) · offline")
            }
        }
    }

    private func scheduleRefresh(_ expiresAt: Date?) {
        refreshTask?.cancel()
        let delay = expiresAt.map { max(60, $0.timeIntervalSinceNow - 120) } ?? 50 * 60
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.resolve()
        }
    }
}

/// The empty slot of a multiview with room for another stream.
final class TVMultiviewAddTile: UIView {
    var onSelect: (() -> Void)?
    private let label = UILabel()
    private let symbol = UIImageView(image: UIImage(systemName: "plus.circle.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.08)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderColor = Theme.accent.cgColor
        symbol.tintColor = UIColor(white: 1, alpha: 0.8)
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        label.text = String(localized: "Add a Stream")
        label.font = TVFont.headline
        label.textColor = UIColor(white: 1, alpha: 0.8)
        let stack = UIStackView(arrangedSubviews: [symbol, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = label.text
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { !isHidden }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let focused = context.nextFocusedView === self
        coordinator.addCoordinatedAnimations {
            self.layer.borderWidth = focused ? 6 : 0
            self.backgroundColor = UIColor(white: 1, alpha: focused ? 0.16 : 0.08)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }) {
            onSelect?()
        } else {
            super.pressesEnded(presses, with: event)
        }
    }
}
