import Foundation

public struct Page<Element: Sendable & Equatable>: Sendable, Equatable {
    public let items: [Element]
    public let cursor: String?

    public init(items: [Element], cursor: String? = nil) {
        self.items = items
        self.cursor = cursor
    }

    public var hasMore: Bool { cursor != nil }

    public func mapItems<T>(_ transform: (Element) -> T) -> Page<T> where T: Sendable & Equatable {
        Page<T>(items: items.map(transform), cursor: cursor)
    }
}
