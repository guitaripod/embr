import UIKit
import Combine
import EmbrCore

/// A channel's page: who it is, whether it is live, a star, and its past broadcasts and clips.
final class TVChannelViewController: UIViewController {
    private let login: String
    private let api = AppContainer.shared.api
    private let avatar = TVArtworkView(shape: .circle, placeholderSymbol: "person.fill")
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let bioLabel = UILabel()
    private let watchButton = UIButton(configuration: .filled())
    private let favoriteButton = UIButton(configuration: .bordered())
    private let multiviewButton = UIButton(configuration: .bordered())
    private let shelves = TVChannelShelvesViewController()
    private var user: TwitchUser?
    private var stream: LiveStream?
    private var cancellables = Set<AnyCancellable>()

    init(login: String) {
        self.login = login
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private let header = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHeader()
        addChild(shelves)
        shelves.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shelves.view)
        shelves.didMove(toParent: self)
        NSLayoutConstraint.activate([
            shelves.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            shelves.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            shelves.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            shelves.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        FavoritesStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateFavoriteButton() }
            .store(in: &cancellables)
        load()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        watchButton.isHidden ? [favoriteButton] : [watchButton]
    }

    private func buildHeader() {
        avatar.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = TVFont.screenTitle
        nameLabel.textColor = Theme.primaryText
        statusLabel.font = TVFont.headline
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 2
        bioLabel.font = TVFont.cardSubtitle
        bioLabel.textColor = Theme.secondaryText
        bioLabel.numberOfLines = 2

        watchButton.configuration?.title = String(localized: "Watch Live")
        watchButton.configuration?.image = UIImage(systemName: "play.fill")
        watchButton.configuration?.imagePadding = 12
        watchButton.isHidden = true
        watchButton.addAction(UIAction { [weak self] _ in self?.watch() }, for: .primaryActionTriggered)

        favoriteButton.configuration?.imagePadding = 12
        favoriteButton.addAction(UIAction { [weak self] _ in self?.toggleFavorite() }, for: .primaryActionTriggered)

        multiviewButton.configuration?.title = String(localized: "Multiview")
        multiviewButton.configuration?.image = UIImage(systemName: "rectangle.split.2x2")
        multiviewButton.configuration?.imagePadding = 12
        multiviewButton.isHidden = true
        multiviewButton.addAction(UIAction { [weak self] _ in
            guard let self, let stream = self.stream else { return }
            TVMultiviewViewController.present(starting: [stream], from: self)
        }, for: .primaryActionTriggered)

        let buttons = UIStackView(arrangedSubviews: [watchButton, favoriteButton, multiviewButton])
        buttons.axis = .horizontal
        buttons.spacing = 32
        let text = UIStackView(arrangedSubviews: [nameLabel, statusLabel, bioLabel, buttons])
        text.axis = .vertical
        text.alignment = .leading
        text.spacing = 10
        text.setCustomSpacing(30, after: bioLabel)
        header.addArrangedSubview(avatar)
        header.addArrangedSubview(text)
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 48
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 220),
            avatar.heightAnchor.constraint(equalToConstant: 220),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: TVMetrics.tabBarClearance),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TVMetrics.horizontalInset),
            header.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -TVMetrics.horizontalInset),
        ])
        updateFavoriteButton()
    }

    private func load() {
        nameLabel.text = login
        Task { [weak self] in
            guard let self else { return }
            guard let user = try? await self.api.user(login: self.login) else {
                self.statusLabel.text = String(localized: "This channel couldn't be found.")
                return
            }
            self.user = user
            self.nameLabel.text = user.displayName
            self.avatar.setImage(user.profileImageURL)
            self.bioLabel.text = user.description
            self.bioLabel.isHidden = user.description.isEmpty
            self.updateFavoriteButton()
            async let live = try? self.api.streams(userIDs: [user.id]).first
            async let videos = try? self.api.videos(userID: user.id, after: nil, first: 30).items
            async let clips = try? self.api.clips(broadcasterID: user.id, after: nil, first: 30).items
            self.show(stream: await live)
            self.shelves.show(videos: await videos ?? [], clips: await clips ?? [])
        }
    }

    private func show(stream: LiveStream?) {
        self.stream = stream
        watchButton.isHidden = stream == nil
        multiviewButton.isHidden = stream == nil
        if let stream {
            statusLabel.text = String(localized: "Live · \(stream.viewerCount.formatted()) viewers · \(stream.gameName)\n\(stream.title)")
        } else {
            statusLabel.text = String(localized: "Offline")
        }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func watch() {
        guard let stream else { return }
        TVPlaybackCoordinator.play(.live(stream), from: self)
    }

    private func toggleFavorite() {
        guard let user else { return }
        FavoritesStore.shared.toggle(id: user.id, login: user.login, name: user.displayName)
    }

    private func updateFavoriteButton() {
        let favorite = user.map { FavoritesStore.shared.isFavorite($0.id) } ?? false
        favoriteButton.configuration?.title = favorite ? String(localized: "Favorited") : String(localized: "Favorite")
        favoriteButton.configuration?.image = UIImage(systemName: favorite ? "star.fill" : "star")
        favoriteButton.isEnabled = user != nil
    }
}

/// The past broadcasts and clips under a channel's header.
final class TVChannelShelvesViewController: TVShelfViewController {
    private var videos: [VideoOnDemand] = []

    override var managesOwnInsets: Bool { true }
    private var clips: [Clip] = []

    override var refreshInterval: TimeInterval { 600 }

    func show(videos: [VideoOnDemand], clips: [Clip]) {
        self.videos = videos
        self.clips = clips
        render()
    }

    override func load() async {
        render()
    }

    private func render() {
        guard isViewLoaded else { return }
        apply([
            TVShelf(id: "videos", title: String(localized: "Past Broadcasts"), style: .videos, items: videos.map(TVShelfItem.video)),
            TVShelf(id: "clips", title: String(localized: "Clips"), style: .videos, items: clips.map(TVShelfItem.clip)),
        ])
    }
}
