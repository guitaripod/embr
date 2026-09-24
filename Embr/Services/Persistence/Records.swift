import Foundation
import GRDB

/// A row of the Favorites list. The table was created in v1 for joined chat rooms and never
/// used; Favorites adopted it as-is so the shipped migration stays untouched.
nonisolated struct JoinedChannelRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    var broadcasterID: String
    var login: String
    var displayName: String
    var addedAt: Date

    static let databaseTableName = "joinedChannel"

    enum Columns {
        static let broadcasterID = Column("broadcasterID")
        static let login = Column("login")
        static let displayName = Column("displayName")
        static let addedAt = Column("addedAt")
    }
}

nonisolated struct RecentEmoteRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    var name: String
    var provider: String
    var usedAt: Date

    static let databaseTableName = "recentEmote"

    enum Columns {
        static let name = Column("name")
        static let provider = Column("provider")
        static let usedAt = Column("usedAt")
    }
}

nonisolated struct BlockedUserRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    var userID: String
    var login: String

    static let databaseTableName = "blockedUser"

    enum Columns {
        static let userID = Column("userID")
        static let login = Column("login")
    }
}

nonisolated struct CustomCommandRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    var trigger: String
    var expansion: String

    static let databaseTableName = "customCommand"

    enum Columns {
        static let trigger = Column("trigger")
        static let expansion = Column("expansion")
    }
}

nonisolated struct AccountRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    var userID: String
    var login: String
    var displayName: String

    static let databaseTableName = "account"

    enum Columns {
        static let userID = Column("userID")
        static let login = Column("login")
        static let displayName = Column("displayName")
    }
}
