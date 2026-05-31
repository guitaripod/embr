import Foundation
import GRDB
import EmbrCore

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    private let queue: DatabaseQueue
    private let logger = AppLogger.shared
    private let recentEmoteCap = 48

    init(queue: DatabaseQueue? = nil) {
        if let queue {
            self.queue = queue
        } else {
            self.queue = Self.openDefaultQueue()
        }
        do {
            try Self.migrator.migrate(self.queue)
        } catch {
            AppLogger.shared.error("database migration failed: \(error)", category: .persistence)
        }
    }

    private static func openDefaultQueue() -> DatabaseQueue {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let url = support.appendingPathComponent("embr.sqlite")
            return try DatabaseQueue(path: url.path)
        } catch {
            AppLogger.shared.error("failed to open database, using in-memory: \(error)", category: .persistence)
            return try! DatabaseQueue()
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: JoinedChannelRecord.databaseTableName) { t in
                t.column("broadcasterID", .text).primaryKey()
                t.column("login", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(table: RecentEmoteRecord.databaseTableName) { t in
                t.column("name", .text).primaryKey()
                t.column("provider", .text).notNull()
                t.column("usedAt", .datetime).notNull()
            }
            try db.create(table: BlockedUserRecord.databaseTableName) { t in
                t.column("userID", .text).primaryKey()
                t.column("login", .text).notNull()
            }
            try db.create(table: CustomCommandRecord.databaseTableName) { t in
                t.column("trigger", .text).primaryKey()
                t.column("expansion", .text).notNull()
            }
            try db.create(table: AccountRecord.databaseTableName) { t in
                t.column("userID", .text).primaryKey()
                t.column("login", .text).notNull()
                t.column("displayName", .text).notNull()
            }
        }
        return migrator
    }

    func joinedChannels() async -> [JoinedChannelRecord] {
        await read { db in
            try JoinedChannelRecord
                .order(JoinedChannelRecord.Columns.addedAt.desc)
                .fetchAll(db)
        } ?? []
    }

    func addJoinedChannel(_ record: JoinedChannelRecord) async {
        await write { db in
            try record.save(db)
        }
    }

    func removeJoinedChannel(broadcasterID: String) async {
        await write { db in
            _ = try JoinedChannelRecord.deleteOne(db, key: broadcasterID)
        }
    }

    func recentEmotes() async -> [RecentEmoteRecord] {
        await read { db in
            try RecentEmoteRecord
                .order(RecentEmoteRecord.Columns.usedAt.desc)
                .limit(self.recentEmoteCap)
                .fetchAll(db)
        } ?? []
    }

    func bumpRecentEmote(name: String, provider: String) async {
        let record = RecentEmoteRecord(name: name, provider: provider, usedAt: Date())
        await write { db in
            try record.save(db)
            let keep = try RecentEmoteRecord
                .order(RecentEmoteRecord.Columns.usedAt.desc)
                .limit(self.recentEmoteCap)
                .fetchAll(db)
                .map(\.name)
            if !keep.isEmpty {
                try RecentEmoteRecord
                    .filter(!keep.contains(RecentEmoteRecord.Columns.name))
                    .deleteAll(db)
            }
        }
    }

    func setBlockedUser(userID: String, login: String) async {
        let record = BlockedUserRecord(userID: userID, login: login)
        await write { db in
            try record.save(db)
        }
    }

    func removeBlockedUser(userID: String) async {
        await write { db in
            _ = try BlockedUserRecord.deleteOne(db, key: userID)
        }
    }

    func isBlocked(userID: String) async -> Bool {
        await read { db in
            try BlockedUserRecord.exists(db, key: userID)
        } ?? false
    }

    func blockedUsers() async -> [BlockedUserRecord] {
        await read { db in
            try BlockedUserRecord.order(BlockedUserRecord.Columns.login).fetchAll(db)
        } ?? []
    }

    func customCommands() async -> [CustomCommandRecord] {
        await read { db in
            try CustomCommandRecord.order(CustomCommandRecord.Columns.trigger).fetchAll(db)
        } ?? []
    }

    func upsertCustomCommand(_ record: CustomCommandRecord) async {
        await write { db in
            try record.save(db)
        }
    }

    func deleteCustomCommand(trigger: String) async {
        await write { db in
            _ = try CustomCommandRecord.deleteOne(db, key: trigger)
        }
    }

    func saveAccount(_ record: AccountRecord) async {
        await write { db in
            try AccountRecord.deleteAll(db)
            try record.save(db)
        }
    }

    func loadAccount() async -> AccountRecord? {
        await read { db in
            try AccountRecord.fetchOne(db)
        } ?? nil
    }

    func clearAccount() async {
        await write { db in
            try AccountRecord.deleteAll(db)
        }
    }

    @discardableResult
    private func write<T: Sendable>(_ body: @Sendable @escaping (Database) throws -> T) async -> T? {
        do {
            return try await queue.write(body)
        } catch {
            logger.error("database write failed: \(error)", category: .persistence)
            return nil
        }
    }

    private func read<T: Sendable>(_ body: @Sendable @escaping (Database) throws -> T) async -> T? {
        do {
            return try await queue.read(body)
        } catch {
            logger.error("database read failed: \(error)", category: .persistence)
            return nil
        }
    }
}
