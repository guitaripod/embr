import Foundation
import Testing
@testable import EmbrCore

@Suite("Helix")
struct HelixTests {
    private static let streamsJSON = """
    {
      "data": [
        {
          "id": "123456789",
          "user_id": "98765",
          "user_login": "sandysanderman",
          "user_name": "SandySanderman",
          "game_id": "494131",
          "game_name": "Little Nightmares",
          "title": "hablamos y le damos a Little Nightmares 1",
          "viewer_count": 78365,
          "started_at": "2021-03-10T15:04:21Z",
          "language": "es",
          "thumbnail_url": "https://static-cdn.jtvnw.net/previews-ttv/live_user_sandysanderman-{width}x{height}.jpg",
          "tags": ["Espanol"],
          "is_mature": false
        }
      ],
      "pagination": { "cursor": "eyJiIjp7IkN1cnNvciI6ImV5SnoifX0" }
    }
    """

    @Test("HelixResponse<StreamDTO> decodes and maps to LiveStream")
    func decodeAndMapStreams() throws {
        let data = Data(Self.streamsJSON.utf8)
        let response = try TwitchJSON.decode(HelixResponse<StreamDTO>.self, from: data)
        #expect(response.data.count == 1)
        #expect(response.pagination?.cursor == "eyJiIjp7IkN1cnNvciI6ImV5SnoifX0")

        let stream = HelixMappers.liveStream(response.data[0])
        #expect(stream.id == "123456789")
        #expect(stream.userID == "98765")
        #expect(stream.userLogin == "sandysanderman")
        #expect(stream.userName == "SandySanderman")
        #expect(stream.gameID == "494131")
        #expect(stream.gameName == "Little Nightmares")
        #expect(stream.viewerCount == 78365)
        #expect(stream.language == "es")
        #expect(stream.tags == ["Espanol"])
        #expect(stream.isMature == false)
        #expect(stream.thumbnailURL(width: 320, height: 180)?.absoluteString
            == "https://static-cdn.jtvnw.net/previews-ttv/live_user_sandysanderman-320x180.jpg")
    }

    @Test("Stream DTO tolerates missing tags and is_mature")
    func decodeStreamWithMissingOptionals() throws {
        let json = """
        {
          "data": [
            {
              "id": "1",
              "user_id": "2",
              "user_login": "foo",
              "user_name": "Foo",
              "game_id": "3",
              "game_name": "Game",
              "title": "t",
              "viewer_count": 5,
              "started_at": "2021-03-10T15:04:21Z",
              "language": "en",
              "thumbnail_url": "https://x/{width}x{height}.jpg"
            }
          ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<StreamDTO>.self, from: Data(json.utf8))
        let stream = HelixMappers.liveStream(response.data[0])
        #expect(stream.tags.isEmpty)
        #expect(stream.isMature == false)
        #expect(response.pagination == nil)
    }

    @Test("Send-message response with is_sent false maps drop reason")
    func sendMessageDropped() throws {
        let json = """
        {
          "data": [
            {
              "message_id": "",
              "is_sent": false,
              "drop_reason": { "code": "channel_settings", "message": "Follower mode is enabled." }
            }
          ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<SendMessageResultDTO>.self, from: Data(json.utf8))
        let result = HelixMappers.sendResult(response.data[0])
        #expect(result.isSent == false)
        #expect(result.dropReason == "channel_settings: Follower mode is enabled.")
    }

    @Test("Send-message response when sent has no drop reason")
    func sendMessageSent() throws {
        let json = """
        {
          "data": [ { "message_id": "abc-123", "is_sent": true } ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<SendMessageResultDTO>.self, from: Data(json.utf8))
        let result = HelixMappers.sendResult(response.data[0])
        #expect(result.isSent == true)
        #expect(result.messageID == "abc-123")
        #expect(result.dropReason == nil)
    }

    @Test("Chat settings map to RoomState")
    func chatSettingsToRoomState() throws {
        let json = """
        {
          "data": [
            {
              "broadcaster_id": "1234",
              "emote_mode": true,
              "follower_mode": true,
              "follower_mode_duration": 30,
              "slow_mode": true,
              "slow_mode_wait_time": 10,
              "subscriber_mode": false,
              "unique_chat_mode": false
            }
          ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<ChatSettingsDTO>.self, from: Data(json.utf8))
        let state = HelixMappers.roomState(response.data[0])
        #expect(state.emoteOnly == true)
        #expect(state.followersOnly == 30)
        #expect(state.slowMode == 10)
        #expect(state.subscribersOnly == false)
        #expect(state.uniqueChat == false)
    }

    @Test("Chat settings with disabled follower and slow modes yield nil")
    func chatSettingsDisabledModes() throws {
        let json = """
        {
          "data": [
            {
              "broadcaster_id": "1234",
              "emote_mode": false,
              "follower_mode": false,
              "follower_mode_duration": null,
              "slow_mode": false,
              "slow_mode_wait_time": null,
              "subscriber_mode": true,
              "unique_chat_mode": true
            }
          ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<ChatSettingsDTO>.self, from: Data(json.utf8))
        let state = HelixMappers.roomState(response.data[0])
        #expect(state.followersOnly == nil)
        #expect(state.slowMode == nil)
        #expect(state.subscribersOnly == true)
        #expect(state.uniqueChat == true)
    }

    @Test("Emote DTO maps to twitch Emote with image scales and animated flag")
    func emoteMapping() throws {
        let json = """
        {
          "data": [
            {
              "id": "304456832",
              "name": "twitchdevPitchfork",
              "images": {
                "url_1x": "https://static-cdn.jtvnw.net/emoticons/v2/304456832/static/light/1.0",
                "url_2x": "https://static-cdn.jtvnw.net/emoticons/v2/304456832/static/light/2.0",
                "url_4x": "https://static-cdn.jtvnw.net/emoticons/v2/304456832/static/light/3.0"
              },
              "format": ["static", "animated"],
              "scale": ["1.0", "2.0", "3.0"],
              "theme_mode": ["light", "dark"],
              "emote_type": "subscriptions",
              "emote_set_id": "301590448",
              "owner_id": "141981764"
            }
          ],
          "template": "https://static-cdn.jtvnw.net/emoticons/v2/{{id}}/{{format}}/{{theme_mode}}/{{scale}}"
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<EmoteDTO>.self, from: Data(json.utf8))
        let emotes = HelixMappers.emotes(response.data)
        #expect(emotes.count == 1)
        let emote = emotes[0]
        #expect(emote.id == "304456832")
        #expect(emote.name == "twitchdevPitchfork")
        #expect(emote.provider == .twitch)
        #expect(emote.isAnimated == true)
        #expect(emote.ownerID == "141981764")
        #expect(emote.images.url(preferring: .x1)?.absoluteString
            == "https://static-cdn.jtvnw.net/emoticons/v2/304456832/static/light/1.0")
        #expect(emote.images.url(preferring: .x4)?.absoluteString
            == "https://static-cdn.jtvnw.net/emoticons/v2/304456832/static/light/3.0")
    }

    @Test("Badge set DTO maps to Badge per version")
    func badgeMapping() throws {
        let json = """
        {
          "data": [
            {
              "set_id": "subscriber",
              "versions": [
                {
                  "id": "0",
                  "image_url_1x": "https://static-cdn.jtvnw.net/badges/v1/sub0/1",
                  "image_url_2x": "https://static-cdn.jtvnw.net/badges/v1/sub0/2",
                  "image_url_4x": "https://static-cdn.jtvnw.net/badges/v1/sub0/3",
                  "title": "Subscriber",
                  "description": "Subscriber"
                }
              ]
            }
          ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<BadgeSetDTO>.self, from: Data(json.utf8))
        let badges = HelixMappers.badges(response.data)
        #expect(badges.count == 1)
        let badge = badges[0]
        #expect(badge.setID == "subscriber")
        #expect(badge.version == "0")
        #expect(badge.title == "Subscriber")
        #expect(badge.provider == .twitch)
        #expect(badge.images.url(preferring: .x1)?.absoluteString
            == "https://static-cdn.jtvnw.net/badges/v1/sub0/1")
    }

    @Test("Video DTO maps with parsed duration")
    func videoMapping() throws {
        let json = """
        {
          "data": [
            {
              "id": "335921245",
              "user_id": "141981764",
              "user_login": "twitchdev",
              "user_name": "TwitchDev",
              "title": "Twitch Developers 101",
              "created_at": "2018-11-14T21:30:18Z",
              "published_at": "2018-11-14T22:04:30Z",
              "thumbnail_url": "https://x/{width}x{height}.jpg",
              "view_count": 1863062,
              "duration": "3m21s",
              "type": "upload"
            }
          ]
        }
        """
        let response = try TwitchJSON.decode(HelixResponse<VideoDTO>.self, from: Data(json.utf8))
        let video = HelixMappers.video(response.data[0])
        #expect(video.id == "335921245")
        #expect(video.durationSeconds == 201)
        #expect(video.type == "upload")
    }

    @Test("Twitch durations parse to seconds")
    func durationParsing() {
        #expect(HelixDuration.seconds(from: "1h2m3s") == 3723)
        #expect(HelixDuration.seconds(from: "23m45s") == 1425)
        #expect(HelixDuration.seconds(from: "58s") == 58)
        #expect(HelixDuration.seconds(from: "3m21s") == 201)
        #expect(HelixDuration.seconds(from: "2h") == 7200)
        #expect(HelixDuration.seconds(from: "") == 0)
    }

    @Test("topStreams builds GET with correct path, query and headers")
    func topStreamsRequest() throws {
        let factory = HelixRequestFactory(clientID: "abc123")
        let request = factory.topStreams(first: 50, after: "CURSOR", token: "tok-xyz")

        #expect(request.method == .get)
        #expect(request.headers["Client-Id"] == "abc123")
        #expect(request.headers["Authorization"] == "Bearer tok-xyz")

        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "api.twitch.tv")
        #expect(components.path == "/helix/streams")

        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "type", value: "live")))
        #expect(items.contains(URLQueryItem(name: "first", value: "50")))
        #expect(items.contains(URLQueryItem(name: "after", value: "CURSOR")))
    }

    @Test("topStreams omits nil after cursor")
    func topStreamsNoCursor() throws {
        let factory = HelixRequestFactory(clientID: "abc123")
        let request = factory.topStreams(token: "tok")
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let names = (components.queryItems ?? []).map(\.name)
        #expect(!names.contains("after"))
    }

    @Test("sendChatMessage builds POST with JSON body and headers")
    func sendChatMessageRequest() throws {
        let factory = HelixRequestFactory(clientID: "abc123")
        let request = factory.sendChatMessage(
            broadcasterID: "12826",
            senderID: "141981764",
            message: "Hello, world!",
            replyParentMessageID: "parent-42",
            token: "tok-xyz"
        )

        #expect(request.method == .post)
        #expect(request.headers["Client-Id"] == "abc123")
        #expect(request.headers["Authorization"] == "Bearer tok-xyz")
        #expect(request.headers["Content-Type"] == "application/json")

        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/helix/chat/messages")

        let body = try #require(request.body)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(payload["broadcaster_id"] == "12826")
        #expect(payload["sender_id"] == "141981764")
        #expect(payload["message"] == "Hello, world!")
        #expect(payload["reply_parent_message_id"] == "parent-42")
    }

    @Test("banUser builds nested data JSON body with duration and reason")
    func banUserRequest() throws {
        let factory = HelixRequestFactory(clientID: "abc123")
        let request = factory.banUser(
            broadcasterID: "1234",
            moderatorID: "5678",
            userID: "9876",
            duration: 300,
            reason: "spam",
            token: "tok"
        )
        #expect(request.method == .post)

        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/helix/moderation/bans")
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "broadcaster_id", value: "1234")))
        #expect(items.contains(URLQueryItem(name: "moderator_id", value: "5678")))

        let body = try #require(request.body)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let inner = try #require(root["data"] as? [String: Any])
        #expect(inner["user_id"] as? String == "9876")
        #expect(inner["duration"] as? Int == 300)
        #expect(inner["reason"] as? String == "spam")
    }

    @Test("deleteMessage builds DELETE with message_id query")
    func deleteMessageRequest() throws {
        let factory = HelixRequestFactory(clientID: "abc123")
        let request = factory.deleteMessage(
            broadcasterID: "1234",
            moderatorID: "5678",
            messageID: "msg-1",
            token: "tok"
        )
        #expect(request.method == .delete)
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/helix/chat/messages")
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "message_id", value: "msg-1")))
        #expect(request.headers["Authorization"] == "Bearer tok")
    }

    @Test("usersByLogins repeats login query items")
    func usersByLoginsRequest() throws {
        let factory = HelixRequestFactory(clientID: "abc123")
        let request = factory.usersByLogins(["twitchdev", "twitch"], token: "tok")
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/helix/users")
        let logins = (components.queryItems ?? []).filter { $0.name == "login" }.compactMap(\.value)
        #expect(logins == ["twitchdev", "twitch"])
    }
}
