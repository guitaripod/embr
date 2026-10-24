import Foundation
import Testing
@testable import EmbrCore

@Suite struct SevenTVProviderTests {
    static let userJSON = """
    {
      "emote_set": {
        "id": "01F6ME4ASR000FB9N9J6WKD0HS",
        "emotes": [
          {
            "id": "60ae958e229664e8667aea38",
            "name": "EZ",
            "flags": 0,
            "data": {
              "animated": false,
              "host": {
                "url": "//cdn.7tv.app/emote/60ae958e229664e8667aea38",
                "files": [
                  { "name": "1x.avif", "format": "AVIF", "width": 32, "height": 32, "frame_count": 1 },
                  { "name": "1x.webp", "format": "WEBP", "width": 32, "height": 32, "frame_count": 1 },
                  { "name": "2x.webp", "format": "WEBP", "width": 64, "height": 64, "frame_count": 1 },
                  { "name": "3x.webp", "format": "WEBP", "width": 96, "height": 96, "frame_count": 1 },
                  { "name": "4x.webp", "format": "WEBP", "width": 128, "height": 128, "frame_count": 1 }
                ]
              }
            }
          },
          {
            "id": "60b00d1f0d3a78a196f803e3",
            "name": "RainTime",
            "flags": 256,
            "data": {
              "animated": true,
              "host": {
                "url": "//cdn.7tv.app/emote/60b00d1f0d3a78a196f803e3",
                "files": [
                  { "name": "1x.webp", "format": "WEBP", "width": 48, "height": 32, "frame_count": 30 },
                  { "name": "2x.webp", "format": "WEBP", "width": 96, "height": 64, "frame_count": 30 }
                ]
              }
            }
          },
          {
            "id": "60ae6a6f259ac5a73e56a426",
            "name": "Clap",
            "flags": 0,
            "data": {
              "animated": false,
              "host": {
                "url": "//cdn.7tv.app/emote/60ae6a6f259ac5a73e56a426",
                "files": [
                  { "name": "1x.webp", "format": "WEBP", "width": 33, "height": 32, "frame_count": 4 }
                ]
              }
            }
          }
        ]
      }
    }
    """

    static let globalJSON = """
    {
      "id": "global",
      "emotes": [
        {
          "id": "01F6ME4ASR000FB9N9J6WKD0HS",
          "name": "PauseChamp",
          "flags": 0,
          "data": {
            "animated": false,
            "host": {
              "url": "//cdn.7tv.app/emote/01F6ME4ASR000FB9N9J6WKD0HS",
              "files": [
                { "name": "1x.webp", "format": "WEBP", "width": 32, "height": 32, "frame_count": 1 }
              ]
            }
          }
        }
      ]
    }
    """

