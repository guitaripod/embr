import AVFoundation
import Combine
import UIKit
import EmbrCore
import MidgarCore

/// A channel's clips as a vertical feed: one clip fills the screen and plays on a loop, a swipe moves to the next one,
/// which is already buffering. The feed starts on the clip that was tapped and keeps loading the channel's clips as the
/// viewer nears the end. Sound remembers its last setting; a tap pauses; the line at the bottom scrubs. Swiping down
/// past the first clip, the close button or Escape leave.
@MainActor
final class ClipFeedViewController: UIViewController {
    private var clips: [Clip]
    private var currentIndex: Int
    private let pager: ClipPager?
    private let images: ImageLoading
    private let sources: ClipSourceCache
    private let hidden: HiddenClips
    private let filter: ContentFilter
    private let players = ClipPlayerWindow()
    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let closeButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private var cancellables = Set<AnyCancellable>()
    private var lastLaidOutSize: CGSize = .zero
    private var activationTask: Task<Void, Never>?
    private var loadingMore = false
    private var hasAppeared = false
    private var dismissing = false

    private static let neighbours = 1
    private static let lookahead = 3
    private static let dismissPull: CGFloat = 110

    init(
        clips: [Clip],
        startIndex: Int,
        pager: ClipPager?,
        images: ImageLoading = ImageLoader.shared,
        sources: ClipSourceCache = .shared,
        hidden: HiddenClips = HiddenClips(),
        settings: SettingsStore = .shared
    ) {
        let startID = clips.indices.contains(startIndex) ? clips[startIndex].id : nil
        let visible = hidden.visible(clips)
        self.clips = visible
        currentIndex = startID.flatMap { id in visible.firstIndex { $0.id == id } } ?? min(max(startIndex, 0), max(visible.count - 1, 0))
        self.pager = pager
        self.images = images
        self.sources = sources
        self.hidden = hidden
        filter = settings.current.makeContentFilter()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { OrientationCoordinator.mask }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildCollectionView()
        buildChrome()
        bind()
        let upcoming = Array(clips.dropFirst(currentIndex).prefix(Self.lookahead + 1))
        Task { await sources.prefetch(upcoming) }
        MidgarLog.info("clip feed opened at \(currentIndex) of \(clips.count)", category: .playback)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = collectionView.bounds.size
        guard size != lastLaidOutSize, size.width > 0, size.height > 0 else { return }
        lastLaidOutSize = size
        layout.itemSize = size
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        collectionView.contentOffset = CGPoint(x: 0, y: CGFloat(currentIndex) * size.height)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        activateAudioSession()
        if hasAppeared {
            players.resumeIfAllowed()
        } else {
            hasAppeared = true
            activate(currentIndex)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        players.suspend()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        activationTask?.cancel()
        players.tearDown()
    }

    override var keyCommands: [UIKeyCommand]? {
        let next = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(nextClip))
        next.discoverabilityTitle = String(localized: "Next Clip", comment: "Keyboard shortcut in the clip feed")
        let previous = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(previousClip))
        previous.discoverabilityTitle = String(localized: "Previous Clip", comment: "Keyboard shortcut in the clip feed")
        let pause = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(togglePlaybackKey))
        pause.discoverabilityTitle = String(localized: "Play or Pause", comment: "Keyboard shortcut in the clip feed")
        let mute = UIKeyCommand(input: "m", modifierFlags: [], action: #selector(toggleMute))
        mute.discoverabilityTitle = String(localized: "Mute or Unmute", comment: "Keyboard shortcut in the clip feed")
        let close = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close))
        close.discoverabilityTitle = String(localized: "Close", comment: "Keyboard shortcut in the clip feed")
        [next, previous, pause, mute, close].forEach { $0.wantsPriorityOverSystemBehavior = true }
        return [next, previous, pause, mute, close]
    }

    private func buildCollectionView() {
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.decelerationRate = .fast
        collectionView.register(ClipFeedCell.self, forCellWithReuseIdentifier: ClipFeedCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func buildChrome() {
        configureChromeButton(closeButton, symbol: "xmark", label: String(localized: "Close", comment: "Clip feed close button"))
        closeButton.addTarget(self, action: #selector(close), for: .primaryActionTriggered)
        configureChromeButton(muteButton, symbol: muteSymbol, label: muteLabel)
        muteButton.addTarget(self, action: #selector(toggleMute), for: .primaryActionTriggered)
        titleLabel.text = String(localized: "Clips", comment: "Clip feed title")
        titleLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .bold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.accessibilityTraits = .header
        [closeButton, muteButton, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        let guide = view.safeAreaLayoutGuide
        let readable = view.readableContentGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
            closeButton.leadingAnchor.constraint(equalTo: readable.leadingAnchor, constant: -8),
            muteButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            muteButton.trailingAnchor.constraint(equalTo: readable.trailingAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
    }

    private func configureChromeButton(_ button: UIButton, symbol: String, label: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.configuration = configuration
        button.accessibilityLabel = label
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowRadius = 6
        button.layer.shadowOffset = .zero
    }

    private var muteSymbol: String { players.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill" }
    private var muteLabel: String {
        players.isMuted
            ? String(localized: "Unmute", comment: "Clip feed sound button")
            : String(localized: "Mute", comment: "Clip feed sound button")
    }

    private func bind() {
        players.progress
            .sink { [weak self] progress in self?.cell(for: progress.clipID)?.setProgress(progress.fraction) }
            .store(in: &cancellables)
        players.failed
            .sink { [weak self] clipID in self?.handleFailure(clipID) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.players.suspend() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                self.players.resumeIfAllowed()
            }
            .store(in: &cancellables)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            MidgarLog.notice("clip feed audio session not activated: \(error)", category: .playback)
        }
    }

    /// Makes the clip at `index` the one on screen: it plays, its neighbours get players and start buffering, the next
    /// few resolve their addresses, and every other player is let go.
    private func activate(_ index: Int) {
        guard clips.indices.contains(index) else { return }
        currentIndex = index
        let clip = clips[index]
        let window = neighbourhood(of: index)
        players.keep(only: Set(window.map(\.id)))
        let upcoming = Array(clips.dropFirst(index + 1).prefix(Self.lookahead))
        Task { await sources.prefetch(upcoming) }
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            guard let self else { return }
            await self.preparePlayer(for: clip, makeActive: true)
            for neighbour in window where neighbour.id != clip.id {
                guard !Task.isCancelled else { return }
                await self.preparePlayer(for: neighbour, makeActive: false)
            }
        }
        loadMoreIfNeeded(near: index)
    }

    private func neighbourhood(of index: Int) -> [Clip] {
        let lower = max(0, index - Self.neighbours)
        let upper = min(clips.count - 1, index + Self.neighbours)
        guard lower <= upper else { return [] }
        return Array(clips[lower...upper])
    }

    private func preparePlayer(for clip: Clip, makeActive: Bool) async {
        guard let url = await sources.url(for: clip) else {
            cell(for: clip.id)?.showError(true)
            return
        }
        guard !Task.isCancelled else { return }
        let player = players.player(for: clip.id, url: url)
        if let cell = cell(for: clip.id), !cell.hasPlayer {
            cell.attach(player)
        }
        guard makeActive, clips.indices.contains(currentIndex), clips[currentIndex].id == clip.id else { return }
        players.activate(clip.id)
        cell(for: clip.id)?.showPaused(false, animated: false)
    }

    private func handleFailure(_ clipID: String) {
        Task { await sources.forget(clipID) }
        cell(for: clipID)?.showError(true)
    }

    private func loadMoreIfNeeded(near index: Int) {
        guard let pager, pager.hasMore, !loadingMore, index >= clips.count - 4 else { return }
        loadingMore = true
        Task { [weak self] in
            guard let self else { return }
            let fresh = await pager.next()
            self.loadingMore = false
            let known = Set(self.clips.map(\.id))
            let added = self.hidden.visible(fresh).filter { !known.contains($0.id) }
            guard !added.isEmpty else { return }
            let start = self.clips.count
            self.clips.append(contentsOf: added)
            let paths = (start..<self.clips.count).map { IndexPath(item: $0, section: 0) }
            UIView.performWithoutAnimation { self.collectionView.insertItems(at: paths) }
            MidgarLog.info("clip feed loaded \(added.count) more, \(self.clips.count) in all", category: .playback)
        }
    }

    private func cell(for clipID: String) -> ClipFeedCell? {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? ClipFeedCell
    }

    private func settle() {
        let height = collectionView.bounds.height
        guard height > 0 else { return }
        let index = Int((collectionView.contentOffset.y / height).rounded())
        guard clips.indices.contains(index), index != currentIndex else { return }
        Haptics.selection()
        activate(index)
    }

    private func move(by delta: Int) -> Bool {
        let target = currentIndex + delta
        guard clips.indices.contains(target) else { return false }
        collectionView.setContentOffset(CGPoint(x: 0, y: CGFloat(target) * collectionView.bounds.height), animated: !UIAccessibility.isReduceMotionEnabled)
        if UIAccessibility.isReduceMotionEnabled { activate(target) }
        UIAccessibility.post(notification: .pageScrolled, argument: String(localized: "Clip \(target + 1) of \(clips.count)", comment: "VoiceOver page announcement in the clip feed"))
        return true
    }

    @objc private func nextClip() { _ = move(by: 1) }
    @objc private func previousClip() { _ = move(by: -1) }

    @objc private func togglePlaybackKey() {
        guard let cell = cell(for: clips[currentIndex].id) else { return }
        clipCellDidTogglePlayback(cell)
    }

    @objc private func toggleMute() {
        players.setMuted(!players.isMuted)
        configureChromeButton(muteButton, symbol: muteSymbol, label: muteLabel)
        Haptics.impact(.light)
    }

    @objc private func close() {
        guard !dismissing else { return }
        dismissing = true
        players.suspend()
        dismiss(animated: true)
    }
}

extension ClipFeedViewController: UICollectionViewDataSource, UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        clips.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ClipFeedCell.reuseIdentifier, for: indexPath) as? ClipFeedCell else {
            return UICollectionViewCell()
        }
        let clip = clips[indexPath.item]
        cell.delegate = self
        cell.configure(with: clip, images: images, hidesTitle: filter.shouldHide(clip.title))
        if let player = players.existingPlayer(for: clip.id) {
            cell.attach(player)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap { clips.indices.contains($0.item) ? clips[$0.item].thumbnailURL : nil }
        images.prefetch(urls)
    }
}

extension ClipFeedViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? ClipFeedCell, clips.indices.contains(indexPath.item) else { return }
        if !cell.hasPlayer, let player = players.existingPlayer(for: clips[indexPath.item].id) {
            cell.attach(player)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? ClipFeedCell)?.attach(nil)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        settle()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if currentIndex == 0, scrollView.contentOffset.y < -Self.dismissPull {
            close()
        }
    }
}

