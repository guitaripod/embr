import UIKit

/// Menu-bar and hardware-keyboard commands: a Go menu for the tabs and a Playback menu for the
/// video on screen. They are handled by the app delegate, the last responder in every chain, so
/// they work whatever holds focus; each is enabled only while the screen it acts on is visible,
/// and the single-key playback commands step aside while the viewer is typing in chat.
@MainActor
enum KeyCommands {
    private static let goMenu = UIMenu.Identifier("com.guitaripod.embr.go")
    private static let playbackMenu = UIMenu.Identifier("com.guitaripod.embr.playback")

    static func build(into builder: UIMenuBuilder) {
        builder.insertSibling(makeGoMenu(), afterMenu: .view)
        builder.insertSibling(makePlaybackMenu(), afterMenu: goMenu)
    }

    /// Numbered in the order the tabs appear, which depends on whether the viewer is signed in.
    /// Each action may appear only once in the main menu, and ⌘F and ⌘, belong to the system's
    /// Find and Settings items, so the tabs keep to numbers.
    private static func makeGoMenu() -> UIMenu {
        let tabs = activeRoot?.orderedTabs ?? [.top, .favorites, .search, .settings]
        let numbered = tabs.enumerated().map { index, tab in
            UIKeyCommand(title: title(for: tab), action: selector(for: tab), input: String(index + 1), modifierFlags: .command)
        }
        return UIMenu(title: String(localized: "Go"), identifier: goMenu, children: numbered)
    }

    private static func makePlaybackMenu() -> UIMenu {
        let playPause = UIKeyCommand(
            title: String(localized: "Play/Pause"),
            action: #selector(AppDelegate.togglePlayback(_:)),
            input: " ",
            modifierFlags: []
        )
        playPause.wantsPriorityOverSystemBehavior = true
        let mute = UIKeyCommand(
            title: String(localized: "Mute"),
            action: #selector(AppDelegate.toggleMuteCommand(_:)),
            input: "m",
            modifierFlags: []
        )
        let fullscreen = UIKeyCommand(
            title: String(localized: "Full Screen"),
            action: #selector(AppDelegate.toggleVideoFullscreen(_:)),
            input: "f",
            modifierFlags: []
        )
        let chat = UIKeyCommand(
            title: String(localized: "Show Chat"),
            action: #selector(AppDelegate.toggleFullscreenChatCommand(_:)),
            input: "c",
            modifierFlags: []
        )
        let exit = UIKeyCommand(
            title: String(localized: "Exit Full Screen"),
            action: #selector(AppDelegate.exitVideoFullscreen(_:)),
            input: UIKeyCommand.inputEscape,
            modifierFlags: []
        )
        exit.attributes = .hidden
        let skipBack = UIKeyCommand(
            title: String(localized: "Skip Back 10 Seconds"),
            action: #selector(AppDelegate.skipBackCommand(_:)),
            input: UIKeyCommand.inputLeftArrow,
            modifierFlags: []
        )
        skipBack.wantsPriorityOverSystemBehavior = true
        let skipForward = UIKeyCommand(
            title: String(localized: "Skip Forward 10 Seconds"),
            action: #selector(AppDelegate.skipForwardCommand(_:)),
            input: UIKeyCommand.inputRightArrow,
            modifierFlags: []
        )
        skipForward.wantsPriorityOverSystemBehavior = true
        let favorite = UIKeyCommand(
            title: String(localized: "Add to Favorites"),
            action: #selector(AppDelegate.toggleFavoriteCommand(_:)),
            input: "d",
            modifierFlags: .command
        )
        return UIMenu(
            title: String(localized: "Playback"),
            identifier: playbackMenu,
            children: [
                UIMenu(options: .displayInline, children: [playPause, mute, skipBack, skipForward]),
                UIMenu(options: .displayInline, children: [fullscreen, chat, exit]),
                UIMenu(options: .displayInline, children: [favorite])
            ]
        )
    }

    private static func title(for tab: RootTabBarController.Tab) -> String {
        switch tab {
        case .following: return String(localized: "Following")
        case .favorites: return String(localized: "Favorites")
        case .top: return String(localized: "Top")
        case .search: return String(localized: "Search")
        case .settings: return String(localized: "Settings")
        }
    }

    private static func selector(for tab: RootTabBarController.Tab) -> Selector {
        switch tab {
        case .following: return #selector(AppDelegate.goToFollowing(_:))
        case .favorites: return #selector(AppDelegate.goToFavorites(_:))
        case .top: return #selector(AppDelegate.goToTop(_:))
        case .search: return #selector(AppDelegate.goToSearch(_:))
        case .settings: return #selector(AppDelegate.goToSettings(_:))
        }
    }

