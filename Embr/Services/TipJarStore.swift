import UIKit
import Combine
import MidgarCommerce
import MidgarCore

/// What the tip jar needs from the purchase engine, so tests and previews can stand in for `MidgarStore`.
protocol TipPurchasing: Sendable {
    func products() async throws -> [StoreProduct]
    @MainActor func purchase(_ productID: String, confirmIn scene: UIWindowScene?) async throws -> MidgarPurchaseResult
    func events() async -> AsyncStream<MidgarStoreEvent>
}

extension MidgarStore: TipPurchasing {
    @MainActor
    func purchase(_ productID: String, confirmIn scene: UIWindowScene?) async throws -> MidgarPurchaseResult {
        if let scene {
            return try await purchase(productID, confirmIn: scene)
        }
        return try await purchase(productID)
    }
}

/// The optional tip jar: three consumables that unlock nothing. MidgarStore buys each tip, finishes it and reports
/// it to the Midgar ledger with the Midgar ID, so the purchase record is the only thing about a tip that leaves the
/// device.
@MainActor
final class TipJarStore {
    static let shared = TipJarStore()

    static let productIDs = [
        "com.guitaripod.embr.tip.small",
        "com.guitaripod.embr.tip.medium",
        "com.guitaripod.embr.tip.large",
    ]

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
    }

    enum Outcome: Equatable {
        case thanked
        case pending
        case cancelled
        case failed(String)
    }

    let changes = PassthroughSubject<Void, Never>()

    private(set) var products: [StoreProduct] = []
    private(set) var state: LoadState = .idle
    private(set) var tipCount: Int

    private let defaults: UserDefaults
    private var purchasing: (any TipPurchasing)?
    private var eventsTask: Task<Void, Never>?
    private static let tipCountKey = "tipJar.count"

    init(purchasing: (any TipPurchasing)? = nil, defaults: UserDefaults = .standard) {
        self.purchasing = purchasing
        self.defaults = defaults
        tipCount = defaults.integer(forKey: Self.tipCountKey)
    }

    var hasTipped: Bool { tipCount > 0 }

    /// Creates the purchase engine, whose `Transaction.updates` listener finishes tips that complete outside a
    /// purchase call (Ask to Buy approvals, a purchase interrupted by the app closing), and counts those approvals.
    /// A test host or a demo capture has no engine, so its tips stay unavailable.
    func start() {
        guard eventsTask == nil else { return }
        if purchasing == nil, EmbrMidgar.reachesMidgarServices {
            purchasing = EmbrMidgar.shared.makeStore(productIDs: Self.productIDs)
        }
        guard let purchasing else { return }
        eventsTask = Task { [weak self] in
            for await event in await purchasing.events() {
                guard case .purchaseApproved(let productID) = event, Self.productIDs.contains(productID) else { continue }
                self?.recordTip()
            }
        }
    }

    func loadProducts() {
        guard state != .loading, state != .loaded else { return }
        guard let purchasing else {
            state = .unavailable
            changes.send()
            return
        }
        state = .loading
        changes.send()
        Task { [weak self] in
            let fetched = (try? await purchasing.products()) ?? []
            guard let self else { return }
            self.products = fetched.filter { Self.productIDs.contains($0.id) }.sorted { $0.price < $1.price }
            self.state = self.products.isEmpty ? .unavailable : .loaded
            if self.products.isEmpty {
                MidgarLog.notice("tip jar: no products returned", category: .tips)
            }
            self.changes.send()
        }
    }

    func retry() {
        guard state == .unavailable else { return }
        state = .idle
        loadProducts()
    }

    func product(id: String) -> StoreProduct? {
        products.first { $0.id == id }
    }

    func purchase(_ product: StoreProduct, in scene: UIWindowScene?) async -> Outcome {
        guard let purchasing else { return .failed(String(localized: "Tips are not available right now.")) }
        do {
            switch try await purchasing.purchase(product.id, confirmIn: scene) {
            case .purchased:
                recordTip()
                MidgarLog.info("tip \(product.id) completed", category: .tips)
                return .thanked
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            MidgarLog.notice("tip \(product.id) failed: \(error)", category: .tips)
            return .failed(error.localizedDescription)
        }
    }

    private func recordTip() {
        tipCount += 1
        defaults.set(tipCount, forKey: Self.tipCountKey)
        changes.send()
    }
}
