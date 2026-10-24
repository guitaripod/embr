import Foundation
import Testing
@testable import EmbrCore

@Suite("EventSub")
struct EventSubTests {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Decodes session_welcome and extracts session id + keepalive")
    func sessionWelcome() throws {
        let json = """
        {
          "metadata": {
            "message_id": "96a3f3b5-5dec-4eed-908e-e11ee657416c",
            "message_type": "session_welcome",
            "message_timestamp": "2023-07-19T14:56:51.634234626Z"
          },
          "payload": {
            "session": {
              "id": "AQoQILE98gtqShGmLD7AM6yJThAB",
              "status": "connected",
              "connected_at": "2023-07-19T14:56:51.616329898Z",
              "keepalive_timeout_seconds": 10,
              "reconnect_url": null
            }
          }
        }
        """
        let message = try EventSubMessage.decode(Data(json.utf8))
        #expect(message == .welcome(sessionID: "AQoQILE98gtqShGmLD7AM6yJThAB", keepaliveSeconds: 10))
    }

    @Test("Decodes session_keepalive")
    func keepalive() throws {
        let json = """
        {
          "metadata": {
            "message_id": "84c1e79a-2a4b-4c13-ba0b-4312293e9308",
            "message_type": "session_keepalive",
            "message_timestamp": "2023-07-19T10:11:12.634234626Z"
          },
          "payload": {}
        }
        """
        #expect(try EventSubMessage.decode(Data(json.utf8)) == .keepalive)
    }

    @Test("Decodes session_reconnect url")
    func reconnect() throws {
        let json = """
        {
          "metadata": {
            "message_id": "84c1e79a-2a4b-4c13-ba0b-4312293e9308",
            "message_type": "session_reconnect",
            "message_timestamp": "2022-11-18T09:10:11.634234626Z"
          },
          "payload": {
            "session": {
              "id": "AQoQexampleid",
              "status": "reconnecting",
              "keepalive_timeout_seconds": null,
              "reconnect_url": "wss://eventsub.wss.twitch.tv?challenge=foobar",
              "connected_at": "2022-11-16T10:11:12.634234626Z"
            }
          }
        }
        """
        #expect(try EventSubMessage.decode(Data(json.utf8)) == .reconnect(url: "wss://eventsub.wss.twitch.tv?challenge=foobar"))
    }

    @Test("Decodes revocation reason")
    func revocation() throws {
        let json = """
        {
          "metadata": {
            "message_id": "84c1e79a-2a4b-4c13-ba0b-4312293e9308",
            "message_type": "revocation",
            "message_timestamp": "2022-11-16T10:11:12.464757833Z",
            "subscription_type": "channel.chat.message",
            "subscription_version": "1"
          },
          "payload": {
            "subscription": {
              "id": "f1c2a387-161a-49f9-a165-0f21d7a4e1c4",
              "status": "authorization_revoked",
              "type": "channel.chat.message",
              "version": "1"
            }
          }
        }
        """
        #expect(try EventSubMessage.decode(Data(json.utf8)) == .revocation(reason: "authorization_revoked"))
    }

