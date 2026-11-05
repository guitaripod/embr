import UIKit
import Combine
import StoreKit
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Embr's one non-consumable: Founding Supporter. It unlocks only looks (the accent colors, the alternate app icons on
/// iPhone and the badge other viewers see beside the supporter's name in chat) and never anything about watching.
/// MidgarStore buys it with the Midgar ID like the tips; this type keeps the entitlement on screen and ties the
/// purchase to the signed-in Twitch account so the badge can show.
@MainActor
final class SupporterStore {
    static let shared = SupporterStore()

    nonisolated static let productID = SupporterAPI.productID
    nonisolated static let entitlement = "supporter"

    enum Outcome: Equatable {
        case purchased
        case pending
        case cancelled
        case failed(String)
    }

    enum BadgeState: Equatable {
        /// Not a supporter, or nothing has been tried yet.
        case none
        /// A supporter who is not signed in with Twitch: the badge needs a Twitch account to sit beside.
        case needsSignIn
        case claiming
        case shown(login: String)
        case failed
    }

    let changes = PassthroughSubject<Void, Never>()

    private(set) var isSupporter: Bool
    private(set) var product: StoreProduct?
    /// The App Store answered without Founding Supporter, or could not be reached; the screen offers to ask again.
    private(set) var productUnavailable = false
    private(set) var badge: BadgeState = .none

    private let defaults: UserDefaults
    private let settings: SettingsStore
    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    private var store: MidgarStore?
    private var eventsTask: Task<Void, Never>?
    private var claimTask: Task<Void, Never>?
    private var loadingProduct = false
    private var cancellables = Set<AnyCancellable>()

    private static let supporterKey = "supporter.isSupporter"
    private static let claimedKey = "supporter.claimedTwitchUserID"

    init(
        defaults: UserDefaults = .standard,
        settings: SettingsStore = .shared,
        transport: HTTPTransport = MidgarGatewayTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.defaults = defaults
        self.settings = settings
        self.transport = transport
        self.endpoints = endpoints
        isSupporter = defaults.bool(forKey: Self.supporterKey)
        applyAccent()
    }

    /// The accent the app shows: the supporter's pick, violet for everyone else.
    var accent: SupporterAccent {
        guard isSupporter, let raw = settings.current.accent, let accent = SupporterAccent(rawValue: raw) else { return .violet }
        return accent
    }

    func setAccent(_ accent: SupporterAccent) {
        guard isSupporter else { return }
        settings.update { $0.accent = accent.rawValue }
        applyAccent()
        changes.send()
    }

