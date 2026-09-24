import UIKit
import Combine
import StoreKit

/// The optional tip jar: three consumables that unlock nothing. StoreKit 2 is the whole
/// implementation — no receipt or transaction leaves the device, so nothing about a tip is
/// collected by Embr.
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

    private(set) var products: [Product] = []
    private(set) var state: LoadState = .idle
    private(set) var tipCount: Int

    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?
    private static let tipCountKey = "tipJar.count"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tipCount = defaults.integer(forKey: Self.tipCountKey)
    }

    var hasTipped: Bool { tipCount > 0 }

    /// Finishes tips that complete outside a purchase call — Ask to Buy approvals, or a
    /// purchase interrupted by the app closing — so StoreKit stops redelivering them.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                guard Self.productIDs.contains(transaction.productID) else { continue }
                self?.recordTip()
            }
        }
    }

    func loadProducts() {
        guard state != .loading, state != .loaded else { return }
        state = .loading
        changes.send()
        Task { [weak self] in
            let fetched = (try? await Product.products(for: Self.productIDs)) ?? []
            guard let self else { return }
            self.products = fetched.sorted { $0.price < $1.price }
            self.state = fetched.isEmpty ? .unavailable : .loaded
            if fetched.isEmpty {
                AppLogger.shared.warn("tip jar: no products returned", category: .app)
            }
            self.changes.send()
        }
    }

    func retry() {
        guard state == .unavailable else { return }
        state = .idle
        loadProducts()
    }

    func product(id: String) -> Product? {
        products.first { $0.id == id }
    }

    func purchase(_ product: Product, in scene: UIWindowScene?) async -> Outcome {
        do {
            let result: Product.PurchaseResult
            if let scene {
                result = try await product.purchase(confirmIn: scene)
            } else {
                result = try await product.purchase()
            }
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    AppLogger.shared.warn("tip \(product.id) failed verification", category: .app)
                    return .failed(String(localized: "The App Store couldn't verify this purchase."))
                }
                await transaction.finish()
                recordTip()
                AppLogger.shared.info("tip \(product.id) completed", category: .app)
                return .thanked
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            AppLogger.shared.warn("tip \(product.id) failed: \(error)", category: .app)
            return .failed(error.localizedDescription)
        }
    }

    private func recordTip() {
        tipCount += 1
        defaults.set(tipCount, forKey: Self.tipCountKey)
        changes.send()
    }
}
