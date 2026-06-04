import UIKit
import EmbrCore

@MainActor
final class ProfileSheetViewController: UIViewController {
    private let login: String
    private let api: TwitchAPIProviding
    private let images: ImageLoading
    private weak var navigator: UINavigationController?

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let loginLabel = UILabel()
    private let typeLabel = UILabel()
    private let bioLabel = UILabel()
    private let sinceLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let videosButton = UIButton(type: .system)
    private var loadedUser: TwitchUser?

    init(login: String, navigator: UINavigationController? = nil, api: TwitchAPIProviding = TwitchAPIClient.shared, images: ImageLoading = AppContainer.shared.images) {
        self.login = login
        self.navigator = navigator
        self.api = api
        self.images = images
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()
        load()
    }

    private func buildLayout() {
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 40
        avatar.backgroundColor = Theme.surface
        avatar.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        nameLabel.textColor = Theme.primaryText
        nameLabel.textAlignment = .center

        loginLabel.font = .systemFont(ofSize: 15, weight: .regular)
        loginLabel.textColor = Theme.secondaryText
        loginLabel.textAlignment = .center

        typeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        typeLabel.textColor = Theme.accent
        typeLabel.textAlignment = .center
        typeLabel.isHidden = true

        bioLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bioLabel.textColor = Theme.primaryText
        bioLabel.textAlignment = .center
        bioLabel.numberOfLines = 0

        sinceLabel.font = .systemFont(ofSize: 13, weight: .regular)
        sinceLabel.textColor = Theme.secondaryText
        sinceLabel.textAlignment = .center

        var videosConfig = UIButton.Configuration.tinted()
        videosConfig.title = "Videos & Clips"
        videosConfig.image = UIImage(systemName: "film.stack")
        videosConfig.imagePadding = 6
        videosConfig.cornerStyle = .large
        videosConfig.baseForegroundColor = Theme.accent
        videosButton.configuration = videosConfig
        videosButton.isHidden = true
        videosButton.addAction(UIAction { [weak self] _ in self?.openVideos() }, for: .touchUpInside)

        spinner.hidesWhenStopped = true
        spinner.startAnimating()

        let stack = UIStackView(arrangedSubviews: [avatar, nameLabel, loginLabel, typeLabel, bioLabel, sinceLabel, videosButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(16, after: avatar)
        stack.setCustomSpacing(16, after: sinceLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            avatar.widthAnchor.constraint(equalToConstant: 80),
            avatar.heightAnchor.constraint(equalToConstant: 80),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        stack.isHidden = true
        self.stack = stack
    }

    private weak var stack: UIStackView?

    private func load() {
        Task { [weak self] in
            guard let self else { return }
            let user = try? await self.api.user(login: self.login)
            self.spinner.stopAnimating()
            guard let user else {
                self.nameLabel.text = "@\(self.login)"
                self.stack?.isHidden = false
                return
            }
            self.apply(user)
            if let url = user.profileImageURL, let image = await self.images.image(for: url, targetScale: UIScreen.main.scale) {
                self.avatar.image = image
            }
        }
    }

    private func apply(_ user: TwitchUser) {
        loadedUser = user
        nameLabel.text = user.displayName
        loginLabel.text = "@\(user.login)"
        videosButton.isHidden = (navigator == nil || loadedUser == nil)
        switch user.broadcasterType {
        case "partner": typeLabel.text = "TWITCH PARTNER"; typeLabel.isHidden = false
        case "affiliate": typeLabel.text = "AFFILIATE"; typeLabel.isHidden = false
        default: typeLabel.isHidden = true
        }
        bioLabel.text = user.description
        bioLabel.isHidden = user.description.isEmpty
        if let created = user.createdAt {
            sinceLabel.text = "On Twitch since \(Self.yearFormatter.string(from: created))"
        }
        stack?.isHidden = false
    }

    private func openVideos() {
        guard let user = loadedUser, let navigator else { return }
        dismiss(animated: true) {
            navigator.pushViewController(
                ChannelVideosViewController(broadcasterID: user.id, channelName: user.displayName),
                animated: true
            )
        }
    }

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}
