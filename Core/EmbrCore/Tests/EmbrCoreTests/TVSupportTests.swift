import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import EmbrCore

@Suite struct DeviceAuthorizationTests {
    @Test func theStartRequestPostsTheClientAndScopesAsAForm() throws {
        let request = DeviceAuthorization.startRequest(clientID: "abc123")
        let body = try #require(request.body.map { String(decoding: $0, as: UTF8.self) })

        #expect(request.method == .post)
        #expect(request.url == DeviceAuthorization.deviceURL)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(body.contains("client_id=abc123"))
        #expect(body.contains("scopes=user:read:follows%20chat:read"))
    }

    @Test func theTokenRequestCarriesTheDeviceCodeGrant() throws {
        let request = DeviceAuthorization.tokenRequest(clientID: "abc", deviceCode: "dev+code")
        let body = try #require(request.body.map { String(decoding: $0, as: UTF8.self) })

        #expect(request.url == DeviceAuthorization.tokenURL)
        #expect(body.contains("device_code=dev%2Bcode"))
        #expect(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"))
        #expect(!body.contains("client_secret"))
    }

    @Test func theStartAnswerDecodes() throws {
        let json = """
        {"device_code":"d","expires_in":1800,"interval":5,"user_code":"HQDWXDJB","verification_uri":"https://www.twitch.tv/activate?device-code=HQDWXDJB"}
        """
        let start = try DeviceAuthorization.decodeStart(HTTPResponse(status: 200, headers: [:], body: Data(json.utf8)))

        #expect(start.userCode == "HQDWXDJB")
        #expect(start.verificationURI.absoluteString.hasSuffix("device-code=HQDWXDJB"))
        #expect(start.pollInterval == 5)
        #expect(DeviceAuthorization.displayCode(start.userCode) == "HQDW-XDJB")
    }

    @Test(arguments: [
        ("{\"status\":400,\"message\":\"authorization_pending\"}", 400, DeviceAuthorization.PollResult.pending),
        ("{\"status\":400,\"message\":\"slow_down\"}", 400, .slowDown),
        ("{\"status\":400,\"message\":\"invalid device code\"}", 400, .expired),
        ("{\"status\":400,\"message\":\"expired_token\"}", 400, .expired),
        ("{\"status\":400,\"message\":\"access_denied\"}", 400, .denied),
        ("", 429, .slowDown),
    ])
    func pollAnswersMapToTheirResult(body: String, status: Int, expected: DeviceAuthorization.PollResult) {
        let response = HTTPResponse(status: status, headers: [:], body: Data(body.utf8))
        #expect(DeviceAuthorization.pollResult(response) == expected)
    }

    @Test func anApprovedPollCarriesTheTokens() {
        let json = """
        {"access_token":"at","expires_in":14400,"refresh_token":"rt","scope":["chat:read","user:read:follows"],"token_type":"bearer"}
        """
        let result = DeviceAuthorization.pollResult(HTTPResponse(status: 200, headers: [:], body: Data(json.utf8)))

        #expect(result == .authorized(DeviceAuthorization.Token(accessToken: "at", refreshToken: "rt", expiresIn: 14400, scope: ["chat:read", "user:read:follows"])))
    }
}

@Suite struct FavoritesLedgerTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func favorite(_ id: String, at offset: TimeInterval) -> SyncedFavorite {
        SyncedFavorite(id: id, login: "login\(id)", name: "Name \(id)", addedAt: base.addingTimeInterval(offset))
    }

    @Test func aLaterRemovalWinsOverAnEarlierAdd() {
        var phone = FavoritesLedger()
        phone.add(favorite("1", at: 0))
        var tv = phone
        tv.remove(id: "1", at: base.addingTimeInterval(10))

        #expect(phone.merged(with: tv).active.isEmpty)
        #expect(tv.merged(with: phone).active.isEmpty)
    }

    @Test func aLaterAddWinsOverAnEarlierRemoval() {
        var phone = FavoritesLedger()
        phone.remove(id: "1", at: base)
        var tv = FavoritesLedger()
        tv.add(favorite("1", at: 5))

        #expect(phone.merged(with: tv).active.map(\.id) == ["1"])
        #expect(tv.merged(with: phone).active.map(\.id) == ["1"])
    }

    @Test func mergingIsTheSameInEitherOrderAndKeepsEveryStar() {
        var phone = FavoritesLedger()
        phone.add(favorite("1", at: 0))
        phone.add(favorite("2", at: 20))
        var tv = FavoritesLedger()
        tv.add(favorite("3", at: 10))
        tv.remove(id: "2", at: base.addingTimeInterval(5))

        let one = phone.merged(with: tv)
        let other = tv.merged(with: phone)

        #expect(one == other)
        #expect(one.active.map(\.id) == ["2", "3", "1"])
    }

    @Test func anOldRemovalIsForgotten() {
        var ledger = FavoritesLedger()
        ledger.remove(id: "1", at: base)

        #expect(ledger.pruned(now: base.addingTimeInterval(FavoritesLedger.removalMemory - 1)).removals.count == 1)
        #expect(ledger.pruned(now: base.addingTimeInterval(FavoritesLedger.removalMemory + 1)).removals.isEmpty)
    }

    @Test func theLedgerRoundTripsThroughJSON() throws {
        var ledger = FavoritesLedger()
        ledger.add(favorite("1", at: 0))
        ledger.remove(id: "9", at: base)
        let data = try JSONEncoder().encode(ledger)

        #expect(try JSONDecoder().decode(FavoritesLedger.self, from: data) == ledger)
    }
}

