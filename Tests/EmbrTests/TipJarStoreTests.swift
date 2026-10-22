import Foundation
import MidgarCommerce
import Testing
import UIKit

@testable import Embr

private final class FakeTipPurchasing: TipPurchasing, @unchecked Sendable {
    var catalog: [StoreProduct] = []
    var result: Result<MidgarPurchaseResult, Error> = .success(.purchased)
    private(set) var purchased: [String] = []
    private let stream: AsyncStream<MidgarStoreEvent>
    let continuation: AsyncStream<MidgarStoreEvent>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func products() async throws -> [StoreProduct] { catalog }

    @MainActor
    func purchase(_ productID: String, confirmIn scene: UIWindowScene?) async throws -> MidgarPurchaseResult {
        purchased.append(productID)
        return try result.get()
    }

    func events() async -> AsyncStream<MidgarStoreEvent> { stream }
}

private func product(_ id: String, price: Decimal) -> StoreProduct {
    StoreProduct(
        id: id,
        displayName: id,
        description: "",
        displayPrice: "$\(price)",
        price: price,
        isFamilyShareable: false,
        currencyCode: "USD",
        priceLocale: Locale(identifier: "en_US")
    )
}

@MainActor
struct TipJarStoreTests {
    private func makeStore(_ fake: FakeTipPurchasing) -> (TipJarStore, UserDefaults) {
        let suite = "embr.tipjar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (TipJarStore(purchasing: fake, defaults: defaults), defaults)
    }

    private func settle(_ store: TipJarStore, until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func loadsOnlyTheTipsSortedByPrice() async {
        let fake = FakeTipPurchasing()
        fake.catalog = [
            product("com.guitaripod.embr.tip.large", price: 9.99),
            product("something.else", price: 0.99),
            product("com.guitaripod.embr.tip.small", price: 1.99),
            product("com.guitaripod.embr.tip.medium", price: 4.99),
        ]
        let (store, _) = makeStore(fake)

        store.loadProducts()
        await settle(store) { store.state == .loaded }

        #expect(store.state == .loaded)
        #expect(store.products.map(\.id) == TipJarStore.productIDs)
    }

    @Test func noProductsMeansUnavailableAndRetryReloads() async {
        let fake = FakeTipPurchasing()
        let (store, _) = makeStore(fake)
        store.loadProducts()
        await settle(store) { store.state == .unavailable }
        #expect(store.state == .unavailable)

        fake.catalog = [product("com.guitaripod.embr.tip.small", price: 1.99)]
        store.retry()
        await settle(store) { store.state == .loaded }
        #expect(store.state == .loaded)
    }

    @Test func withoutAnEngineTheTipsStayUnavailable() {
        let store = TipJarStore(purchasing: nil, defaults: UserDefaults(suiteName: "embr.tipjar.\(UUID().uuidString)")!)
        store.loadProducts()
        #expect(store.state == .unavailable)
    }

    @Test func aPurchasedTipIsCountedOnce() async throws {
        let fake = FakeTipPurchasing()
        fake.catalog = [product("com.guitaripod.embr.tip.small", price: 1.99)]
        let (store, defaults) = makeStore(fake)
        store.loadProducts()
        await settle(store) { store.state == .loaded }
        let tip = try #require(store.product(id: "com.guitaripod.embr.tip.small"))

        let outcome = await store.purchase(tip, in: nil)

        #expect(outcome == .thanked)
        #expect(store.tipCount == 1)
        #expect(store.hasTipped)
        #expect(defaults.integer(forKey: "tipJar.count") == 1)
        #expect(fake.purchased == ["com.guitaripod.embr.tip.small"])
    }

    @Test func pendingCancelledAndFailedTipsAreNotCounted() async throws {
        let fake = FakeTipPurchasing()
        fake.catalog = [product("com.guitaripod.embr.tip.small", price: 1.99)]
        let (store, _) = makeStore(fake)
        store.loadProducts()
        await settle(store) { store.state == .loaded }
        let tip = try #require(store.product(id: "com.guitaripod.embr.tip.small"))

        fake.result = .success(.pending)
        #expect(await store.purchase(tip, in: nil) == .pending)
        fake.result = .success(.cancelled)
        #expect(await store.purchase(tip, in: nil) == .cancelled)
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        fake.result = .failure(Boom())
        #expect(await store.purchase(tip, in: nil) == .failed("boom"))
        #expect(store.tipCount == 0)
    }

    @Test func anApprovedTipArrivingLaterIsCounted() async {
        let fake = FakeTipPurchasing()
        let (store, _) = makeStore(fake)
        store.start()

        fake.continuation.yield(.purchaseApproved(productID: "com.guitaripod.embr.tip.medium"))
        fake.continuation.yield(.purchaseApproved(productID: "not.a.tip"))
        fake.continuation.yield(.entitlementsChanged)
        await settle(store) { store.tipCount == 1 }
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.tipCount == 1)
    }
}
