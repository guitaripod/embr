import Foundation
import MidgarCommerce
import MidgarCore
import MidgarPortal

/// The composition root of everything Embr shares with the other Midgar apps: the Midgar ID, the gateway
/// clients built on it, the anonymous signals client and the purchase engine. One instance lives for the
/// whole process, so there is one `Transaction.updates` listener and one identity.
final class EmbrMidgar: Sendable {
    /// The registry slug: the `X-App-ID` of every gateway call and the `app` of the ledger entries this app honours.
    static let appID = "embr"

    /// The bundle id the registry holds for the App Store record.
    static let bundleID = "com.guitaripod.embr"

    /// The log file name, kept from the retired per-app logger so the `ios-device-logs` workflow still finds it.
    static let logFileName = "embr.log"

    static let shared = EmbrMidgar()

    /// The Midgar ID client. Minted on first launch, attached on every later one, shared through the keychain group.
    let identity: MidgarIdentity

    /// The gateway client that carries the Midgar ID's bearer token, for the ledger and the portal's "Your Midgar".
    let account: MidgarHTTPClient

    /// The gateway client for Embr's own worker. It carries `X-App-ID` and nothing that identifies the person: the
    /// worker reads no credential and the Midgar ID has no business in a Twitch playback or report request.
    let worker: MidgarHTTPClient

    private init() {
        let configuration = MidgarHTTPConfiguration(appID: Self.appID)
        identity = MidgarIdentity(httpConfiguration: configuration, bundleID: Self.bundleID)
        account = MidgarHTTPClient(configuration: identity.authorizing(configuration))
        worker = MidgarHTTPClient(configuration: configuration)
    }

    /// The portal configuration of Settings: the authorized client, so "Your Midgar" shows what the person owns in
    /// the other apps and a cross-sell skips an app they already use.
    var portalConfig: MidgarPortal.MidgarConfig {
        MidgarPortal.MidgarConfig(placement: "settings", account: account)
    }

    /// Opens the log file. Call first thing at launch so nothing before the rest of the setup is lost.
    static func configureLogging() {
        MidgarLog.configure(fileName: logFileName)
    }

    /// Configures anonymous signals for the portal and starts the Midgar ID in the background, so the app holds one
    /// before the first tip needs it. Call once at launch. A test host or a demo capture talks to no Midgar service.
    func start() {
        guard Self.reachesMidgarServices else {
            MidgarLog.info("Midgar services not started: test host or demo world", category: .account)
            return
        }
        MidgarSignals.configure(configuration: MidgarHTTPConfiguration(appID: Self.appID))
        let identity = identity
        Task {
            do {
                _ = try await identity.midgarId
                MidgarLog.info("Midgar ID ready", category: .account)
            } catch {
                MidgarLog.info("Midgar ID not available yet: \(error)", category: .account)
            }
        }
    }

    /// The purchase engine for the tips. Creating the store starts its `Transaction.updates` listener, so create it once.
    func makeStore(productIDs: [String]) -> MidgarStore {
        MidgarStore(
            configuration: MidgarStoreConfiguration(
                appID: Self.appID,
                productIDs: productIDs,
                entitlementsByProduct: [:],
                mode: .purchases
            ),
            identity: identity,
            http: account
        )
    }

    /// False inside an XCTest or Swift Testing host and in a DEBUG demo capture, which must not mint identities or
    /// send signals to the production services.
    static var reachesMidgarServices: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if DemoWorld.isActive { return false }
        #endif
        return true
    }
}
