import UIKit
import EmbrCore

final class DeepLinkRouter {
    private let api: TwitchAPIProviding

    init(api: TwitchAPIProviding = AppContainer.shared.api) {
        self.api = api
    }

    @MainActor
    func handle(_ url: URL, from root: RootTabBarController) async {
        guard let login = channelLogin(from: url) else {
            AppLogger.shared.debug("ignored deep link \(url.absoluteString)", category: .app)
            return
        }
        AppLogger.shared.info("resolving deep link channel \(login)", category: .app)
        await open(login: login, from: root)
    }

    @MainActor
    private func open(login: String, from root: RootTabBarController) async {
        do {
            guard let user = try await api.user(login: login),
                  let channel = try await api.channelInfo(broadcasterID: user.id) else {
                presentNotFound(login: login, from: root)
                return
            }
            push(channel, from: root)
        } catch {
            AppLogger.shared.warn("deep link resolution failed for \(login): \(error)", category: .app)
            presentNotFound(login: login, from: root)
        }
    }

    @MainActor
    private func push(_ channel: ChannelInfo, from root: RootTabBarController) {
        let destination = ChannelViewController(channel: channel)
        guard let navigation = navigationStack(in: root) else {
            root.present(destination, animated: true)
            return
        }
        navigation.pushViewController(destination, animated: true)
    }

    @MainActor
    private func navigationStack(in root: RootTabBarController) -> UINavigationController? {
        if let navigation = root.selectedViewController as? UINavigationController {
            return navigation
        }
        return root.selectedViewController?.navigationController
    }

    private func channelLogin(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()

        if scheme == "embr" {
            guard host == "channel" else { return nil }
            return firstPathComponent(components)
        }

        if scheme == "https" || scheme == "http" {
            guard host == "twitch.tv" || host == "www.twitch.tv" || host == "m.twitch.tv" else { return nil }
            return firstPathComponent(components)
        }

        return nil
    }

    private func firstPathComponent(_ components: URLComponents) -> String? {
        let segments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let candidate = segments.first, !candidate.isEmpty else { return nil }
        return candidate.lowercased()
    }

    @MainActor
    private func presentNotFound(login: String, from root: RootTabBarController) {
        let alert = UIAlertController(
            title: "Channel Not Found",
            message: "Could not open \"\(login)\".",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        let presenter = root.presentedViewController ?? root
        presenter.present(alert, animated: true)
    }
}
