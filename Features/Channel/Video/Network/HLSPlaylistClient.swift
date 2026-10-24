import Foundation

/// Fetches the text of an HLS playlist.
nonisolated struct HLSPlaylistClient: Sendable {
    func playlist(at url: URL) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
