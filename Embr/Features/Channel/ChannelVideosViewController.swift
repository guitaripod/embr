import UIKit
import EmbrCore

@MainActor
final class ChannelVideosViewController: UIViewController {
    private enum Item: Hashable {
        case vod(VideoOnDemand)
        case clip(Clip)
        case schedule(ScheduleSegment)
    }

    private let broadcasterID: String
    private let api: TwitchAPIProviding

    private let segmented = UISegmentedControl(items: [String(localized: "Videos"), String(localized: "Clips"), String(localized: "Schedule")])
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private let spinner = UIActivityIndicatorView(style: .large)
    private let emptyView = EmptyStateView(symbol: "film.stack", message: String(localized: "Nothing here yet."))

    private var vods: [VideoOnDemand] = []
    private var clips: [Clip] = []
    private var schedule: [ScheduleSegment] = []
    private var vodCursor: String?
    private var clipCursor: String?
    private var vodHasMore = true
    private var clipHasMore = true
    private var scheduleLoaded = false
    private var scheduleFailed = false
    private var loadingVods = false
    private var loadingClips = false
    private var loadingSchedule = false
    private var resolvingClip = false

    private var showingClips: Bool { segmented.selectedSegmentIndex == 1 }
    private var showingSchedule: Bool { segmented.selectedSegmentIndex == 2 }

    init(broadcasterID: String, channelName: String, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.broadcasterID = broadcasterID
        self.api = api
        super.init(nibName: nil, bundle: nil)
        title = channelName
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        navigationItem.titleView = segmented
        setUpCollectionView()
        setUpDataSource()
        setUpStates()
        load()
    }

    @objc private func segmentChanged() {
        Haptics.selection()
        if needsLoad { load() } else { render() }
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }

    private var needsLoad: Bool {
        if showingSchedule { return !scheduleLoaded && !loadingSchedule }
        if showingClips { return clips.isEmpty && !loadingClips }
        return vods.isEmpty && !loadingVods
    }

    private func setUpCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.backgroundColor = .clear
        config.showsSeparators = false
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setUpDataSource() {
        let vodReg = UICollectionView.CellRegistration<MediaRowCell, VideoOnDemand> { cell, _, vod in
            cell.configure(
                thumbnail: MediaRowCell.thumbnailURL(vod.thumbnailURLTemplate),
                title: vod.title,
                meta: [MediaRowCell.relative(vod.publishedAt), MediaRowCell.views(vod.viewCount)].joined(separator: "  ·  "),
                duration: MediaRowCell.duration(Double(vod.durationSeconds))
            )
        }
        let clipReg = UICollectionView.CellRegistration<MediaRowCell, Clip> { cell, _, clip in
            cell.configure(
                thumbnail: clip.thumbnailURL,
                title: clip.title,
                meta: [String(localized: "clipped by \(clip.creatorName)"), MediaRowCell.views(clip.viewCount)].joined(separator: "  ·  "),
                duration: MediaRowCell.duration(clip.duration)
            )
        }
        let scheduleReg = UICollectionView.CellRegistration<ScheduleRowCell, ScheduleSegment> { cell, _, segment in
            cell.configure(with: segment)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .vod(let vod):
                return collectionView.dequeueConfiguredReusableCell(using: vodReg, for: indexPath, item: vod)
            case .clip(let clip):
                return collectionView.dequeueConfiguredReusableCell(using: clipReg, for: indexPath, item: clip)
            case .schedule(let segment):
                return collectionView.dequeueConfiguredReusableCell(using: scheduleReg, for: indexPath, item: segment)
            }
        }
    }

    private func setUpStates() {
        for v in [spinner, emptyView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
            NSLayoutConstraint.activate([
                v.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                v.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
        emptyView.isHidden = true
        spinner.hidesWhenStopped = true
    }

    private func render() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0])
        let items: [Item]
        let empty: Bool
        let loadingNow: Bool
        let message: String
        if showingSchedule {
            items = schedule.map(Item.schedule)
            empty = schedule.isEmpty
            loadingNow = loadingSchedule
            message = scheduleFailed ? String(localized: "Couldn't load the schedule.") : String(localized: "No upcoming streams scheduled.")
        } else if showingClips {
            items = clips.map(Item.clip)
            empty = clips.isEmpty
            loadingNow = loadingClips
            message = String(localized: "No clips yet.")
        } else {
            items = vods.map(Item.vod)
            empty = vods.isEmpty
            loadingNow = loadingVods
            message = String(localized: "No past broadcasts available.")
        }
        snapshot.appendItems(items, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.setMessage(message)
        emptyView.onRetry = (showingSchedule && scheduleFailed) ? { [weak self] in self?.load() } : nil
        if loadingNow && empty { spinner.startAnimating() } else { spinner.stopAnimating() }
        emptyView.isHidden = !empty || loadingNow
    }

    private func load() {
        if showingSchedule { loadSchedule(); return }
        let clipsMode = showingClips
        if clipsMode {
            guard !loadingClips, clipHasMore else { return }
            loadingClips = true
        } else {
            guard !loadingVods, vodHasMore else { return }
            loadingVods = true
        }
        render()
        Task { [weak self] in
            guard let self else { return }
            do {
                if clipsMode {
                    let page = try await self.api.clips(broadcasterID: self.broadcasterID, after: self.clipCursor, first: 20)
                    self.clipCursor = page.cursor
                    self.clipHasMore = page.cursor != nil
                    let known = Set(self.clips.map(\.id))
                    self.clips.append(contentsOf: page.items.filter { !known.contains($0.id) })
                } else {
                    let page = try await self.api.videos(userID: self.broadcasterID, after: self.vodCursor, first: 20)
                    self.vodCursor = page.cursor
                    self.vodHasMore = page.cursor != nil
                    let known = Set(self.vods.map(\.id))
                    self.vods.append(contentsOf: page.items.filter { !known.contains($0.id) })
                }
            } catch {
                AppLogger.shared.warn("media load \(self.broadcasterID) failed: \(error)", category: .api)
            }
            if clipsMode { self.loadingClips = false } else { self.loadingVods = false }
            self.render()
        }
    }

    private func loadSchedule() {
        guard !loadingSchedule, !scheduleLoaded else { return }
        loadingSchedule = true
        scheduleFailed = false
        render()
        Task { [weak self] in
            guard let self else { return }
            do {
                let segments = try await TwitchAPIClient.shared.schedule(broadcasterID: self.broadcasterID)
                self.schedule = segments.filter { $0.canceledUntil == nil }
                self.scheduleLoaded = true
                AppLogger.shared.info("schedule \(self.broadcasterID): \(self.schedule.count) segments", category: .api)
            } catch APIError.notFound {
                self.schedule = []
                self.scheduleLoaded = true
                AppLogger.shared.info("schedule \(self.broadcasterID): none published", category: .api)
            } catch {
                self.schedule = []
                self.scheduleFailed = true
                AppLogger.shared.warn("schedule \(self.broadcasterID) failed: \(error)", category: .api)
            }
            self.loadingSchedule = false
            self.render()
        }
    }
}

