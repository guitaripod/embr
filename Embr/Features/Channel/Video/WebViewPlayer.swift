import WebKit
import Combine
import UIKit

/// The sole video player: it loads Twitch's official embedded player (served by the
/// Worker `/embed` route, which runs `embed.twitch.tv` for live/VOD and the official
/// clip embed for clips). The embed plays through Twitch's own player — including any
/// advertising Twitch serves — and posts playback state back over a message handler.
@MainActor
final class WebViewPlayer: NSObject, VideoPlaying {

    var view: UIView { webView }

    var statePublisher: AnyPublisher<VideoState, Never> { stateSubject.eraseToAnyPublisher() }

    private let stateSubject = CurrentValueSubject<VideoState, Never>(.idle)
    private let logger: AppLogger
    private let workerBaseURL: URL
    private var muted = false

    private let messageProxy = WeakScriptMessageHandler()

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        messageProxy.target = self
        controller.add(messageProxy, name: "embrPlayer")
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        return webView
    }()

    init(
        logger: AppLogger = .shared,
        workerBaseURL: URL = Configuration.current.workerBaseURL
    ) {
        self.logger = logger
        self.workerBaseURL = workerBaseURL
        super.init()
    }

    func load(_ source: VideoSource) {
        stateSubject.send(.loading)
        let item: URLQueryItem
        switch source {
        case .live(let login): item = URLQueryItem(name: "channel", value: login)
        case .vod(let id): item = URLQueryItem(name: "video", value: id)
        case .clip(let id): item = URLQueryItem(name: "clip", value: id)
        }
        loadEmbed(item)
    }

    func play() {
        evaluate("if (window.embrPlayer) { window.embrPlayer.play(); }")
    }

    func pause() {
        evaluate("if (window.embrPlayer) { window.embrPlayer.pause(); }")
    }

    func setMuted(_ muted: Bool) {
        self.muted = muted
        evaluate("if (window.embrPlayer) { window.embrPlayer.setMuted(\(muted ? "true" : "false")); }")
    }

    func teardown() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "embrPlayer")
        webView.loadHTMLString("", baseURL: nil)
        stateSubject.send(.idle)
        logger.info("WebView teardown", category: .playback)
    }

    private func loadEmbed(_ target: URLQueryItem) {
        var components = URLComponents(url: workerBaseURL.appendingPathComponent("embed"), resolvingAgainstBaseURL: false)
        components?.queryItems = [target, URLQueryItem(name: "muted", value: muted ? "true" : "false")]
        guard let url = components?.url else {
            stateSubject.send(.error("Unable to build embed URL"))
            return
        }
        webView.load(URLRequest(url: url))
        logger.info("WebView embed \(target.name)=\(target.value ?? "") url=\(url.absoluteString)", category: .playback)
    }

    private func evaluate(_ js: String) {
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

extension WebViewPlayer: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "embrPlayer", let body = message.body as? String else { return }
        switch body {
        case "playing": stateSubject.send(.playing)
        case "paused": stateSubject.send(.paused)
        case "ended": stateSubject.send(.ended)
        case "offline": stateSubject.send(.error("This channel isn't live right now."))
        case "ready": break
        default: break
        }
    }
}

@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

extension WebViewPlayer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        stateSubject.send(.error(error.localizedDescription))
        logger.error("WebView navigation failed: \(error.localizedDescription)", category: .playback)
    }

    /// Clear the app's loading overlay once the embed page has loaded, then hand off to
    /// Twitch's own player UI. We can't wait for the embed's JS "playing" event — iOS
    /// blocks unattended autoplay-with-sound, so it may never fire until the user taps —
    /// and the page-finished signal always fires. Real offline/ended events still arrive
    /// over the message handler afterwards and override this.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if stateSubject.value == .loading {
            stateSubject.send(.playing)
        }
    }
}