@Suite struct MultiviewLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test(arguments: [(1, nil), (2, nil), (3, nil), (3, 2), (4, nil), (4, 1)] as [(Int, Int?)])
    func tilesKeepTheStreamShapeFitAndNeverOverlap(count: Int, featured: Int?) {
        let frames = MultiviewLayout.frames(count: count, featured: featured, in: bounds, spacing: 24)

        #expect(frames.count == count)
        for frame in frames {
            #expect(bounds.insetBy(dx: -1, dy: -1).contains(frame))
            #expect(abs(frame.width / frame.height - 16.0 / 9.0) < 0.02)
        }
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] {
                #expect(!frame.insetBy(dx: 1, dy: 1).intersects(other))
            }
        }
    }

    @Test func theFeaturedStreamIsTheLargest() {
        let frames = MultiviewLayout.frames(count: 4, featured: 2, in: bounds, spacing: 24)
        let largest = frames.enumerated().max { $0.element.width < $1.element.width }?.offset

        #expect(largest == 2)
    }

    @Test func gapsAreTheRequestedSpacing() {
        let frames = MultiviewLayout.frames(count: 2, featured: nil, in: bounds, spacing: 24)

        #expect(abs(frames[1].minX - frames[0].maxX - 24) <= 1)
    }

    @Test func moreThanFourStreamsAreCappedAndNothingFitsNowhere() {
        #expect(MultiviewLayout.frames(count: 6, featured: nil, in: bounds, spacing: 24).count == 4)
        #expect(MultiviewLayout.frames(count: 2, featured: nil, in: .zero, spacing: 24).isEmpty)
    }
}

@Suite struct SupporterAPITests {
    private let endpoints = WorkerEndpoints(baseURL: URL(string: "https://api.example.com/v1/embr")!)

    @Test func theDirectoryIsReadFromTheWorker() throws {
        #expect(endpoints.supporters().url.absoluteString == "https://api.example.com/v1/embr/supporters")
        let directory = try WorkerEndpoints.decodeSupporterDirectory(Data(#"{"supporters":["1","22"]}"#.utf8))
        #expect(directory.supporters == ["1", "22"])
    }

    @Test func aClaimPostsTheTransactionAndTheToken() throws {
        let request = endpoints.claimSupporter(SupporterAPI.ClaimRequest(signedTransaction: "jws", twitchAccessToken: "tok"))
        let body = try #require(request.body)
        let decoded = try JSONDecoder().decode(SupporterAPI.ClaimRequest.self, from: body)

        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://api.example.com/v1/embr/supporters/claim")
        #expect(decoded == SupporterAPI.ClaimRequest(signedTransaction: "jws", twitchAccessToken: "tok"))
    }

    @Test func theDirectoryCarriesEachSupportersNumberAndLook() throws {
        let json = #"{"supporters":["1","22"],"profiles":{"1":{"number":1,"color":"gold","nameStyle":"glow"},"22":{"number":null,"color":"neon","nameStyle":"sparkle"}},"count":2}"#
        let directory = try WorkerEndpoints.decodeSupporterDirectory(Data(json.utf8))
        let profiles = directory.resolvedProfiles

        #expect(directory.supporterCount == 2)
        #expect(profiles["1"] == SupporterAPI.Profile(number: 1, color: "gold", nameStyle: "glow"))
        #expect(profiles["1"]?.style == .glow)
        #expect(profiles["22"]?.number == nil)
        #expect(profiles["22"]?.style == .twitch)
    }

    @Test func aDirectoryFromAnOlderWorkerGivesEverySupporterTheDefaultLook() throws {
        let directory = try WorkerEndpoints.decodeSupporterDirectory(Data(#"{"supporters":["7"]}"#.utf8))

        #expect(directory.supporterCount == 1)
        #expect(directory.resolvedProfiles["7"] == SupporterAPI.Profile(number: nil, color: "violet", nameStyle: "twitch"))
    }

    @Test func aClaimAnswersWithTheFoundingNumberAndLook() throws {
        let claim = try WorkerEndpoints.decodeSupporterClaim(Data(#"{"twitchUserID":"111","number":12,"color":"mint","nameStyle":"color"}"#.utf8))
        let older = try WorkerEndpoints.decodeSupporterClaim(Data(#"{"twitchUserID":"111"}"#.utf8))

        #expect(claim.profile == SupporterAPI.Profile(number: 12, color: "mint", nameStyle: "color"))
        #expect(older.profile == SupporterAPI.Profile(number: nil, color: "violet", nameStyle: "twitch"))
    }

    @Test func aStyleChangePostsTheTokenColorAndNameStyle() throws {
        let request = endpoints.updateSupporterStyle(SupporterAPI.StyleRequest(twitchAccessToken: "tok", color: "rose", nameStyle: .glow))
        let body = try #require(request.body)
        let decoded = try JSONDecoder().decode(SupporterAPI.StyleRequest.self, from: body)
        let answer = try WorkerEndpoints.decodeSupporterProfile(Data(#"{"id":"111","number":3,"color":"rose","nameStyle":"glow"}"#.utf8))

        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://api.example.com/v1/embr/supporters/style")
        #expect(decoded == SupporterAPI.StyleRequest(twitchAccessToken: "tok", color: "rose", nameStyle: .glow))
        #expect(answer == SupporterAPI.Profile(number: 3, color: "rose", nameStyle: "glow"))
    }
}
