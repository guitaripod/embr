import Foundation
import Security
import EmbrCore

/// What the app leaves for the Top Shelf extension: whose streams to look for, and the last live streams it saw so the
/// shelf still shows something when the extension cannot reach Twitch. It travels in a keychain item of a shared
/// access group, the one store an app and its extension share without an App Group.
struct TopShelfSnapshot: Codable, Sendable, Equatable {
    struct Stream: Codable, Sendable, Equatable {
        let userID: String
        let login: String
        let name: String
        let title: String
        let game: String
        let viewers: Int
        let startedAt: Date
        let thumbnailTemplate: String

        init(_ stream: LiveStream) {
            userID = stream.userID
            login = stream.userLogin
            name = stream.userName
            title = stream.title
            game = stream.gameName
            viewers = stream.viewerCount
            startedAt = stream.startedAt
            thumbnailTemplate = stream.thumbnailURLTemplate
        }

        var liveStream: LiveStream {
            LiveStream(
                id: "shelf-\(userID)", userID: userID, userLogin: login, userName: name, gameID: "", gameName: game,
                title: title, viewerCount: viewers, startedAt: startedAt, language: "", thumbnailURLTemplate: thumbnailTemplate
            )
        }
    }

    /// Helix answers at most 100 user ids per request, favorites first.
    static let channelLimit = 100

    var favoriteIDs: [String]
    var followedIDs: [String]
    var live: [Stream]
    var updatedAt: Date
    var previews: Bool

    /// Every channel to look up, favorites first, each once, within one Helix request.
    var channelIDs: [String] {
        var seen: Set<String> = []
        return (favoriteIDs + followedIDs).filter { seen.insert($0).inserted }.prefix(Self.channelLimit).map { $0 }
    }
}

enum TopShelfSnapshotStore {
    private static let service = "com.guitaripod.embr.topshelf"
    private static let account = "snapshot"

    /// `<team prefix>com.guitaripod.embr.shelf`, written into both Info.plists by the build so neither binary hardcodes
    /// the team.
    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "EmbrShelfKeychainGroup") as? String
    }

    static func load() -> TopShelfSnapshot? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? TwitchJSON.decoder.decode(TopShelfSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: TopShelfSnapshot) -> Bool {
        guard let data = try? TwitchJSON.encoder.encode(snapshot) else { return false }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        let insert = baseQuery().merging(attributes) { _, new in new }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
