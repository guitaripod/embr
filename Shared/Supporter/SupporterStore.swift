import UIKit
import Combine
import StoreKit
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Embr's one non-consumable: Founding Supporter. It unlocks only looks and never anything about watching: for the
/// supporter, the themes, accent colors, chat fonts and alternate iPhone icons; for everyone in Embr, the supporter's
/// flame badge in the color they pick, their name in that color or glowing, and their founding number. MidgarStore
/// buys it with the Midgar ID like the tips; this type keeps the entitlement and the looks on screen, ties the
/// purchase to the signed-in Twitch account and sends the badge's look to the worker.
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

    private var styleTask: Task<Void, Never>?

    private static let supporterKey = "supporter.isSupporter"
    private static let claimedKey = "supporter.claimedTwitchUserID"
    private static let numberKey = "supporter.number"
    private static let badgeColorKey = "supporter.badgeColor"
    private static let nameStyleKey = "supporter.nameStyle"
    private static let stylePendingKey = "supporter.stylePending"
    private static let tryOnKey = "supporter.pendingTryOn"

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
        applyLook()
    }

    /// The accent the app shows: the supporter's pick, violet for everyone else.
    var accent: SupporterAccent {
        isSupporter ? savedAccent : .violet
    }

    /// The theme the app shows: the supporter's pick, standard for everyone else.
    var theme: SupporterTheme {
        isSupporter ? settings.current.supporterTheme : .standard
    }

    /// The supporter's founding number, once the worker has given one.
    var number: Int? {
        if let saved = defaults.object(forKey: Self.numberKey) as? Int { return saved }
        guard let claimed = defaults.string(forKey: Self.claimedKey) else { return nil }
        return SupporterDirectory.shared.profile(for: claimed)?.number
    }

    /// How many Founding Supporters there are, for the purchase screen.
    var supporterCount: Int {
        SupporterDirectory.shared.count
    }

    /// The looks as saved, whether or not they show: a refunded supporter keeps them for a purchase later.
    var choice: SupporterLookChoice {
        SupporterLookChoice(
            theme: settings.current.supporterTheme,
            accent: savedAccent,
            chatFont: settings.current.supporterChatFont,
            badgeColor: defaults.string(forKey: Self.badgeColorKey).flatMap(SupporterAccent.init(rawValue:)) ?? .violet,
            nameStyle: defaults.string(forKey: Self.nameStyleKey).flatMap(SupporterAPI.NameStyle.init(rawValue:)) ?? .twitch,
            icon: Self.currentIcon
        )
    }

    private var savedAccent: SupporterAccent {
        settings.current.accent.flatMap(SupporterAccent.init(rawValue:)) ?? .violet
    }

    func setAccent(_ accent: SupporterAccent) {
        guard isSupporter else { return }
        settings.update { $0.accent = accent.rawValue }
        applyLook()
        changes.send()
    }

    func setTheme(_ theme: SupporterTheme) {
        guard isSupporter else { return }
        settings.update { $0.palette = theme.rawValue }
        applyLook()
        changes.send()
    }

    func setChatFont(_ font: SupporterChatFont) {
        guard isSupporter else { return }
        settings.update { $0.chatFont = font.rawValue }
        changes.send()
    }

    /// The badge's color and how the name looks to everyone in Embr: saved here, shown in this device's chat at once
    /// and sent to the worker for everyone else, again later if the worker cannot be reached now.
    func setBadgeStyle(color: SupporterAccent, nameStyle: SupporterAPI.NameStyle) {
        guard isSupporter else { return }
        defaults.set(color.rawValue, forKey: Self.badgeColorKey)
        defaults.set(nameStyle.rawValue, forKey: Self.nameStyleKey)
        defaults.set(true, forKey: Self.stylePendingKey)
        showOwnProfile()
        changes.send()
        syncStyle()
    }

    /// Makes every look someone tried on before buying their own, right after the purchase.
    private func apply(_ choice: SupporterLookChoice) {
        guard isSupporter else { return }
        settings.update {
            $0.palette = choice.theme.rawValue
            $0.accent = choice.accent.rawValue
            $0.chatFont = choice.chatFont.rawValue
        }
        applyLook()
        setBadgeStyle(color: choice.badgeColor, nameStyle: choice.nameStyle)
        Self.setIcon(choice.icon)
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
        Task { [weak self] in
            await SupporterDirectory.shared.refreshIfStale()
            self?.changes.send()
        }
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
                MidgarLog.notice("supporter: product not returned by the App Store", category: .supporter)
            }
            self.changes.send()
        }
    }

    /// Buys Founding Supporter and keeps the looks tried on before: at once, or when an Ask to Buy request is approved
    /// later, even after a relaunch.
    func purchase(in scene: UIWindowScene?, tryingOn tried: SupporterLookChoice?) async -> Outcome {
        guard let store else { return .failed(String(localized: "Purchases are not available right now.")) }
        rememberTryOn(tried)
        do {
            switch try await receipt(from: store, in: scene) {
            case .purchased(let receipt):
                MidgarLog.info("supporter purchased", category: .supporter)
                setSupporter(true)
                claim(signedTransaction: receipt.signedTransaction)
                return .purchased
            case .pending:
                return .pending
            case .cancelled:
                rememberTryOn(nil)
                return .cancelled
            }
        } catch {
            rememberTryOn(nil)
            MidgarLog.notice("supporter purchase failed: \(error)", category: .supporter)
            return .failed(error.localizedDescription)
        }
    }

    private func rememberTryOn(_ choice: SupporterLookChoice?) {
        guard let choice else {
            defaults.removeObject(forKey: Self.tryOnKey)
            return
        }
        defaults.set([choice.theme.rawValue, choice.accent.rawValue, choice.chatFont.rawValue, choice.badgeColor.rawValue, choice.nameStyle.rawValue, choice.icon ?? ""], forKey: Self.tryOnKey)
    }

    /// The looks someone tried on before a purchase that is not finished yet.
    private var rememberedTryOn: SupporterLookChoice? {
        guard let saved = defaults.stringArray(forKey: Self.tryOnKey), saved.count == 6 else { return nil }
        return SupporterLookChoice(
            theme: SupporterTheme(rawValue: saved[0]) ?? .standard,
            accent: SupporterAccent(rawValue: saved[1]) ?? .violet,
            chatFont: SupporterChatFont(rawValue: saved[2]) ?? .standard,
            badgeColor: SupporterAccent(rawValue: saved[3]) ?? .violet,
            nameStyle: SupporterAPI.NameStyle(rawValue: saved[4]) ?? .twitch,
            icon: saved[5].isEmpty ? nil : saved[5]
        )
    }

    /// Asks the App Store for the purchases this Apple Account already made, for a supporter on a new device.
    func restore() async -> Bool {
        guard let store else { return false }
        do {
            try await store.restore()
        } catch {
            MidgarLog.notice("supporter restore failed: \(error)", category: .supporter)
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
        if value {
            if let tried = rememberedTryOn {
                rememberTryOn(nil)
                applyLook()
                apply(tried)
            }
        } else {
            badge = .none
            Self.setIcon(nil)
            SupporterDirectory.shared.unpin()
            defaults.removeObject(forKey: Self.claimedKey)
            defaults.removeObject(forKey: Self.numberKey)
        }
        applyLook()
        settings.republish()
        changes.send()
    }

    /// The alternate iPhone and iPad icon in use; nil is Embr's own, and always on Apple TV.
    static var currentIcon: String? {
        #if os(iOS)
        UIApplication.shared.alternateIconName
        #else
        nil
        #endif
    }

    /// Switches the iPhone and iPad icon; a refunded supporter gets Embr's own back.
    static func setIcon(_ name: String?) {
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                MidgarLog.notice("supporter: icon change failed: \(error)", category: .supporter)
            }
        }
        #endif
    }

    /// Shows this device's looks: the accent as every window's tint, the theme carried down every window, and the
    /// chat font chat layout reads.
    private func applyLook() {
        SupporterLook.setUnlocked(isSupporter)
        SupporterAccent.activate(accent)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.tintColor = accent.color
                window.traitOverrides[SupporterThemeTrait.self] = theme
            }
        }
    }

    /// Puts the supporter's own look into this device's directory, so their next chat message shows it.
    private func showOwnProfile() {
        guard let claimed = defaults.string(forKey: Self.claimedKey) else { return }
        let look = choice
        SupporterDirectory.shared.pin(claimed, profile: SupporterAPI.Profile(number: number, color: look.badgeColor.rawValue, nameStyle: look.nameStyle.rawValue))
    }

    /// The worker no longer ties the purchase to this Twitch account, because another device claimed it for another
    /// one: the badge leaves this device until the person chooses Try Again, which claims it back.
    private func lostClaim() {
        defaults.removeObject(forKey: Self.claimedKey)
        SupporterDirectory.shared.unpin()
        updateBadge(.failed)
    }

    /// Sends a changed badge look to the worker once the purchase is tied to the signed-in Twitch account.
    private func syncStyle() {
        guard isSupporter, defaults.bool(forKey: Self.stylePendingKey) else { return }
        styleTask?.cancel()
        styleTask = Task { [weak self] in
            guard let self else { return }
            guard let user = await AuthService.shared.currentUser(), self.defaults.string(forKey: Self.claimedKey) == user.id else { return }
            let look = self.choice
            do {
                let token = try await AuthService.shared.validAccessToken()
                let request = self.endpoints.updateSupporterStyle(SupporterAPI.StyleRequest(twitchAccessToken: token, color: look.badgeColor.rawValue, nameStyle: look.nameStyle))
                let response = try await self.transport.send(request)
                if response.status == 403 {
                    MidgarLog.notice("supporter style: the badge is no longer tied to \(user.login)", category: .supporter)
                    self.lostClaim()
                    return
                }
                guard response.isSuccess else {
                    MidgarLog.notice("supporter style: status \(response.status)", category: .supporter)
                    return
                }
                let profile = try WorkerEndpoints.decodeSupporterProfile(response.body)
                guard self.choice.badgeColor == look.badgeColor, self.choice.nameStyle == look.nameStyle else { return }
                self.defaults.set(false, forKey: Self.stylePendingKey)
                SupporterDirectory.shared.pin(user.id, profile: profile)
                MidgarLog.info("supporter style sent: \(look.badgeColor.rawValue), \(look.nameStyle.rawValue)", category: .supporter)
            } catch {
                guard !Task.isCancelled else { return }
                MidgarLog.notice("supporter style failed: \(error)", category: .supporter)
            }
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
                self.showOwnProfile()
                self.updateBadge(.shown(login: user.login))
                self.syncStyle()
                return
            }
            var jws = signedTransaction
            if jws == nil {
                jws = await Self.currentTransactionJWS()
            }
            guard let jws else {
                MidgarLog.notice("supporter claim: no verified transaction on this device", category: .supporter)
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
                MidgarLog.notice("supporter claim: status \(response.status)", category: .supporter)
                updateBadge(.failed)
                return
            }
            let claimed = try WorkerEndpoints.decodeSupporterClaim(response.body)
            defaults.set(claimed.twitchUserID, forKey: Self.claimedKey)
            if let number = claimed.number {
                defaults.set(number, forKey: Self.numberKey)
            } else {
                defaults.removeObject(forKey: Self.numberKey)
            }
            if defaults.bool(forKey: Self.stylePendingKey) {
                showOwnProfile()
                syncStyle()
            } else {
                adoptStyle(claimed.profile)
                SupporterDirectory.shared.pin(claimed.twitchUserID, profile: claimed.profile)
            }
            updateBadge(.shown(login: user.login))
            MidgarLog.info("supporter badge claimed for \(user.login), number \(claimed.number.map(String.init) ?? "none")", category: .supporter)
        } catch {
            guard !Task.isCancelled else { return }
            MidgarLog.notice("supporter claim failed: \(error)", category: .supporter)
            updateBadge(.failed)
        }
    }

    /// Takes the badge look the worker kept, for a supporter on a new device who has not picked one here.
    private func adoptStyle(_ profile: SupporterAPI.Profile) {
        defaults.set(profile.color, forKey: Self.badgeColorKey)
        defaults.set(profile.style.rawValue, forKey: Self.nameStyleKey)
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
        product = StoreProduct(id: Self.productID, displayName: "Founding Member", description: "", displayPrice: "$9.99", price: 9.99)
        if supporter {
            defaults.set(12, forKey: Self.numberKey)
            defaults.set(SupporterAccent.ember.rawValue, forKey: Self.badgeColorKey)
            defaults.set(SupporterAPI.NameStyle.glow.rawValue, forKey: Self.nameStyleKey)
        }
        applyLook()
        changes.send()
    }
    #endif
}
