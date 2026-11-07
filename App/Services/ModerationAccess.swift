import Foundation
import EmbrCore
import MidgarCore

/// Which channels the signed-in viewer moderates, and whether Moderator Tools runs in one: always their own channel,
/// and with the moderator scopes granted every channel Twitch lists for them, looked up at most every ten minutes.
actor ModerationAccess {
    static let shared = ModerationAccess()

    private let auth: AuthControlling
    private let api: TwitchAPIProviding
    private var cached: (userID: String, channels: Set<String>, at: Date)?
    private let freshFor: TimeInterval = 600

    init(auth: AuthControlling = AuthService.shared, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.auth = auth
        self.api = api
    }

    /// Whether the AutoMod queue, moderation log and unban requests should run in this channel: Moderator Tools is on,
    /// the viewer granted its scopes, and they moderate here.
    func toolsApply(to channelID: String) async -> Bool {
        let enabled = await MainActor.run { SettingsStore.shared.current.moderatorToolsEnabled }
        guard enabled, let user = await auth.currentUser(), user.hasModeratorScopes else { return false }
        return await moderates(channelID, user: user)
    }

    /// Whether the viewer moderates the channel as far as Twitch says; false without the scope to ask.
    func moderates(_ channelID: String) async -> Bool {
        guard let user = await auth.currentUser() else { return false }
        return await moderates(channelID, user: user)
    }

    func forget() {
        cached = nil
    }

    private func moderates(_ channelID: String, user: AuthenticatedUser) async -> Bool {
        if channelID == user.id { return true }
        guard user.scopes.contains("user:read:moderated_channels") else { return false }
        if let cached, cached.userID == user.id, Date().timeIntervalSince(cached.at) < freshFor {
            return cached.channels.contains(channelID)
        }
        do {
            let channels = try await api.moderatedChannelIDs(userID: user.id)
            cached = (user.id, channels, Date())
            MidgarLog.info("moderation: \(user.login) moderates \(channels.count) channel(s)", category: .chat)
            return channels.contains(channelID)
        } catch {
            MidgarLog.notice("moderation: moderated channels lookup failed: \(error)", category: .chat)
            return cached?.userID == user.id && cached?.channels.contains(channelID) == true
        }
    }
}