extension ChannelVideosViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        switch item {
        case .vod(let vod):
            navigationController?.pushViewController(VideoViewController(source: .vod(id: vod.id)), animated: true)
        case .clip(let clip):
            playClip(clip)
        case .schedule:
            break
        }
    }

    private func playClip(_ clip: Clip) {
        guard !resolvingClip else { return }
        resolvingClip = true
        let startedSpinner = !spinner.isAnimating
        if startedSpinner { spinner.startAnimating() }
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.resolvingClip = false
                if startedSpinner { self.spinner.stopAnimating() }
            }
            do {
                let url = try await PlaybackResolver.shared.resolveClip(slug: clip.id)
                self.navigationController?.pushViewController(VideoViewController(source: .clip(url: url)), animated: true)
            } catch {
                AppLogger.shared.warn("clip resolve \(clip.id) failed: \(error)", category: .playback)
                if let mp4 = MediaRowCell.clipMP4(from: clip.thumbnailURL) {
                    self.navigationController?.pushViewController(VideoViewController(source: .clip(url: mp4)), animated: true)
                } else {
                    let alert = UIAlertController(title: String(localized: "Clip Unavailable"), message: String(localized: "This clip can't be played right now."), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}

extension ChannelVideosViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard !showingSchedule else { return }
        guard let max = indexPaths.map(\.item).max() else { return }
        if max >= dataSource.snapshot().numberOfItems - 4 { load() }
    }
}

