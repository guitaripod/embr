import Foundation

/// The `embr://` links that open a place in the Apple TV app: the Top Shelf's buttons and the deep links.
enum EmbrLink: Equatable, Sendable {
    case watch(login: String)
    case channel(login: String)

    static let scheme = "embr"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .watch(let login):
            components.host = "watch"
            components.path = "/\(login)"
        case .channel(let login):
            components.host = "channel"
            components.path = "/\(login)"
        }
        return components.url ?? URL(string: "embr://")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let host = url.host?.lowercased(),
              let value = url.pathComponents.dropFirst().first,
              !value.isEmpty,
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return nil }
        switch host {
        case "watch": self = .watch(login: value.lowercased())
        case "channel": self = .channel(login: value.lowercased())
        default: return nil
        }
    }
}
