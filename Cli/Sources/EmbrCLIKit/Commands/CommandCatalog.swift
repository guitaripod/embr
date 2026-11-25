import Foundation

enum CommandCatalog {
    static let groups: [GroupSpec] = [
        GroupSpec(["auth"], summary: "Sign in, refresh, inspect and clear tokens."),
        GroupSpec(["config"], summary: "Credentials path and profiles."),
        GroupSpec(["streams"], summary: "Live streams and live status."),
        GroupSpec(["games"], summary: "Categories."),
        GroupSpec(["search"], summary: "Search categories and channels."),
        GroupSpec(["users"], summary: "User lookup."),
        GroupSpec(["channels"], summary: "Channel information, settings and follows."),
        GroupSpec(["videos"], summary: "Videos and past broadcasts."),
        GroupSpec(["clips"], summary: "Clips."),
        GroupSpec(["schedule"], summary: "Stream schedules."),
        GroupSpec(["chat"], summary: "Chat messages, modes, emotes, badges, pins and reading chat."),
        GroupSpec(["chat", "emotes"], summary: "Twitch emotes: global, channel or the user's own."),
        GroupSpec(["chat", "badges"], summary: "Twitch chat badges."),
        GroupSpec(["mod"], summary: "Bans, message removal, AutoMod, unban requests and channel people."),
        GroupSpec(["studio"], summary: "Ads, Hype Trains, polls, predictions, goals, followers and Shield Mode."),
        GroupSpec(["studio", "shield"], summary: "Shield Mode."),
        GroupSpec(["eventsub"], summary: "EventSub subscriptions and live event streams."),
        GroupSpec(["emotes"], summary: "Twitch, 7TV, BetterTTV and FrankerFaceZ emotes."),
        GroupSpec(["playback"], summary: "HLS playback URLs.")
    ]

    static let commands: [CommandSpec] =
        AuthCommands.specs
        + StreamCommands.specs
        + DirectoryCommands.specs
        + ChatCommands.specs
        + ModCommands.specs
        + StudioCommands.specs
        + EventSubCommands.specs
        + EmoteCommands.specs
        + PlaybackCommands.specs
        + UtilityCommands.specs
        + StreamingCommands.specs

    static let registry = CommandRegistry(groups: groups, commands: commands)
}
