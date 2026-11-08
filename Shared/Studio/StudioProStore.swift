import Combine
import Foundation
import EmbrCore
import MidgarCommerce
import MidgarCore
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Studio Pro: what a streamer pays for, sold as a monthly or yearly subscription or once for life, and shared by the
/// iPhone, iPad and Apple TV apps through the App Store's universal purchase. Every streamer who hasn't bought it gets
/// one week of it, once per device, from the first live stream Studio sees (decision D26); nothing is charged and
/// nothing renews. Founding Supporter is a separate thank-you from viewers and unlocks none of this.
@MainActor
final class StudioProStore {
    static let shared = StudioProStore()

    nonisolated static let yearlyID = "com.guitaripod.embr.studio.yearly"
    nonisolated static let monthlyID = "com.guitaripod.embr.studio.monthly"
    nonisolated static let lifetimeID = "com.guitaripod.embr.studio.lifetime"
    nonisolated static let productIDs = [yearlyID, monthlyID, lifetimeID]
    nonisolated static let entitlement = "studio"

    enum Outcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    let changes = PassthroughSubject<Void, Never>()

    private(set) var isSubscriber: Bool
    private(set) var products: [StoreProduct] = []
    private(set) var productsUnavailable = false
    private var loadingProducts = false
    private var store: MidgarStore?
    private var eventsTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let week: StudioProWeekStore

    private static let subscriberKey = "studio.pro.isSubscriber"

    init(defaults: UserDefaults = .standard, week: StudioProWeekStore = .live()) {
        self.defaults = defaults
        self.week = week
        isSubscriber = defaults.bool(forKey: Self.subscriberKey)
    }

    /// Whether Pro is open right now: bought, or inside the free week.
    var hasPro: Bool {
        isSubscriber || weekPhase().isActive
    }

    func weekPhase(now: Date = Date()) -> StudioProWeek.Phase {
        StudioProWeek.phase(start: week.loadStart(), now: now)
    }

    /// Opens the free week the first time a streamer's own live stream reaches Studio. A buyer, the sample stream and
    /// a moderator watching someone else's channel never start one.
    func noteLiveStream(role: StudioRole, isSample: Bool, now: Date = Date()) {
        guard !isSubscriber, !isSample, role == .broadcaster, week.loadStart() == nil else { return }
        week.saveStart(now)
        MidgarLog.info("Studio Pro week started", category: .commerce)
        changes.send()
    }

    /// Hooks onto the shared purchase engine. Call once at launch.
    func start() {
        guard eventsTask == nil, EmbrMidgar.reachesMidgarServices else { return }
        let store = EmbrMidgar.shared.commerce
        self.store = store
        eventsTask = Task { [weak self] in
            await self?.refreshEntitlement()
            for await event in await store.events() {
                switch event {
                case .entitlementsChanged, .purchaseApproved:
                    await self?.refreshEntitlement()
                case .refused:
                    break
                }
            }
        }
    }

    func loadProducts() {
        guard products.isEmpty, !loadingProducts else { return }
        guard let store else {
            productsUnavailable = true
            changes.send()
            return
        }
        loadingProducts = true
        productsUnavailable = false
        changes.send()
        Task { [weak self] in
            let all = (try? await store.products()) ?? []
            guard let self else { return }
            self.loadingProducts = false
            self.products = Self.productIDs.compactMap { id in all.first { $0.id == id } }
            self.productsUnavailable = self.products.isEmpty
            if self.products.count < Self.productIDs.count {
                MidgarLog.notice("Studio Pro: \(self.products.count) of \(Self.productIDs.count) products returned", category: .commerce)
            }
            self.changes.send()
        }
    }

    var isLoadingProducts: Bool { loadingProducts }

    func product(_ id: String) -> StoreProduct? {
        products.first { $0.id == id }
    }

    /// How much the yearly plan saves against twelve months, as a whole percentage, when both prices are known.
    var yearlySavingPercent: Int? {
        guard let yearly = product(Self.yearlyID)?.price, let monthly = product(Self.monthlyID)?.price, monthly > 0 else { return nil }
        let twelve = monthly * 12
        guard twelve > yearly else { return nil }
        let saving = (twelve - yearly) / twelve * 100
        return Int(NSDecimalNumber(decimal: saving).doubleValue.rounded(.down))
    }

