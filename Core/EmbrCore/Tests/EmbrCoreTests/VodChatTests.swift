import Foundation
import Testing
@testable import EmbrCore

@Test func vodCommentsPageDecodesAndMapsToChat() throws {
    let json = """
    {
      "comments": [
        {
          "id": "comment-1",
          "offsetSeconds": 42,
          "createdAt": "2026-10-23T16:55:26.374Z",
          "authorID": "user-1",
          "authorLogin": "viewer",
          "authorName": "Viewer",
          "color": "#FF4500",
          "fragments": [
            { "text": "hello " },
            { "text": "Kappa", "emoteID": "25;6;11" }
          ]
        }
      ],
      "nextOffset": 43,
      "hasMore": true
    }
    """
    let page = try WorkerEndpoints.decodeVodComments(Data(json.utf8))

    #expect(page.nextOffset == 43)
    #expect(page.hasMore)
    #expect(page.comments.count == 1)

    let message = page.comments[0].chatMessage(channelID: "channel-1")
    #expect(message.id == "comment-1")
    #expect(message.channelID == "channel-1")
    #expect(message.author.login == "viewer")
    #expect(message.author.color == ChatColor(red: 255, green: 69, blue: 0))
    #expect(message.fragments.count == 2)
    guard case .emote(let emote) = message.fragments[1] else {
        Issue.record("Expected an emote fragment")
        return
    }
    #expect(emote.id == "25")
    #expect(emote.text == "Kappa")
}

@Test func vodCommentsEndpointCarriesOffset() throws {
    let endpoints = WorkerEndpoints(baseURL: URL(string: "https://api.example.com/v1/embr")!)
    let request = endpoints.vodComments(id: "12345", offset: 900)

    #expect(request.method == .get)
    #expect(request.url.absoluteString == "https://api.example.com/v1/embr/vod/12345/comments?offset=900")
}
