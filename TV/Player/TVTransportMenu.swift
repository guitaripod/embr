import UIKit
import EmbrCore

/// The items Embr adds to the player's transport bar: chat on or off, its placement and text size, the quality, the
/// star and multiview.
@MainActor
enum TVTransportMenu {
    struct Actions {
        let setChatVisible: @MainActor (Bool) -> Void
        let placeChat: @MainActor () -> Void
        let resizeChat: @MainActor () -> Void
        let setQuality: @MainActor (StreamQuality) -> Void
        let openMultiview: @MainActor (LiveStream) -> Void
        let refresh: @MainActor () -> Void
    }

    static func items(
        chatAvailable: Bool,
        chatVisible: Bool,
        qualities: [StreamQuality],
        currentQuality: StreamQuality?,
        stream: LiveStream?,
        actions: Actions
    ) -> [UIMenuElement] {
        var items: [UIMenuElement] = []
        if chatAvailable {
            let chat = UIAction(
                title: String(localized: "Chat"),
                image: UIImage(systemName: chatVisible ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            ) { _ in
                actions.setChatVisible(!chatVisible)
            }
            chat.state = chatVisible ? .on : .off
            items.append(chat)
        }
        if chatAvailable && chatVisible {
            items.append(chatOptionsMenu(actions: actions))
        }
        if let quality = qualityMenu(qualities: qualities, current: currentQuality, actions: actions) {
            items.append(quality)
        }
        if let stream {
            items.append(favoriteAction(for: stream, actions: actions))
            items.append(UIAction(title: String(localized: "Multiview"), image: UIImage(systemName: "rectangle.split.2x2")) { _ in
                actions.openMultiview(stream)
            })
        }
        return items
    }

    private static func chatOptionsMenu(actions: Actions) -> UIMenu {
        let settings = SettingsStore.shared.current
        let placement = UIMenu(title: String(localized: "Placement"), options: .displayInline, children: Settings.ChatPlacement.allCases.map { side in
            let action = UIAction(title: side == .left ? String(localized: "Left") : String(localized: "Right")) { _ in
                SettingsStore.shared.update { $0.tvChatPlacement = side }
                actions.placeChat()
                actions.refresh()
            }
            action.state = settings.tvChatPlacementPreference == side ? .on : .off
            return action
        })
        let size = UIMenu(title: String(localized: "Text Size"), options: .displayInline, children: Settings.ChatTextSize.allCases.map { textSize in
            let title: String = switch textSize {
            case .small: String(localized: "Small")
            case .medium: String(localized: "Medium")
            case .large: String(localized: "Large")
            }
            let action = UIAction(title: title) { _ in
                SettingsStore.shared.update { $0.tvChatTextSize = textSize }
                actions.resizeChat()
                actions.refresh()
            }
            action.state = settings.tvChatTextSizePreference == textSize ? .on : .off
            return action
        })
        return UIMenu(title: String(localized: "Chat Options"), image: UIImage(systemName: "textformat.size"), children: [placement, size])
    }

    private static func qualityMenu(qualities: [StreamQuality], current: StreamQuality?, actions: Actions) -> UIMenu? {
        guard !qualities.isEmpty else { return nil }
        var choices = [UIAction(title: String(localized: "Auto")) { _ in
            guard let auto = StreamQuality.auto(from: qualities) else { return }
            actions.setQuality(auto)
            actions.refresh()
        }]
        choices[0].state = current == nil ? .on : .off
        for quality in qualities {
            let action = UIAction(title: quality.displayName) { _ in
                actions.setQuality(quality)
                actions.refresh()
            }
            action.state = current == quality ? .on : .off
            choices.append(action)
        }
        return UIMenu(title: String(localized: "Quality"), image: UIImage(systemName: "slider.horizontal.3"), options: .singleSelection, children: choices)
    }

    private static func favoriteAction(for stream: LiveStream, actions: Actions) -> UIAction {
        let favorite = FavoritesStore.shared.isFavorite(stream.userID)
        let action = UIAction(
            title: favorite ? String(localized: "Favorited") : String(localized: "Favorite"),
            image: UIImage(systemName: favorite ? "star.fill" : "star")
        ) { _ in
            FavoritesStore.shared.toggle(id: stream.userID, login: stream.userLogin, name: stream.userName)
            actions.refresh()
        }
        action.state = favorite ? .on : .off
        return action
    }
}

extension StreamQuality {
    /// The name the quality menu shows: Twitch's `chunked` is the source rendition.
    var displayName: String {
        name.lowercased() == "chunked" ? String(localized: "Source") : name
    }

    /// A stand-in quality the player reads as "Auto": no peak bit rate, the master playlist chooses.
    static func auto(from qualities: [StreamQuality]) -> StreamQuality? {
        guard let first = qualities.first else { return nil }
        return StreamQuality(name: "Auto", url: first.url)
    }
}