extension ClipFeedViewController: ClipFeedCellDelegate {
    func clipCellDidTogglePlayback(_ cell: ClipFeedCell) {
        guard let clip = cell.clip, clips.indices.contains(currentIndex), clips[currentIndex].id == clip.id else { return }
        players.togglePlayback()
        cell.showPaused(!players.isPlaying, animated: true)
        Haptics.impact(.light)
    }

    func clipCellDidTapShare(_ cell: ClipFeedCell, clip: Clip) {
        guard let url = clip.url ?? URL(string: "https://clips.twitch.tv/\(clip.id)") else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = cell
        sheet.popoverPresentationController?.sourceRect = CGRect(x: cell.bounds.maxX - 60, y: cell.bounds.maxY - 160, width: 48, height: 48)
        present(sheet, animated: true)
    }

    func clipCellDidTapMore(_ cell: ClipFeedCell, clip: Clip) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        if let url = clip.url {
            sheet.addAction(UIAlertAction(title: String(localized: "Copy Link", comment: "Clip feed menu"), style: .default) { _ in
                UIPasteboard.general.url = url
                Haptics.notify(.success)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Open on Twitch", comment: "Clip feed menu"), style: .default) { [weak self] _ in
                self?.openWebLink(url)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Report Clip", comment: "Clip feed menu"), style: .destructive) { [weak self] _ in
            self?.report(clip)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = cell
        sheet.popoverPresentationController?.sourceRect = CGRect(x: cell.bounds.maxX - 60, y: cell.bounds.maxY - 110, width: 48, height: 48)
        present(sheet, animated: true)
    }

    /// Sends the clip to Embr's review queue and takes it out of the feed and every clip list on this device
    /// (App Store Guideline 1.2), moving on to the next clip.
    private func report(_ clip: Clip) {
        hidden.hide(clip.id)
        Task {
            await ReportClient.shared.submit(
                WorkerAPI.ReportRequest(
                    channel: clip.broadcasterName,
                    messageID: "clip:\(clip.id)",
                    authorID: nil,
                    authorLogin: clip.creatorName,
                    reason: "Clip reported",
                    text: clip.title
                )
            )
        }
        Haptics.notify(.success)
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Clip reported and hidden.", comment: "VoiceOver announcement after reporting a clip"))
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips.remove(at: index)
        players.keep(only: Set(neighbourhood(of: min(currentIndex, max(clips.count - 1, 0))).map(\.id)))
        collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        guard !clips.isEmpty else {
            close()
            return
        }
        let next = min(index, clips.count - 1)
        currentIndex = -1
        collectionView.layoutIfNeeded()
        collectionView.contentOffset = CGPoint(x: 0, y: CGFloat(next) * collectionView.bounds.height)
        activate(next)
    }

    func clipCellDidRequestRetry(_ cell: ClipFeedCell, clip: Clip) {
        Task { [weak self] in
            guard let self else { return }
            await self.sources.forget(clip.id)
            self.players.keep(only: Set(self.neighbourhood(of: self.currentIndex).map(\.id)).subtracting([clip.id]))
            cell.attach(nil)
            await self.preparePlayer(for: clip, makeActive: self.clips[self.currentIndex].id == clip.id)
        }
    }

    func clipCell(_ cell: ClipFeedCell, didScrubTo fraction: Double, clip: Clip) {
        players.seek(clip.id, to: fraction)
    }

    func clipCell(_ cell: ClipFeedCell, scrollBy direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .up, .next: move(by: 1)
        case .down, .previous: move(by: -1)
        default: false
        }
    }
}

/// The rest of a channel's clips, a page at a time, for the feed to keep going past what the list had loaded.
@MainActor
final class ClipPager {
    private let api: TwitchAPIProviding
    private let broadcasterID: String
    private var cursor: String?
    private(set) var hasMore: Bool

    init(api: TwitchAPIProviding, broadcasterID: String, cursor: String?, hasMore: Bool) {
        self.api = api
        self.broadcasterID = broadcasterID
        self.cursor = cursor
        self.hasMore = hasMore && cursor != nil
    }

    func next() async -> [Clip] {
        guard hasMore else { return [] }
        do {
            let page = try await api.clips(broadcasterID: broadcasterID, after: cursor, first: 20)
            cursor = page.cursor
            hasMore = page.cursor != nil
            return page.items
        } catch {
            MidgarLog.notice("clip feed page for \(broadcasterID) failed: \(error)", category: .api)
            return []
        }
    }
}
