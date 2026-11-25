import Foundation
import Testing
@testable import EmbrCore

@Suite("Helix lists")
struct HelixListsTests {
    private let factory = HelixRequestFactory(clientID: "abc123")

    @Test("chatters builds the documented query and clamps the page size")
    func chattersRequest() throws {
        let request = factory.chatters(broadcasterID: "1", moderatorID: "2", first: 5000, after: "CURSOR", token: "tok")
        #expect(request.method == .get)
        #expect(request.headers["Authorization"] == "Bearer tok")
        #expect(request.headers["Client-Id"] == "abc123")
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/helix/chat/chatters")
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "broadcaster_id", value: "1")))
        #expect(items.contains(URLQueryItem(name: "moderator_id", value: "2")))
        #expect(items.contains(URLQueryItem(name: "first", value: "1000")))
        #expect(items.contains(URLQueryItem(name: "after", value: "CURSOR")))
    }

    @Test("userEmotes names the user and optionally the broadcaster, with no page size")
    func userEmotesRequest() throws {
        let request = factory.userEmotes(userID: "7", broadcasterID: "9", after: "NEXT", token: "tok")
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/helix/chat/emotes/user")
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "user_id", value: "7")))
        #expect(items.contains(URLQueryItem(name: "broadcaster_id", value: "9")))
        #expect(items.contains(URLQueryItem(name: "after", value: "NEXT")))
        #expect(!items.contains { $0.name == "first" })
    }

    @Test("the three pinned-message requests use GET, PATCH and DELETE on chat/pins")
    func pinnedRequests() throws {
        let get = factory.pinnedMessage(broadcasterID: "1", moderatorID: "2", token: "t")
        #expect(get.method == .get && get.url.absoluteString == "https://api.twitch.tv/helix/chat/pins?broadcaster_id=1&moderator_id=2")

        let update = factory.updatePinnedMessage(broadcasterID: "1", moderatorID: "2", messageID: "m", durationSeconds: 5, token: "t")
        #expect(update.method == .patch)
        #expect(update.url.absoluteString.contains("message_id=m"))
        #expect(update.url.absoluteString.contains("duration_seconds=30"))

        let unpin = factory.unpinMessage(broadcasterID: "1", moderatorID: "2", messageID: "m", token: "t")
        #expect(unpin.method == .delete)
        #expect(unpin.url.absoluteString.contains("message_id=m"))
    }

    @Test("updatePinnedMessage omits the duration when it should stay until the stream ends")
    func updatePinnedWithoutDuration() throws {
        let request = factory.updatePinnedMessage(broadcasterID: "1", moderatorID: "2", messageID: "m", token: "t")
        #expect(!request.url.absoluteString.contains("duration_seconds"))
        let long = factory.updatePinnedMessage(broadcasterID: "1", moderatorID: "2", messageID: "m", durationSeconds: 9000, token: "t")
        #expect(long.url.absoluteString.contains("duration_seconds=1800"))
    }

    @Test("bannedUsers filters by user IDs and drops paging when it does")
    func bannedUsersFiltering() throws {
        let filtered = factory.bannedUsers(broadcasterID: "1", userIDs: ["a", "b"], first: 100, after: "C", token: "t")
        let items = try #require(URLComponents(url: filtered.url, resolvingAgainstBaseURL: false)).queryItems ?? []
        #expect(items.filter { $0.name == "user_id" }.compactMap(\.value) == ["a", "b"])
        #expect(!items.contains { $0.name == "first" || $0.name == "after" })

        let paged = factory.bannedUsers(broadcasterID: "1", first: 500, token: "t")
        let pageItems = try #require(URLComponents(url: paged.url, resolvingAgainstBaseURL: false)).queryItems ?? []
        #expect(pageItems.contains(URLQueryItem(name: "first", value: "100")))
    }

    @Test("moderators and vips hit their documented paths")
    func moderatorAndVIPRequests() throws {
        let moderators = factory.moderators(broadcasterID: "1", token: "t")
        #expect(moderators.url.absoluteString.hasPrefix("https://api.twitch.tv/helix/moderation/moderators?broadcaster_id=1"))
        let vips = factory.vips(broadcasterID: "1", token: "t")
        #expect(vips.url.absoluteString.hasPrefix("https://api.twitch.tv/helix/channels/vips?broadcaster_id=1"))
    }

    @Test("modifyChannel sends only the fields that were set")
    func modifyChannelRequest() throws {
        let request = factory.modifyChannel(
            broadcasterID: "1",
            update: ChannelUpdate(title: "New title", tags: ["English"], contentClassificationLabels: [ContentClassificationLabel(id: "Gambling", isEnabled: true)]),
            token: "t"
        )
        #expect(request.method == .patch)
        #expect(request.headers["Content-Type"] == "application/json")
        let body = try #require(request.body)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["title"] as? String == "New title")
        #expect(payload["tags"] as? [String] == ["English"])
        let labels = try #require(payload["content_classification_labels"] as? [[String: Any]])
        #expect(labels.first?["id"] as? String == "Gambling")
        #expect(labels.first?["is_enabled"] as? Bool == true)
        #expect(payload["game_id"] == nil)
        #expect(payload["broadcaster_language"] == nil)
        #expect(payload["delay"] == nil)
        #expect(payload["is_branded_content"] == nil)
    }

    @Test("chatters decode with the total and the cursor")
    func chattersDecode() throws {
        let json = """
        {
          "data": [
            { "user_id": "1", "user_login": "alpha", "user_name": "Alpha" },
            { "user_id": "2", "user_login": "beta", "user_name": "Beta" }
          ],
          "pagination": { "cursor": "CURSOR" },
          "total": 42
        }
        """
        let page = try TwitchJSON.decode(HelixResponse<ChannelUser>.self, from: Data(json.utf8))
        #expect(page.data.map(\.userLogin) == ["alpha", "beta"])
        #expect(page.data[0].id == "1")
        #expect(page.pagination?.cursor == "CURSOR")
        #expect(page.total == 42)
    }

    @Test("bannedUsers decodes a permanent ban from the empty expiry string and a timeout from a timestamp")
    func bannedDecode() throws {
        let json = """
        {
          "data": [
            {
              "user_id": "1", "user_login": "alpha", "user_name": "Alpha",
              "expires_at": "", "created_at": "2024-01-02T03:04:05Z",
              "reason": "spam", "moderator_id": "9", "moderator_login": "mod", "moderator_name": "Mod"
            },
            {
              "user_id": "2", "user_login": "beta", "user_name": "Beta",
              "expires_at": "2024-01-02T04:00:00.500Z", "created_at": "2024-01-02T03:00:00Z",
              "reason": null, "moderator_id": "9", "moderator_login": "mod", "moderator_name": "Mod"
            }
          ],
          "pagination": { "cursor": "C" }
        }
        """
        let page = try TwitchJSON.decode(HelixResponse<BannedUser>.self, from: Data(json.utf8))
        #expect(page.data.count == 2)
        #expect(page.data[0].isPermanent)
        #expect(page.data[0].reason == "spam")
        #expect(page.data[0].createdAt == Date(timeIntervalSince1970: 1_704_164_645))
        #expect(!page.data[1].isPermanent)
        #expect(page.data[1].expiresAt?.timeIntervalSince1970 == 1_704_168_000.5)
        #expect(page.data[1].reason == nil)
    }

    @Test("pinnedMessage decodes fragments into the chat model and tolerates a null message")
    func pinnedDecode() throws {
        let json = """
        {
          "data": [
            {
              "message_id": "m1", "broadcaster_id": "b1",
              "sender_user_id": "s1", "sender_user_login": "sender", "sender_user_name": "Sender",
              "pinned_by_user_id": "p1", "pinned_by_user_login": "pinner", "pinned_by_user_name": "Pinner",
              "message": {
                "text": "hi Kappa @bob cheer100",
                "fragments": [
                  { "type": "text", "text": "hi " },
                  { "type": "emote", "text": "Kappa", "emote": { "id": "25", "emote_set_id": "0", "owner_id": "1", "format": ["static"] } },
                  { "type": "mention", "text": "@bob", "mention": { "user_id": "9", "user_login": "bob", "user_name": "Bob" } },
                  { "type": "cheermote", "text": "cheer100", "cheermote": { "prefix": "cheer", "bits": 100, "tier": 1 } }
                ]
              },
              "starts_at": "2024-01-02T03:04:05Z",
              "ends_at": null,
              "updated_at": "2024-01-02T03:04:06Z"
            }
          ]
        }
        """
        let page = try TwitchJSON.decode(HelixResponse<PinnedMessage>.self, from: Data(json.utf8))
        let pinned = try #require(page.data.first)
        #expect(pinned.id == "m1")
        #expect(pinned.fragments.count == 4)
        #expect(pinned.fragments[1] == .emote(TwitchEmoteRef(id: "25", text: "Kappa", setID: "0", ownerID: "1", formats: [.static])))
        #expect(pinned.fragments[2] == .mention(MentionRef(userID: "9", login: "bob", displayName: "Bob")))
        #expect(pinned.fragments[3] == .cheermote(CheermoteRef(prefix: "cheer", bits: 100, tier: 1, text: "cheer100")))
        #expect(pinned.isPinnedUntilStreamEnds)

        let nullMessage = """
        { "data": [ { "message_id": "m2", "broadcaster_id": "b1", "sender_user_id": "s", "sender_user_login": "s", "sender_user_name": "S", "pinned_by_user_id": "p", "pinned_by_user_login": "p", "pinned_by_user_name": "P", "message": null, "starts_at": "2024-01-02T03:04:05Z", "ends_at": "2024-01-02T05:04:05Z", "updated_at": "2024-01-02T03:04:05Z" } ] }
        """
        let nullPage = try TwitchJSON.decode(HelixResponse<PinnedMessage>.self, from: Data(nullMessage.utf8))
        #expect(nullPage.data[0].text == nil)
        #expect(nullPage.data[0].fragments.isEmpty)
        #expect(!nullPage.data[0].isPinnedUntilStreamEnds)
    }

    @Test("user emotes map the CDN template into image URLs")
    func userEmotesDecode() throws {
        let json = """
        {
          "data": [
            {
              "id": "25", "name": "Kappa", "emote_type": "globals", "emote_set_id": "0", "owner_id": "",
              "format": ["static", "animated"], "scale": ["1.0", "2.0", "3.0"], "theme_mode": ["dark", "light"],
              "template": "https://static-cdn.jtvnw.net/emoticons/v2/{{id}}/{{format}}/{{theme_mode}}/{{scale}}"
            }
          ],
          "pagination": { "cursor": "C" }
        }
        """
        let page = try UserEmoteDecoder.decode(Data(json.utf8))
        let emote = try #require(page.data.first)
        #expect(emote.id == "25")
        #expect(emote.emoteType == "globals")
        #expect(emote.setID == "0")
        #expect(emote.ownerID == nil)
        #expect(emote.isAnimated)
        #expect(emote.emote.images.url(preferring: .x1)?.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/1.0")
        #expect(emote.emote.images.url(preferring: .x4)?.absoluteString == "https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/3.0")
        #expect(page.pagination?.cursor == "C")
    }
}

