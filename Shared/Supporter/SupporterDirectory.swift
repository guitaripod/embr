import Foundation
import os
import EmbrCore
import MidgarCore

/// The Twitch user ids of Embr's Founding Supporters, read from the worker so chat can draw the supporter badge
/// beside their names for every Embr viewer. The last list is kept on the device, so the badges show before the
/// first refresh of a launch.
final class SupporterDirectory: Sendable {
    static let shared = SupporterDirectory()

    private let ids: OSAllocatedUnfairLock<Set<String>>
    private let lastRefresh = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    private static let cacheKey = "supporters.directory.v1"
    private static let refreshInterval: TimeInterval = 30 * 60

    init(
        transport: HTTPTransport = MidgarGatewayTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.transport = transport
        self.endpoints = endpoints
        let cached = UserDefaults.standard.stringArray(forKey: Self.cacheKey) ?? []
        ids = OSAllocatedUnfairLock(initialState: Set(cached))
    }

    func contains(_ userID: String) -> Bool {
        guard !userID.isEmpty else { return false }
        return ids.withLock { $0.contains(userID) }
    }

    /// Shows the person's own badge at once after a claim, before the next refresh brings it back from the worker.
    func insert(_ userID: String) {
        ids.withLock { _ = $0.insert(userID) }
    }

    /// Reads the list again unless it was read in the last half hour.
    func refreshIfStale(now: Date = Date()) async {
        let due = lastRefresh.withLock { last in
            guard let last, now.timeIntervalSince(last) < Self.refreshInterval else { return true }
            return false
        }
        guard due else { return }
        await refresh(now: now)
    }

    private func refresh(now: Date) async {
        do {
            let response = try await transport.send(endpoints.supporters())
            guard response.isSuccess else {
                MidgarLog.notice("supporter directory: status \(response.status)", category: .tips)
                return
            }
            let directory = try WorkerEndpoints.decodeSupporterDirectory(response.body)
            ids.withLock { $0 = Set(directory.supporters) }
            lastRefresh.withLock { $0 = now }
            UserDefaults.standard.set(directory.supporters, forKey: Self.cacheKey)
            MidgarLog.info("supporter directory: \(directory.supporters.count) supporters", category: .tips)
        } catch {
            MidgarLog.notice("supporter directory refresh failed: \(error)", category: .tips)
        }
    }

    /// The badge drawn beside a supporter's name: Embr's flame, bundled so it never waits on the network.
    static let badge: Badge = {
        var urls: [EmoteScale: URL] = [:]
        let files: [(EmoteScale, String)] = [(.x1, "supporter-badge-18"), (.x2, "supporter-badge-36"), (.x4, "supporter-badge-72")]
        for (scale, name) in files {
            if let url = Bundle.main.url(forResource: name, withExtension: "png") {
                urls[scale] = url
            }
        }
        return Badge(
            id: "1",
            setID: "embr-supporter",
            version: "1",
            title: String(localized: "Embr Founding Supporter"),
            provider: .embr,
            images: EmoteImageSet(urlsByScale: urls)
        )
    }()
}