    /// Hooks onto the shared purchase engine and the Twitch session. Call once at launch.
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
        AuthService.shared.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.claimIfNeeded() }
            .store(in: &cancellables)
        Task { await SupporterDirectory.shared.refreshIfStale() }
    }

    func loadProduct() {
        guard product == nil, !loadingProduct else { return }
        guard let store else {
            productUnavailable = true
            changes.send()
            return
        }
        loadingProduct = true
        productUnavailable = false
        changes.send()
        Task { [weak self] in
            let products = (try? await store.products()) ?? []
            guard let self else { return }
            self.loadingProduct = false
            self.product = products.first { $0.id == Self.productID }
            self.productUnavailable = self.product == nil
            if self.product == nil {
                MidgarLog.notice("supporter: product not returned by the App Store", category: .tips)
            }
            self.changes.send()
        }
    }

    func purchase(in scene: UIWindowScene?) async -> Outcome {
        guard let store else { return .failed(String(localized: "Purchases are not available right now.")) }
        do {
            switch try await receipt(from: store, in: scene) {
            case .purchased(let receipt):
                MidgarLog.info("supporter purchased", category: .tips)
                setSupporter(true)
                claim(signedTransaction: receipt.signedTransaction)
                return .purchased
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            }
        } catch {
            MidgarLog.notice("supporter purchase failed: \(error)", category: .tips)
            return .failed(error.localizedDescription)
        }
    }

    /// Asks the App Store for the purchases this Apple Account already made, for a supporter on a new device.
    func restore() async -> Bool {
        guard let store else { return false }
        do {
            try await store.restore()
        } catch {
            MidgarLog.notice("supporter restore failed: \(error)", category: .tips)
        }
        await refreshEntitlement()
        return isSupporter
    }

    private func receipt(from store: MidgarStore, in scene: UIWindowScene?) async throws -> MidgarReceiptResult {
        #if os(iOS)
        if let scene {
            return try await store.purchaseReceipt(Self.productID, confirmIn: scene)
        }
        #endif
        return try await store.purchaseReceipt(Self.productID)
    }

    private func refreshEntitlement() async {
        guard let store else { return }
        let entitled = await store.isEntitled(to: Self.entitlement)
        setSupporter(entitled)
        claimIfNeeded()
    }

    private func setSupporter(_ value: Bool) {
        guard value != isSupporter else { return }
        isSupporter = value
        defaults.set(value, forKey: Self.supporterKey)
        if !value {
            badge = .none
            resetIcon()
        }
        applyAccent()
        changes.send()
    }

    /// A refunded supporter gets Embr's own icon back; the accent falls back to violet by itself.
    private func resetIcon() {
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != nil else { return }
        UIApplication.shared.setAlternateIconName(nil)
        #endif
    }

    private func applyAccent() {
        SupporterAccent.activate(accent)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach { $0.tintColor = accent.color }
        }
    }

    /// Ties the purchase to the Twitch account that is signed in, once per account, so the badge follows a sign-in on
    /// another account and a supporter who signs in later still gets it.
    private func claimIfNeeded() {
        guard isSupporter else { return }
        claim(signedTransaction: nil)
    }

    private func claim(signedTransaction: String?) {
        claimTask?.cancel()
        claimTask = Task { [weak self] in
            guard let self else { return }
            guard let user = await AuthService.shared.currentUser() else {
                self.updateBadge(.needsSignIn)
                return
            }
            if self.defaults.string(forKey: Self.claimedKey) == user.id, signedTransaction == nil {
                SupporterDirectory.shared.insert(user.id)
                self.updateBadge(.shown(login: user.login))
                return
            }
            var jws = signedTransaction
            if jws == nil {
                jws = await Self.currentTransactionJWS()
            }
            guard let jws else {
                MidgarLog.notice("supporter claim: no verified transaction on this device", category: .tips)
                self.updateBadge(.failed)
                return
            }
            self.updateBadge(.claiming)
            await self.send(jws: jws, user: user)
        }
    }

    private func send(jws: String, user: AuthenticatedUser) async {
        do {
            let token = try await AuthService.shared.validAccessToken()
            let request = endpoints.claimSupporter(SupporterAPI.ClaimRequest(signedTransaction: jws, twitchAccessToken: token))
            let response = try await transport.send(request)
            guard response.isSuccess else {
                MidgarLog.notice("supporter claim: status \(response.status)", category: .tips)
                updateBadge(.failed)
                return
            }
            let claimed = try WorkerEndpoints.decodeSupporterClaim(response.body)
            defaults.set(claimed.twitchUserID, forKey: Self.claimedKey)
            SupporterDirectory.shared.insert(claimed.twitchUserID)
            updateBadge(.shown(login: user.login))
            MidgarLog.info("supporter badge claimed for \(user.login)", category: .tips)
        } catch {
            guard !Task.isCancelled else { return }
            MidgarLog.notice("supporter claim failed: \(error)", category: .tips)
            updateBadge(.failed)
        }
    }

    private func updateBadge(_ state: BadgeState) {
        guard badge != state else { return }
        badge = state
        changes.send()
    }

    /// The signed transaction StoreKit holds for the supporter purchase on this device: what the worker verifies with
    /// Apple's certificates before it shows a badge.
    private static func currentTransactionJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == productID, transaction.revocationDate == nil else {
                continue
            }
            return result.jwsRepresentation
        }
        return nil
    }

    /// Retries the badge after a failure, from the supporter screen.
    func retryBadge() {
        defaults.removeObject(forKey: Self.claimedKey)
        claimIfNeeded()
    }

    #if DEBUG
    /// Poses the supporter screens for screenshots without a purchase.
    func seedForScreenshots(supporter: Bool) {
        isSupporter = supporter
        product = StoreProduct(id: Self.productID, displayName: "Founding Supporter", description: "", displayPrice: "$9.99", price: 9.99)
        applyAccent()
        changes.send()
    }
    #endif
}