@Suite("OAuth tokens")
struct OAuthTokenTests {
    @Test("the client credentials grant asks for an app token")
    func appTokenRequest() throws {
        let request = AppAccessToken.request(clientID: "abc", clientSecret: "s3cr3t", scopes: ["chat:read", "user:read:emotes"])
        #expect(request.method == .post)
        #expect(request.url == AppAccessToken.endpoint)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        let fields = try formFields(request)
        #expect(fields["client_id"] == "abc")
        #expect(fields["client_secret"] == "s3cr3t")
        #expect(fields["grant_type"] == "client_credentials")
        #expect(fields["scope"] == "chat:read user:read:emotes")
    }

    @Test("the refresh grant omits a secret for public clients and sends it for confidential ones")
    func refreshRequests() throws {
        let publicClient = TokenRefresh.request(clientID: "abc", refreshToken: "refresh-token")
        let publicFields = try formFields(publicClient)
        #expect(publicFields["grant_type"] == "refresh_token")
        #expect(publicFields["refresh_token"] == "refresh-token")
        #expect(publicFields["client_secret"] == nil)

        let confidential = TokenRefresh.request(clientID: "abc", clientSecret: "s3cr3t", refreshToken: "refresh-token")
        #expect(try formFields(confidential)["client_secret"] == "s3cr3t")
    }

    @Test("a token decodes with optional fields left out")
    func tokenDecode() throws {
        let json = #"{ "access_token": "tok", "expires_in": 3600 }"#
        let token = try AppAccessToken.decode(HTTPResponse(status: 200, headers: [:], body: Data(json.utf8)))
        #expect(token.accessToken == "tok")
        #expect(token.expiresIn == 3600)
        #expect(token.tokenType == "bearer")
        #expect(token.scope.isEmpty)
        #expect(token.refreshToken == nil)
    }

    @Test("a failed grant throws instead of returning a token")
    func failedGrantThrows() {
        #expect(throws: APIError.self) {
            try TokenRefresh.decode(HTTPResponse(status: 400, headers: [:], body: Data(#"{"message":"invalid grant"}"#.utf8)))
        }
    }

    private func formFields(_ request: HTTPRequest) throws -> [String: String] {
        let raw = String(decoding: try #require(request.body), as: UTF8.self)
        var components = URLComponents()
        components.percentEncodedQuery = raw
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
