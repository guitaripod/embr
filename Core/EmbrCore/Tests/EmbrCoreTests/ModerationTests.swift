import Foundation
import Testing
@testable import EmbrCore

@Suite("Moderation")
struct ModerationTests {
    private let now = Date(timeIntervalSince1970: 1_647_309_928)

    @Test("An AutoMod hold names the author, the text and AutoMod's category")
    func autoModHold() throws {
        let json = """
        {
          "broadcaster_user_id": "1337", "moderator_user_id": "9001",
          "user_id": "4242", "user_login": "baduser", "user_name": "BadUser",
          "message_id": "bad-message-id",
          "message": { "text": "This is a bad message", "fragments": [] },
          "reason": "automod",
          "automod": { "category": "aggressive", "level": 1, "boundaries": [] },
          "blocked_term": null,
          "held_at": "2022-12-02T15:00:00.00Z"
        }
        """
        let event = try EventSubMapper.chatEvent(subscriptionType: "automod.message.hold", eventData: Data(json.utf8), timestamp: now)
        guard case .moderation(.held(let held)) = event else {
            Issue.record("expected a held message, got \(event)")
            return
        }
        #expect(held.id == "bad-message-id")
        #expect(held.author.login == "baduser")
        #expect(held.text == "This is a bad message")
        #expect(held.reason == "aggressive")
    }

    @Test("A blocked-term hold says so")
    func blockedTermHold() throws {
        let json = """
        { "user_id": "1", "user_login": "a", "user_name": "A", "message_id": "m", "message": { "text": "x" },
          "reason": "blocked_term", "automod": null, "blocked_term": { "terms_found": [] }, "held_at": "2022-12-02T15:00:00Z" }
        """
        let event = try EventSubMapper.chatEvent(subscriptionType: "automod.message.hold", eventData: Data(json.utf8), timestamp: now)
        guard case .moderation(.held(let held)) = event else {
            Issue.record("expected a held message")
            return
        }
        #expect(held.reason == "blocked term")
    }

    @Test("An AutoMod update carries its outcome and who decided")
    func autoModUpdate() throws {
        let json = """
        { "message_id": "bad-message-id", "status": "Denied", "moderator_user_name": "The_Mod" }
        """
        let event = try EventSubMapper.chatEvent(subscriptionType: "automod.message.update", eventData: Data(json.utf8), timestamp: now)
        #expect(event == .moderation(.heldResolved(messageID: "bad-message-id", status: .denied, moderator: "The_Mod")))
    }

    @Test("A timeout in the moderation log has its target, reason and length")
    func timeoutLogEntry() throws {
        let json = """
        {
          "moderator_user_name": "quotrok", "action": "timeout", "ban": null,
          "timeout": { "user_id": "141981764", "user_login": "twitchdev", "user_name": "TwitchDev",
                       "reason": "Does not like pineapple on pizza.", "expires_at": "2022-03-15T02:15:28Z" }
        }
        """
        let event = try EventSubMapper.chatEvent(subscriptionType: "channel.moderate", eventData: Data(json.utf8), timestamp: now)
        guard case .moderation(.action(let entry)) = event else {
            Issue.record("expected a log entry, got \(event)")
            return
        }
        #expect(entry.action == "timeout")
        #expect(entry.moderator == "quotrok")
        #expect(entry.target == "TwitchDev")
        #expect(entry.reason == "Does not like pineapple on pizza.")
        #expect(entry.seconds == 600)
    }

    @Test("A setting change in the log has no target")
    func settingLogEntry() throws {
        let json = """
        { "moderator_user_login": "quotrok", "action": "slow", "slow": { "wait_time_seconds": 30 } }
        """
        let event = try EventSubMapper.chatEvent(subscriptionType: "channel.moderate", eventData: Data(json.utf8), timestamp: now)
        guard case .moderation(.action(let entry)) = event else {
            Issue.record("expected a log entry")
            return
        }
        #expect(entry.moderator == "quotrok")
        #expect(entry.target == nil)
        #expect(entry.seconds == 30)
    }

    @Test("An unban request names who asks and what they wrote")
    func unbanRequest() throws {
        let json = """
        { "id": "60", "broadcaster_user_id": "1337", "user_id": "1339", "user_login": "not_cool_user",
          "user_name": "Not_Cool_User", "text": "unban me", "created_at": "2023-11-16T10:11:12.634234626Z" }
        """
        let event = try EventSubMapper.chatEvent(subscriptionType: "channel.unban_request.create", eventData: Data(json.utf8), timestamp: now)
        guard case .moderation(.unbanRequest(let request)) = event else {
            Issue.record("expected an unban request")
            return
        }
        #expect(request.id == "60")
        #expect(request.user.displayName == "Not_Cool_User")
        #expect(request.text == "unban me")
    }

    @Test("Moderator subscriptions name the moderator and use the current versions")
    func moderatorSubscriptions() {
        let requests = EventSubSubscriptionRequest.moderatorSubscriptions(broadcasterID: "1", moderatorID: "2", sessionID: "s")
        #expect(requests.map(\.type) == ["automod.message.hold", "automod.message.update", "channel.moderate", "channel.unban_request.create"])
        #expect(requests.map(\.version) == ["2", "2", "2", "1"])
        #expect(requests.allSatisfy { $0.condition == ["broadcaster_user_id": "1", "moderator_user_id": "2"] })
        #expect(requests.allSatisfy { EventSubSubscriptionRequest.isModeratorType($0.type) })
        #expect(!EventSubSubscriptionRequest.isModeratorType("channel.chat.message"))
    }

    @Test("Allowing a held message posts the moderator, message and action")
    func resolveHeldRequest() throws {
        let request = HelixRequestFactory(clientID: "abc").resolveHeldMessage(moderatorID: "9", messageID: "m1", allow: true, token: "t")
        #expect(request.method == .post)
        #expect(request.url.path.hasSuffix("/moderation/automod/message"))
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: String]
        #expect(body == ["user_id": "9", "msg_id": "m1", "action": "ALLOW"])
    }

    @Test("Resolving an unban request patches its status")
    func resolveUnbanRequest() {
        let request = HelixRequestFactory(clientID: "abc").resolveUnbanRequest(broadcasterID: "1", moderatorID: "2", requestID: "60", approve: false, note: nil, token: "t")
        #expect(request.method == .patch)
        let query = request.url.query ?? ""
        #expect(query.contains("unban_request_id=60"))
        #expect(query.contains("status=denied"))
        #expect(!query.contains("resolution_text"))
    }
}