    static var activeRoot: RootTabBarController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.lazy.compactMap { $0.rootViewController as? RootTabBarController }.first
    }

    /// The channel page or standalone video on top of the selected tab, unless a sheet covers it.
    static var visiblePlayback: (channel: ChannelViewController?, player: VideoViewController)? {
        guard let root = activeRoot, root.presentedViewController == nil,
              let top = root.selectedNavigationController?.topViewController else { return nil }
        if let channel = top as? ChannelViewController, let player = channel.player {
            return (channel, player)
        }
        if let player = top as? VideoViewController {
            return (nil, player)
        }
        return nil
    }

    static func tab(for action: Selector) -> RootTabBarController.Tab? {
        RootTabBarController.Tab.allCases.first { selector(for: $0) == action }
    }

    static let playbackActions: Set<Selector> = [
        #selector(AppDelegate.togglePlayback(_:)),
        #selector(AppDelegate.toggleMuteCommand(_:)),
        #selector(AppDelegate.toggleVideoFullscreen(_:)),
        #selector(AppDelegate.toggleFullscreenChatCommand(_:)),
        #selector(AppDelegate.exitVideoFullscreen(_:)),
        #selector(AppDelegate.toggleFavoriteCommand(_:)),
        #selector(AppDelegate.skipBackCommand(_:)),
        #selector(AppDelegate.skipForwardCommand(_:))
    ]

    /// Whether a command can act right now; nil for actions that are not these commands.
    static func canPerform(_ action: Selector) -> Bool? {
        if let tab = tab(for: action) {
            return activeRoot?.canSelect(tab) ?? false
        }
        guard playbackActions.contains(action) else { return nil }
        guard let playback = visiblePlayback else { return false }
        if playback.channel?.isTypingInChat == true, action != #selector(AppDelegate.toggleFavoriteCommand(_:)) {
            return false
        }
        switch action {
        case #selector(AppDelegate.toggleFavoriteCommand(_:)):
            return playback.channel != nil
        case #selector(AppDelegate.toggleFullscreenChatCommand(_:)):
            return playback.channel?.isFullscreen == true
        case #selector(AppDelegate.exitVideoFullscreen(_:)):
            return playback.channel?.isFullscreen == true || playback.player.isStandaloneFullscreen
        case #selector(AppDelegate.skipBackCommand(_:)), #selector(AppDelegate.skipForwardCommand(_:)):
            return playback.player.isSeekable
        default:
            return true
        }
    }

    /// Titles that follow state, so the menu reads "Pause" while playing and "Unmute" while muted.
    static func validate(_ command: UICommand) {
        guard let playback = visiblePlayback else { return }
        switch command.action {
        case #selector(AppDelegate.togglePlayback(_:)):
            command.title = playback.player.isPlaying ? String(localized: "Pause") : String(localized: "Play")
        case #selector(AppDelegate.toggleMuteCommand(_:)):
            command.title = playback.player.isMuted ? String(localized: "Unmute") : String(localized: "Mute")
        case #selector(AppDelegate.toggleVideoFullscreen(_:)):
            let fullscreen = playback.channel?.isFullscreen == true || playback.player.isStandaloneFullscreen
            command.title = fullscreen ? String(localized: "Exit Full Screen") : String(localized: "Full Screen")
        case #selector(AppDelegate.toggleFullscreenChatCommand(_:)):
            let visible = playback.channel?.isFullscreenChatVisible == true
            command.title = visible ? String(localized: "Hide Chat") : String(localized: "Show Chat")
        case #selector(AppDelegate.toggleFavoriteCommand(_:)):
            let favorite = playback.channel.map { FavoritesStore.shared.isFavorite($0.broadcasterID) } ?? false
            command.title = favorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")
        default:
            break
        }
    }
}

extension AppDelegate {
    @objc func goToFollowing(_ sender: Any?) { KeyCommands.activeRoot?.select(.following) }
    @objc func goToFavorites(_ sender: Any?) { KeyCommands.activeRoot?.select(.favorites) }
    @objc func goToTop(_ sender: Any?) { KeyCommands.activeRoot?.select(.top) }
    @objc func goToSearch(_ sender: Any?) {
        guard let root = KeyCommands.activeRoot else { return }
        root.select(.search)
        (root.selectedNavigationController?.viewControllers.first as? SearchViewController)?.focusSearchField()
    }
    @objc func goToSettings(_ sender: Any?) { KeyCommands.activeRoot?.select(.settings) }

    @objc func togglePlayback(_ sender: Any?) {
        KeyCommands.visiblePlayback?.player.togglePlayPause()
    }

    @objc func toggleMuteCommand(_ sender: Any?) {
        KeyCommands.visiblePlayback?.player.toggleMute()
    }

    @objc func toggleVideoFullscreen(_ sender: Any?) {
        KeyCommands.visiblePlayback?.player.toggleFullscreen()
    }

    @objc func toggleFullscreenChatCommand(_ sender: Any?) {
        KeyCommands.visiblePlayback?.channel?.toggleFullscreenChat()
    }

    @objc func exitVideoFullscreen(_ sender: Any?) {
        guard let playback = KeyCommands.visiblePlayback else { return }
        if let channel = playback.channel {
            channel.exitFullscreen()
        } else {
            playback.player.setStandaloneFullscreen(false)
        }
    }

    @objc func skipBackCommand(_ sender: Any?) {
        KeyCommands.visiblePlayback?.player.skip(by: -10)
    }

    @objc func skipForwardCommand(_ sender: Any?) {
        KeyCommands.visiblePlayback?.player.skip(by: 10)
    }

    @objc func toggleFavoriteCommand(_ sender: Any?) {
        KeyCommands.visiblePlayback?.channel?.toggleFavoriteFromCommand()
    }
}
