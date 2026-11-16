import AVFoundation
import EmbrCore
import MidgarCore

/// Serves AVPlayer one Twitch media playlist for Hyper Low Latency, read straight from Twitch and rewritten on the
/// device by `HyperPlaylistRewriter`, so a Hyper stream costs the worker nothing while it plays. The player asks for
/// the playlist under the `embr-hyper` scheme, which only this loader answers; the segments it lists are Twitch's own
/// https URLs, which the player loads directly.
///
/// The rewriter's state (the first URI seen for each sequence number) lives here, one loader per player item, and is
/// touched only on `queue`, the queue the resource loader calls back on; that is what makes it safe to send.
nonisolated final class HyperPlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "embr-hyper"

    let queue = DispatchQueue(label: "cc.midgarcorp.embr.hyper-playlist")
    private var rewriter = HyperPlaylistRewriter()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A player item that plays the Twitch media playlist at `playlistURL` through a new loader. The resource loader
    /// holds its delegate weakly, so the caller keeps the loader for as long as the item plays.
    static func item(playing playlistURL: URL) -> (item: AVPlayerItem, loader: HyperPlaylistLoader) {
        let loader = HyperPlaylistLoader()
        let asset = AVURLAsset(url: wrapped(playlistURL))
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return (AVPlayerItem(asset: asset), loader)
    }

    static func wrapped(_ url: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "playlist"
        components.queryItems = [URLQueryItem(name: "u", value: url.absoluteString)]
        return components.url ?? url
    }

    static func unwrapped(_ url: URL) -> URL? {
        guard url.scheme == scheme,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value,
              let upstream = URL(string: value), upstream.scheme == "https" else { return nil }
        return upstream
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url, let upstream = Self.unwrapped(url) else { return false }
        var request = URLRequest(url: upstream, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/vnd.apple.mpegurl", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode
            self.queue.async { self.answer(loadingRequest, upstream: upstream, data: data, status: status, error: error) }
        }.resume()
        return true
    }

    /// Hands the player the rewritten playlist, or the failure that makes the app's recovery reload the stream.
    private func answer(_ loadingRequest: AVAssetResourceLoadingRequest, upstream: URL, data: Data?, status: Int?, error: Error?) {
        guard !loadingRequest.isCancelled, !loadingRequest.isFinished else { return }
        guard status == 200, let data, let text = String(data: data, encoding: .utf8) else {
            MidgarLog.notice("HLS hyper playlist failed: status \(status.map(String.init) ?? "none") \(error?.localizedDescription ?? "")", category: .playback)
            loadingRequest.finishLoading(with: error ?? URLError(.badServerResponse))
            return
        }
        let body = Data(rewriter.rewrite(text, playlistURL: upstream).utf8)
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(body.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: body)
        loadingRequest.finishLoading()
    }
}