    @Test func decodesUserResponse() throws {
        let (setID, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        #expect(setID == "01F6ME4ASR000FB9N9J6WKD0HS")
        #expect(emotes.count == 3)
    }

    @Test func zeroWidthFlagged() throws {
        let (_, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        let rainTime = try #require(emotes.first { $0.name == "RainTime" })
        #expect(rainTime.isZeroWidth)
        let ez = try #require(emotes.first { $0.name == "EZ" })
        #expect(!ez.isZeroWidth)
    }

    @Test func animatedDetection() throws {
        let (_, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        let rainTime = try #require(emotes.first { $0.name == "RainTime" })
        #expect(rainTime.isAnimated)
        let ez = try #require(emotes.first { $0.name == "EZ" })
        #expect(!ez.isAnimated)
        let clap = try #require(emotes.first { $0.name == "Clap" })
        #expect(clap.isAnimated)
    }

    @Test func cdnURLIsHTTPSAndWebp() throws {
        let (_, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        let ez = try #require(emotes.first { $0.name == "EZ" })
        let url = try #require(ez.images.url(preferring: .x1))
        #expect(url.absoluteString == "https://cdn.7tv.app/emote/60ae958e229664e8667aea38/1x.webp")
        #expect(url.scheme == "https")
        #expect(ez.images.urlsByScale[.x4] != nil)
    }

    @Test func skipsAvifKeepsWebpScales() throws {
        let (_, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        let ez = try #require(emotes.first { $0.name == "EZ" })
        #expect(ez.images.urlsByScale.count == 4)
        for url in ez.images.urlsByScale.values {
            #expect(url.absoluteString.hasSuffix(".webp"))
        }
    }

    @Test func aspectRatioFromX1() throws {
        let (_, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        let rainTime = try #require(emotes.first { $0.name == "RainTime" })
        #expect(abs(rainTime.aspectRatio - 1.5) < 0.0001)
    }

    @Test func providerIsSevenTV() throws {
        let (_, emotes) = try SevenTVDTO.emotes(fromUser: Data(Self.userJSON.utf8))
        #expect(emotes.allSatisfy { $0.provider == .sevenTV })
    }

    @Test func decodesGlobalResponse() throws {
        let emotes = try SevenTVDTO.emotes(fromGlobal: Data(Self.globalJSON.utf8))
        #expect(emotes.count == 1)
        #expect(emotes[0].name == "PauseChamp")
        #expect(emotes[0].provider == .sevenTV)
    }
}

@Suite struct BetterTTVProviderTests {
    static let globalJSON = """
    [
      { "id": "54fa8f1401e468494b85b537", "code": ":tf:", "imageType": "png", "animated": false },
      { "id": "566ca04265dbbdab32ec054a", "code": "OMEGALUL", "imageType": "png" },
      { "id": "5e76d399d6581c3724c0f0b8", "code": "weirdChamp", "imageType": "gif", "animated": true },
      { "id": "58487cad5b3fc8ee5f1fc099", "code": "SoSnowy", "imageType": "gif", "animated": true }
    ]
    """

    static let channelJSON = """
    {
      "id": "5561e02a5b2e0d8f5b1f3c0f",
      "channelEmotes": [
        { "id": "aaa111", "code": "catKISS", "imageType": "webp", "animated": false }
      ],
      "sharedEmotes": [
        { "id": "bbb222", "code": "peepoClap", "imageType": "gif", "animated": true },
        { "id": "ccc333", "code": "modCheck", "imageType": "png" }
      ]
    }
    """

    @Test func decodesGlobal() throws {
        let emotes = try BetterTTVDTO.globalEmotes(Data(Self.globalJSON.utf8))
        #expect(emotes.count == 4)
        #expect(emotes.allSatisfy { $0.provider == .betterTTV })
    }

    @Test func globalCDNURLs() throws {
        let emotes = try BetterTTVDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let lul = try #require(emotes.first { $0.name == "OMEGALUL" })
        let url1 = try #require(lul.images.url(preferring: .x1))
        #expect(url1.absoluteString == "https://cdn.betterttv.net/emote/566ca04265dbbdab32ec054a/1x")
        #expect(lul.images.urlsByScale[.x3]?.absoluteString == "https://cdn.betterttv.net/emote/566ca04265dbbdab32ec054a/3x")
        #expect(lul.images.urlsByScale.count == 3)
    }

    @Test func animatedByGifOrFlag() throws {
        let emotes = try BetterTTVDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let weird = try #require(emotes.first { $0.name == "weirdChamp" })
        #expect(weird.isAnimated)
        let tf = try #require(emotes.first { $0.name == ":tf:" })
        #expect(!tf.isAnimated)
    }

    @Test func zeroWidthFromHardcodedSet() throws {
        let emotes = try BetterTTVDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let snowy = try #require(emotes.first { $0.name == "SoSnowy" })
        #expect(snowy.isZeroWidth)
        let lul = try #require(emotes.first { $0.name == "OMEGALUL" })
        #expect(!lul.isZeroWidth)
    }

    @Test func channelConcatenatesChannelAndShared() throws {
        let emotes = try BetterTTVDTO.channelEmotes(Data(Self.channelJSON.utf8))
        #expect(emotes.count == 3)
        let names = emotes.map(\.name)
        #expect(names.contains("catKISS"))
        #expect(names.contains("peepoClap"))
        #expect(names.contains("modCheck"))
        #expect(names.first == "catKISS")
    }
}

@Suite struct FrankerFaceZProviderTests {
    static let globalJSON = """
    {
      "default_sets": [3],
      "sets": {
        "3": {
          "id": 3,
          "emoticons": [
            {
              "id": 28136,
              "name": "ZreknarF",
              "width": 40,
              "height": 32,
              "urls": { "1": "//cdn.frankerfacez.com/emote/28136/1", "2": "//cdn.frankerfacez.com/emote/28136/2", "4": "//cdn.frankerfacez.com/emote/28136/4" },
              "modifier": false
            },
            {
              "id": 4096,
              "name": "5Head",
              "width": 32,
              "height": 32,
              "urls": { "1": "//cdn.frankerfacez.com/emote/4096/1" },
              "animated": { "1": "//cdn.frankerfacez.com/emote/4096/animated/1", "2": "//cdn.frankerfacez.com/emote/4096/animated/2" }
            },
            {
              "id": 9999,
              "name": "cvHazmat",
              "width": 32,
              "height": 32,
              "urls": { "1": "//cdn.frankerfacez.com/emote/9999/1" },
              "modifier": true,
              "modifier_flags": 1
            }
          ]
        },
        "42": {
          "id": 42,
          "emoticons": [
            { "id": 1, "name": "ShouldNotAppear", "urls": { "1": "//cdn.frankerfacez.com/emote/1/1" } }
          ]
        }
      }
    }
    """

    static let roomJSON = """
    {
      "room": { "set": 555 },
      "sets": {
        "555": {
          "id": 555,
          "emoticons": [
            { "id": 70000, "name": "channelEmote", "width": 28, "height": 28, "urls": { "1": "//cdn.frankerfacez.com/emote/70000/1", "2": "//cdn.frankerfacez.com/emote/70000/2" } }
          ]
        },
        "3": {
          "id": 3,
          "emoticons": [
            { "id": 28136, "name": "GlobalLeftover", "urls": { "1": "//cdn.frankerfacez.com/emote/28136/1" } }
          ]
        }
      }
    }
    """

    @Test func globalPicksOnlyDefaultSets() throws {
        let emotes = try FrankerFaceZDTO.globalEmotes(Data(Self.globalJSON.utf8))
        #expect(emotes.count == 3)
        #expect(!emotes.contains { $0.name == "ShouldNotAppear" })
        #expect(emotes.allSatisfy { $0.provider == .frankerFaceZ })
    }

    @Test func protocolRelativeURLsBecomeHTTPS() throws {
        let emotes = try FrankerFaceZDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let zrek = try #require(emotes.first { $0.name == "ZreknarF" })
        let url = try #require(zrek.images.url(preferring: .x1))
        #expect(url.absoluteString == "https://cdn.frankerfacez.com/emote/28136/1")
        #expect(url.scheme == "https")
        #expect(zrek.images.urlsByScale[.x4] != nil)
    }

    @Test func animatedUsesAnimatedMap() throws {
        let emotes = try FrankerFaceZDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let fiveHead = try #require(emotes.first { $0.name == "5Head" })
        #expect(fiveHead.isAnimated)
        let url = try #require(fiveHead.images.url(preferring: .x1))
        #expect(url.absoluteString == "https://cdn.frankerfacez.com/emote/4096/animated/1")
        let zrek = try #require(emotes.first { $0.name == "ZreknarF" })
        #expect(!zrek.isAnimated)
    }

    @Test func modifierIsZeroWidth() throws {
        let emotes = try FrankerFaceZDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let hazmat = try #require(emotes.first { $0.name == "cvHazmat" })
        #expect(hazmat.isZeroWidth)
        let zrek = try #require(emotes.first { $0.name == "ZreknarF" })
        #expect(!zrek.isZeroWidth)
    }

    @Test func aspectRatio() throws {
        let emotes = try FrankerFaceZDTO.globalEmotes(Data(Self.globalJSON.utf8))
        let zrek = try #require(emotes.first { $0.name == "ZreknarF" })
        #expect(abs(zrek.aspectRatio - 1.25) < 0.0001)
    }

    @Test func roomPicksOnlyRoomSet() throws {
        let emotes = try FrankerFaceZDTO.roomEmotes(Data(Self.roomJSON.utf8))
        #expect(emotes.count == 1)
        #expect(emotes[0].name == "channelEmote")
        #expect(!emotes.contains { $0.name == "GlobalLeftover" })
    }
}

@Suite struct SevenTVEventFrameTests {
    static let helloJSON = """
    { "op": 1, "d": { "heartbeat_interval": 45000, "session_id": "abc123session" } }
    """

    static let heartbeatJSON = """
    { "op": 2, "d": { "count": 7 } }
    """

    static let dispatchJSON = """
    {
      "op": 0,
      "d": {
        "type": "emote_set.update",
        "body": {
          "id": "01F6ME4ASR000FB9N9J6WKD0HS",
          "actor": { "display_name": "ModUser" },
          "pushed": [
            {
              "key": "emotes",
              "index": 5,
              "value": {
                "id": "60ae958e229664e8667aea38",
                "name": "PogU",
                "flags": 0,
                "data": {
                  "animated": false,
                  "host": {
                    "url": "//cdn.7tv.app/emote/60ae958e229664e8667aea38",
                    "files": [
                      { "name": "1x.webp", "format": "WEBP", "width": 32, "height": 32, "frame_count": 1 }
                    ]
                  }
                }
              }
            }
          ],
          "pulled": [
            {
              "key": "emotes",
              "index": 2,
              "old_value": { "id": "deadbeef", "name": "OldEmote" }
            }
          ]
        }
      }
    }
    """

    @Test func decodesHello() throws {
        let event = try SevenTVEventFrame.decode(Data(Self.helloJSON.utf8))
        #expect(event == .hello(heartbeatMS: 45000, sessionID: "abc123session"))
    }

    @Test func decodesHeartbeat() throws {
        let event = try SevenTVEventFrame.decode(Data(Self.heartbeatJSON.utf8))
        #expect(event == .heartbeat)
    }

    @Test func decodesDispatchToEmoteSetUpdate() throws {
        let event = try SevenTVEventFrame.decode(Data(Self.dispatchJSON.utf8))
        guard case let .dispatch(update) = event else {
            Issue.record("expected dispatch, got \(event)")
            return
        }
        #expect(update.added.count == 1)
        #expect(update.added[0].name == "PogU")
        #expect(update.added[0].provider == .sevenTV)
        #expect(update.added[0].images.url(preferring: .x1)?.absoluteString == "https://cdn.7tv.app/emote/60ae958e229664e8667aea38/1x.webp")
        #expect(update.removed == ["OldEmote"])
        #expect(update.actor == "ModUser")
    }

    @Test func subscribeFrameBuildsExpectedPayload() throws {
        let data = try SevenTVEventFrame.subscribeFrame(emoteSetID: "SET42")
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["op"] as? Int == 35)
        let d = try #require(object["d"] as? [String: Any])
        #expect(d["type"] as? String == "emote_set.update")
        let condition = try #require(d["condition"] as? [String: Any])
        #expect(condition["object_id"] as? String == "SET42")
    }

    @Test func unknownOpIsOther() throws {
        let event = try SevenTVEventFrame.decode(Data("{ \"op\": 99 }".utf8))
        #expect(event == .other)
    }
}