    #if canImport(UIKit)
    func purchase(_ productID: String, in scene: UIWindowScene?) async -> Outcome {
        guard let store else { return .failed(String(localized: "Purchases are not available right now.")) }
        do {
            let result: MidgarPurchaseResult
            #if os(iOS)
            if let scene {
                result = try await store.purchase(productID, confirmIn: scene)
            } else {
                result = try await store.purchase(productID)
            }
            #else
            result = try await store.purchase(productID)
            #endif
            switch result {
            case .purchased:
                MidgarLog.info("Studio Pro purchased: \(productID)", category: .commerce)
                await refreshEntitlement()
                setSubscriber(true)
                return .purchased
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            }
        } catch {
            MidgarLog.notice("Studio Pro purchase failed: \(error)", category: .commerce)
            return .failed(error.localizedDescription)
        }
    }
    #endif

    func restore() async -> Bool {
        guard let store else { return false }
        do {
            try await store.restore()
        } catch {
            MidgarLog.notice("Studio Pro restore failed: \(error)", category: .commerce)
        }
        await refreshEntitlement()
        return isSubscriber
    }

    private func refreshEntitlement() async {
        guard let store else { return }
        setSubscriber(await store.isEntitled(to: Self.entitlement))
    }

    private func setSubscriber(_ value: Bool) {
        guard value != isSubscriber else { return }
        isSubscriber = value
        defaults.set(value, forKey: Self.subscriberKey)
        changes.send()
    }

    #if DEBUG
    /// Opens or closes Pro for screenshots and UI tests without the App Store.
    func seedForScreenshots(subscriber: Bool) {
        isSubscriber = subscriber
        changes.send()
    }
    #endif
}

/// The calendar of Studio's free Pro week, derived from its start date alone, so a relaunch, a reinstall or a clock
/// change all agree.
enum StudioProWeek {
    static let length: TimeInterval = 7 * 86_400

    enum Phase: Equatable, Sendable {
        case notStarted
        case active(endsAt: Date)
        case over

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }
    }

    static func phase(start: Date?, now: Date) -> Phase {
        guard let start else { return .notStarted }
        let elapsed = max(0, now.timeIntervalSince(start))
        return elapsed < length ? .active(endsAt: start.addingTimeInterval(length)) : .over
    }

    /// Whole days left, counting a part day as a day, so the last day reads "1 day left" and never "0".
    static func daysLeft(until end: Date, now: Date) -> Int {
        max(1, Int((end.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

/// Where the Pro week's start lives: the keychain first, so a reinstall doesn't hand out a second week, with a defaults
/// copy for when the keychain can't answer. Never synchronizable: a week belongs to one device.
struct StudioProWeekStore: Sendable {
    private static let defaultsKey = "studio.proWeekStart"
    private static let keychainService = "com.guitaripod.embr.studio.proweek"
    private static let keychainAccount = "start"

    private let defaultsSuite: String?
    private let usesKeychain: Bool

    static func live() -> StudioProWeekStore {
        StudioProWeekStore(defaultsSuite: nil, usesKeychain: true)
    }

    static func local(suite: String) -> StudioProWeekStore {
        StudioProWeekStore(defaultsSuite: suite, usesKeychain: false)
    }

    private var defaults: UserDefaults {
        defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func loadStart() -> Date? {
        let stored = usesKeychain ? Self.keychainStart() : nil
        let copy = defaults.object(forKey: Self.defaultsKey) as? Double
        guard let seconds = stored ?? copy else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func saveStart(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.defaultsKey)
        if usesKeychain { Self.writeKeychainStart(date.timeIntervalSince1970) }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func keychainStart() -> Double? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return Double(text)
    }

    /// Adds the item once; a start already stored is never moved, so a later week can't be handed out.
    private static func writeKeychainStart(_ seconds: Double) {
        var query = baseQuery
        query[kSecValueData as String] = Data(String(seconds).utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            MidgarLog.notice("Studio Pro week start not written to the keychain: \(status)", category: .commerce)
        }
    }
}