@MainActor
private final class MediaRowCell: UICollectionViewListCell {
    private let thumbnail = UIImageView()
    private let durationBadge = PaddedBadge()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let images = AppContainer.shared.images
    private var imageTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell().updated(for: state)
        background.backgroundColor = .clear
        backgroundConfiguration = background
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.contentView.alpha = self.isHighlighted ? 0.7 : 1
            }
        }
    }

    func configure(thumbnail url: URL?, title: String, meta: String, duration: String) {
        titleLabel.text = title
        metaLabel.text = meta
        durationBadge.text = duration
        durationBadge.isHidden = duration.isEmpty
        thumbnail.image = nil
        imageTask?.cancel()
        guard let url else { return }
        if let cached = images.cachedImage(for: url) { thumbnail.image = cached; return }
        imageTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: UIScreen.main.scale)
            guard !Task.isCancelled else { return }
            self?.thumbnail.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        thumbnail.image = nil
        contentView.alpha = 1
    }

    private func setUp() {
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.backgroundColor = Theme.surface
        thumbnail.layer.cornerRadius = 8
        thumbnail.layer.cornerCurve = .continuous
        thumbnail.translatesAutoresizingMaskIntoConstraints = false

        durationBadge.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2

        metaLabel.font = .systemFont(ofSize: 12, weight: .regular)
        metaLabel.textColor = Theme.secondaryText
        metaLabel.numberOfLines = 1

        let text = UIStackView(arrangedSubviews: [titleLabel, metaLabel])
        text.axis = .vertical
        text.spacing = 4
        text.alignment = .leading
        text.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        thumbnail.addSubview(durationBadge)
        contentView.addSubview(text)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            thumbnail.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            thumbnail.widthAnchor.constraint(equalToConstant: 142),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),
            durationBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -4),
            durationBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -4),
            text.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: thumbnail.centerYAnchor)
        ])
    }

    static func thumbnailURL(_ template: String) -> URL? {
        guard !template.isEmpty else { return nil }
        return URL(string: template
            .replacingOccurrences(of: "%{width}", with: "320")
            .replacingOccurrences(of: "%{height}", with: "180"))
    }

    static func clipMP4(from thumbnail: URL?) -> URL? {
        guard let raw = thumbnail?.absoluteString,
              let range = raw.range(of: "-preview-[0-9]+x[0-9]+\\.jpg", options: .regularExpression) else { return nil }
        return URL(string: raw.replacingCharacters(in: range, with: ".mp4"))
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func views(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(localized: "\(String(format: "%.1fM", Double(count) / 1_000_000)) views")
        }
        if count >= 1_000 {
            return String(localized: "\(String(format: "%.1fK", Double(count) / 1_000)) views")
        }
        return String(localized: "\(count) views")
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

@MainActor
private final class ScheduleRowCell: UICollectionViewListCell {
    private let dateBlock = UIView()
    private let weekdayLabel = UILabel()
    private let dayLabel = UILabel()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let metaLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell().updated(for: state)
        background.backgroundColor = .clear
        backgroundConfiguration = background
    }

    func configure(with segment: ScheduleSegment) {
        weekdayLabel.text = Self.weekday.string(from: segment.startTime).uppercased()
        dayLabel.text = Self.day.string(from: segment.startTime)
        titleLabel.text = segment.title.isEmpty ? (segment.categoryName ?? String(localized: "Scheduled stream")) : segment.title
        var time = Self.time.string(from: segment.startTime)
        if let end = segment.endTime { time += " – " + Self.time.string(from: end) }
        timeLabel.text = time
        var meta: [String] = []
        if let category = segment.categoryName, !category.isEmpty { meta.append(category) }
        if segment.isRecurring { meta.append(String(localized: "Weekly")) }
        metaLabel.text = meta.joined(separator: "  ·  ")
        metaLabel.isHidden = meta.isEmpty
    }

    private func setUp() {
        dateBlock.backgroundColor = Theme.accent.withAlphaComponent(0.15)
        dateBlock.layer.cornerRadius = 10
        dateBlock.layer.cornerCurve = .continuous
        dateBlock.translatesAutoresizingMaskIntoConstraints = false

        weekdayLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        weekdayLabel.textColor = Theme.accent
        weekdayLabel.textAlignment = .center
        dayLabel.font = .systemFont(ofSize: 20, weight: .bold)
        dayLabel.textColor = Theme.primaryText
        dayLabel.textAlignment = .center

        let dateStack = UIStackView(arrangedSubviews: [weekdayLabel, dayLabel])
        dateStack.axis = .vertical
        dateStack.alignment = .center
        dateStack.spacing = 0
        dateStack.translatesAutoresizingMaskIntoConstraints = false
        dateBlock.addSubview(dateStack)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        timeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        timeLabel.textColor = Theme.secondaryText
        metaLabel.font = .systemFont(ofSize: 12, weight: .regular)
        metaLabel.textColor = Theme.accent

        let text = UIStackView(arrangedSubviews: [titleLabel, timeLabel, metaLabel])
        text.axis = .vertical
        text.spacing = 3
        text.alignment = .leading
        text.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(dateBlock)
        contentView.addSubview(text)

        NSLayoutConstraint.activate([
            dateBlock.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            dateBlock.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dateBlock.widthAnchor.constraint(equalToConstant: 54),
            dateBlock.heightAnchor.constraint(equalToConstant: 54),
            dateBlock.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            dateStack.centerXAnchor.constraint(equalTo: dateBlock.centerXAnchor),
            dateStack.centerYAnchor.constraint(equalTo: dateBlock.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: dateBlock.trailingAnchor, constant: 14),
            text.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            text.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private static let weekday: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d"; return f }()
    private static let time: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f }()
}

@MainActor
private final class PaddedBadge: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        textColor = .white
        backgroundColor = UIColor.black.withAlphaComponent(0.75)
        layer.cornerRadius = 4
        layer.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
