import Foundation

public struct StoredProfile: Codable, Sendable, Equatable {
    public var clientID: String?
    public var accessToken: String?
    public var refreshToken: String?
    public var scopes: [String]
    public var expiresAt: Date?
    public var userID: String?
    public var login: String?
    public var tokenKind: String?
    public var refreshURL: String?

    public init(
        clientID: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        scopes: [String] = [],
        expiresAt: Date? = nil,
        userID: String? = nil,
        login: String? = nil,
        tokenKind: String? = nil,
        refreshURL: String? = nil
    ) {
        self.clientID = clientID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.userID = userID
        self.login = login
        self.tokenKind = tokenKind
        self.refreshURL = refreshURL
    }
}

public struct CredentialsFile: Codable, Sendable {
    public var version: Int
    public var profiles: [String: StoredProfile]

    public init(version: Int = 1, profiles: [String: StoredProfile] = [:]) {
        self.version = version
        self.profiles = profiles
    }

    enum CodingKeys: String, CodingKey {
        case version
        case profiles
    }
}

public final class CredentialsStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    public convenience init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(url: Self.defaultURL(environment: environment))
    }

    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["EMBR_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override).appendingPathComponent("credentials.json")
        }
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("embr/credentials.json")
    }

    public func load() -> CredentialsFile {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else {
            return CredentialsFile()
        }
        return (try? Self.decoder.decode(CredentialsFile.self, from: data)) ?? CredentialsFile()
    }

    public func profile(_ name: String) -> StoredProfile? {
        load().profiles[name]
    }

    public func save(_ file: CredentialsFile) throws {
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try Self.encoder.encode(file)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    @discardableResult
    public func update(_ name: String, _ mutate: (inout CredentialsFile) -> Void) throws -> CredentialsFile {
        lock.lock()
        defer { lock.unlock() }
        var file: CredentialsFile
        if let data = try? Data(contentsOf: url),
           let decoded = try? Self.decoder.decode(CredentialsFile.self, from: data) {
            file = decoded
        } else {
            file = CredentialsFile()
        }
        mutate(&file)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try Self.encoder.encode(file)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return file
    }

    public func remove(_ name: String) throws {
        try update(name) { file in
            file.profiles.removeValue(forKey: name)
        }
    }

    public func permissions() -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