    @Test("Unknown message_type throws")
    func unknownType() {
        let json = """
        { "metadata": { "message_type": "session_disconnect" }, "payload": {} }
        """
        #expect(throws: APIError.self) {
            _ = try EventSubMessage.decode(Data(json.utf8))
        }
    }

    @Test("Maps a chat.message notification to ChatMessage with fragments, badges, color, reply")
    func chatMessageNotification() throws {
        let message = try EventSubMessage.decode(Data(Self.chatMessageEnvelope.utf8))
        guard case let .notification(subscriptionType, eventData) = message else {
            Issue.record("expected notification, got \(message)")
            return
        }
        #expect(subscriptionType == "channel.chat.message")

        let chat = try EventSubMapper.chatMessage(fromEvent: eventData, timestamp: timestamp)
        #expect(chat.id == "cc106a89-1814-919d-454c-f4f2f970aae7")
        #expect(chat.channelID == "1971641")
        #expect(chat.author.id == "4145994")
        #expect(chat.author.login == "viewer32")
        #expect(chat.author.displayName == "viewer32")
        #expect(chat.author.color == ChatColor(hex: "#00FF7F"))
        #expect(chat.messageType == .regular)
        #expect(chat.bits == nil)
        #expect(chat.isAction == false)

        #expect(chat.fragments.count == 3)
        guard case let .text(lead) = chat.fragments[0] else {
            Issue.record("fragment 0 not text")
            return
        }
        #expect(lead == "Hey ")

        guard case let .mention(mention) = chat.fragments[1] else {
            Issue.record("fragment 1 not mention")
            return
        }
        #expect(mention.userID == "12826")
        #expect(mention.login == "twitch")
        #expect(mention.displayName == "Twitch")

        guard case let .emote(emote) = chat.fragments[2] else {
            Issue.record("fragment 2 not emote")
            return
        }
        #expect(emote.id == "emotesv2_a1b2c3")
        #expect(emote.text == " PogChamp")
        #expect(emote.setID == "0")
        #expect(emote.ownerID == "12826")
        #expect(emote.formats == [.static, .animated])

        #expect(chat.badges.count == 2)
        #expect(chat.badges[0] == MessageBadge(setID: "moderator", id: "1", info: nil))
        #expect(chat.badges[1] == MessageBadge(setID: "subscriber", id: "12", info: "16"))

        let reply = try #require(chat.reply)
        #expect(reply.parentMessageID == "parent-123")
        #expect(reply.parentUserID == "12826")
        #expect(reply.parentLogin == "twitch")
        #expect(reply.parentDisplayName == "Twitch")
        #expect(reply.parentText == "hello there")
        #expect(reply.threadParentMessageID == "thread-123")

        #expect(chat.sharedChatSource == nil)
        #expect(chat.notice == nil)
    }

    @Test("chatEvent dispatches message subscription")
    func chatEventMessage() throws {
        guard case let .notification(_, eventData) = try EventSubMessage.decode(Data(Self.chatMessageEnvelope.utf8)) else {
            Issue.record("expected notification")
            return
        }
        let event = try EventSubMapper.chatEvent(
            subscriptionType: "channel.chat.message",
            eventData: eventData,
            timestamp: timestamp
        )
        guard case let .message(chat) = event else {
            Issue.record("expected .message")
            return
        }
        #expect(chat.id == "cc106a89-1814-919d-454c-f4f2f970aae7")
    }

    @Test("Cheer bits and channel_points message_type map through")
    func chatMessageBitsAndType() throws {
        let json = """
        {
          "broadcaster_user_id": "1971641",
          "chatter_user_id": "4145994",
          "chatter_user_login": "viewer32",
          "chatter_user_name": "viewer32",
          "message_id": "msg-bits",
          "color": "",
          "message": {
            "text": "cheer100 nice",
            "fragments": [
              { "type": "cheermote", "text": "cheer100", "cheermote": { "prefix": "cheer", "bits": 100, "tier": 1 }, "emote": null, "mention": null },
              { "type": "text", "text": " nice", "cheermote": null, "emote": null, "mention": null }
            ]
          },
          "badges": [],
          "message_type": "channel_points_highlighted",
          "cheer": { "bits": 100 },
          "reply": null,
          "channel_points_custom_reward_id": null
        }
        """
        let chat = try EventSubMapper.chatMessage(fromEvent: Data(json.utf8), timestamp: timestamp)
        #expect(chat.bits == 100)
        #expect(chat.messageType == .channelPointsHighlighted)
        #expect(chat.author.color == nil)
        guard case let .cheermote(cheer) = chat.fragments[0] else {
            Issue.record("fragment 0 not cheermote")
            return
        }
        #expect(cheer.prefix == "cheer")
        #expect(cheer.bits == 100)
        #expect(cheer.tier == 1)
        #expect(cheer.text == "cheer100")
    }

    @Test("Detects leading ACTION byte as isAction")
    func actionDetection() throws {
        let json = """
        {
          "broadcaster_user_id": "1971641",
          "chatter_user_id": "4145994",
          "chatter_user_login": "viewer32",
          "chatter_user_name": "viewer32",
          "message_id": "msg-action",
          "color": "#FFFFFF",
          "message": {
            "text": "\\u0001ACTION waves\\u0001",
            "fragments": [
              { "type": "text", "text": "\\u0001ACTION waves\\u0001", "cheermote": null, "emote": null, "mention": null }
            ]
          },
          "badges": [],
          "message_type": "text",
          "cheer": null,
          "reply": null
        }
        """
        let chat = try EventSubMapper.chatMessage(fromEvent: Data(json.utf8), timestamp: timestamp)
        #expect(chat.isAction == true)
    }

    @Test("Maps a chat.notification into a ChatMessage carrying a ChannelNotice")
    func notificationMapping() throws {
        let json = """
        {
          "broadcaster_user_id": "1971641",
          "chatter_user_id": "4145994",
          "chatter_user_login": "viewer32",
          "chatter_user_name": "viewer32",
          "message_id": "notif-1",
          "color": "#1E90FF",
          "message": {
            "text": "Thanks for the sub!",
            "fragments": [
              { "type": "text", "text": "Thanks for the sub!", "cheermote": null, "emote": null, "mention": null }
            ]
          },
          "badges": [
            { "set_id": "subscriber", "id": "0", "info": "1" }
          ],
          "system_message": "viewer32 subscribed at Tier 1.",
          "notice_type": "sub"
        }
        """
        let chat = try EventSubMapper.notification(fromEvent: Data(json.utf8), timestamp: timestamp)
        let notice = try #require(chat.notice)
        #expect(notice.kind == .sub)
        #expect(notice.systemMessage == "viewer32 subscribed at Tier 1.")
        #expect(chat.plainText == "Thanks for the sub!")
        #expect(chat.author.color == ChatColor(hex: "#1E90FF"))
    }

    @Test("Maps a message_delete notification to ChatEvent.deleteMessage")
    func messageDelete() throws {
        let envelope = """
        {
          "metadata": {
            "message_id": "befa7b53-d79d-478f-86b9-120f112b044e",
            "message_type": "notification",
            "message_timestamp": "2022-11-16T10:11:12.464757833Z",
            "subscription_type": "channel.chat.message_delete",
            "subscription_version": "1"
          },
          "payload": {
            "subscription": {
              "id": "f1c2a387-161a-49f9-a165-0f21d7a4e1c4",
              "type": "channel.chat.message_delete",
              "version": "1",
              "status": "enabled"
            },
            "event": {
              "broadcaster_user_id": "1971641",
              "broadcaster_user_login": "streamer",
              "broadcaster_user_name": "streamer",
              "target_user_id": "4145994",
              "target_user_login": "viewer32",
              "target_user_name": "viewer32",
              "message_id": "del-abc-123"
            }
          }
        }
        """
        guard case let .notification(subscriptionType, eventData) = try EventSubMessage.decode(Data(envelope.utf8)) else {
            Issue.record("expected notification")
            return
        }
        #expect(subscriptionType == "channel.chat.message_delete")
        let event = try EventSubMapper.chatEvent(
            subscriptionType: subscriptionType,
            eventData: eventData,
            timestamp: timestamp
        )
        #expect(event == .deleteMessage(messageID: "del-abc-123"))
    }

    @Test("Maps clear_user_messages and clear to ChatEvents")
    func clearEvents() throws {
        let clearUser = """
        {
          "broadcaster_user_id": "1971641",
          "broadcaster_user_login": "streamer",
          "broadcaster_user_name": "streamer",
          "target_user_id": "4145994",
          "target_user_login": "viewer32",
          "target_user_name": "viewer32"
        }
        """
        let userEvent = try EventSubMapper.chatEvent(
            subscriptionType: "channel.chat.clear_user_messages",
            eventData: Data(clearUser.utf8),
            timestamp: timestamp
        )
        #expect(userEvent == .clearUserMessages(userID: "4145994", login: "viewer32"))

        let clear = """
        { "broadcaster_user_id": "1971641", "broadcaster_user_login": "streamer", "broadcaster_user_name": "streamer" }
        """
        let clearEvent = try EventSubMapper.chatEvent(
            subscriptionType: "channel.chat.clear",
            eventData: Data(clear.utf8),
            timestamp: timestamp
        )
        #expect(clearEvent == .clearChat)
    }

    @Test("Unsupported subscription type throws")
    func unsupportedSubscription() {
        #expect(throws: APIError.self) {
            _ = try EventSubMapper.chatEvent(
                subscriptionType: "channel.follow",
                eventData: Data("{}".utf8),
                timestamp: timestamp
            )
        }
    }

    @Test("Builds a channel.chat.message subscription request with the right JSON keys")
    func subscriptionRequest() throws {
        let request = EventSubSubscriptionRequest.chatMessage(
            broadcasterID: "1971641",
            userID: "4145994",
            sessionID: "AQoQILE98gtqShGmLD7AM6yJThAB"
        )
        #expect(request.type == "channel.chat.message")
        #expect(request.version == "1")
        #expect(request.condition["broadcaster_user_id"] == "1971641")
        #expect(request.condition["user_id"] == "4145994")
        #expect(request.transport.method == "websocket")
        #expect(request.transport.sessionID == "AQoQILE98gtqShGmLD7AM6yJThAB")

        let data = try request.encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "channel.chat.message")
        #expect(object["version"] as? String == "1")
        let condition = try #require(object["condition"] as? [String: String])
        #expect(condition["broadcaster_user_id"] == "1971641")
        #expect(condition["user_id"] == "4145994")
        let transport = try #require(object["transport"] as? [String: Any])
        #expect(transport["method"] as? String == "websocket")
        #expect(transport["session_id"] as? String == "AQoQILE98gtqShGmLD7AM6yJThAB")
    }

    @Test("Builds supplemental chat subscription requests with shared condition and version 1")
    func supplementalSubscriptionRequests() throws {
        let requests = EventSubSubscriptionRequest.supplementalChatSubscriptions(
            broadcasterID: "1971641",
            userID: "4145994",
            sessionID: "AQoQILE98gtqShGmLD7AM6yJThAB"
        )
        #expect(requests.map(\.type) == [
            "channel.chat.notification",
            "channel.chat.message_delete",
            "channel.chat.clear_user_messages",
            "channel.chat.clear",
        ])
        for request in requests {
            #expect(request.version == "1")
            #expect(request.condition == [
                "broadcaster_user_id": "1971641",
                "user_id": "4145994",
            ])
            #expect(request.transport.method == "websocket")
            #expect(request.transport.sessionID == "AQoQILE98gtqShGmLD7AM6yJThAB")
            let object = try #require(try JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
            #expect(object["type"] as? String == request.type)
            let transport = try #require(object["transport"] as? [String: Any])
            #expect(transport["session_id"] as? String == "AQoQILE98gtqShGmLD7AM6yJThAB")
        }
    }

    private static let chatMessageEnvelope = """
    {
      "metadata": {
        "message_id": "befa7b53-d79d-478f-86b9-120f112b044e",
        "message_type": "notification",
        "message_timestamp": "2023-11-06T18:11:47.492253549Z",
        "subscription_type": "channel.chat.message",
        "subscription_version": "1"
      },
      "payload": {
        "subscription": {
          "id": "f1c2a387-161a-49f9-a165-0f21d7a4e1c4",
          "status": "enabled",
          "type": "channel.chat.message",
          "version": "1",
          "condition": { "broadcaster_user_id": "1971641", "user_id": "2914196" },
          "transport": { "method": "websocket", "session_id": "AQoQexampleid" },
          "created_at": "2023-11-06T18:11:47.492253549Z",
          "cost": 0
        },
        "event": {
          "broadcaster_user_id": "1971641",
          "broadcaster_user_login": "streamer",
          "broadcaster_user_name": "streamer",
          "chatter_user_id": "4145994",
          "chatter_user_login": "viewer32",
          "chatter_user_name": "viewer32",
          "message_id": "cc106a89-1814-919d-454c-f4f2f970aae7",
          "message": {
            "text": "Hey @Twitch PogChamp",
            "fragments": [
              { "type": "text", "text": "Hey ", "cheermote": null, "emote": null, "mention": null },
              {
                "type": "mention",
                "text": "@Twitch",
                "cheermote": null,
                "emote": null,
                "mention": { "user_id": "12826", "user_login": "twitch", "user_name": "Twitch" }
              },
              {
                "type": "emote",
                "text": " PogChamp",
                "cheermote": null,
                "emote": { "id": "emotesv2_a1b2c3", "emote_set_id": "0", "owner_id": "12826", "format": ["static", "animated"] },
                "mention": null
              }
            ]
          },
          "color": "#00FF7F",
          "badges": [
            { "set_id": "moderator", "id": "1", "info": "" },
            { "set_id": "subscriber", "id": "12", "info": "16" }
          ],
          "message_type": "text",
          "cheer": null,
          "reply": {
            "parent_message_id": "parent-123",
            "parent_user_id": "12826",
            "parent_user_login": "twitch",
            "parent_user_name": "Twitch",
            "parent_message_body": "hello there",
            "thread_message_id": "thread-123",
            "thread_user_id": "12826",
            "thread_user_login": "twitch",
            "thread_user_name": "Twitch"
          },
          "channel_points_custom_reward_id": null
        }
      }
    }
    """
}
