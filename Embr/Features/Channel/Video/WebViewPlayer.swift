import WebKit
import Combine
import UIKit
import EmbrCore

@MainActor
final class WebViewPlayer: NSObject, VideoPlaying {

    var view: UIView { webView }

    var statePublisher: AnyPublisher<VideoState, Never> { stateSubject.eraseToAnyPublisher() }
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { latencySubject.eraseToAnyPublisher() }

    private(set) var availableQualities: [StreamQuality] = []
    private(set) var currentQuality: StreamQuality?

    private let stateSubject = CurrentValueSubject<VideoState, Never>(.idle)
    private let latencySubject = CurrentValueSubject<TimeInterval?, Never>(nil)
    private let logger: AppLogger
    private let workerBaseURL: URL
    private let parentHost: String

    private let messageProxy = WeakScriptMessageHandler()

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
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
        return webView
    }()

    init(
        logger: AppLogger = .shared,
        workerBaseURL: URL = Configuration.current.workerBaseURL,
        parentHost: String = "embr.twitch.tv"
    ) {
        self.logger = logger
        self.workerBaseURL = workerBaseURL
        self.parentHost = parentHost
        super.init()
    }

    func load(_ resolution: PlaybackResolution) {
        availableQualities = resolution.qualities
        currentQuality = nil
        stateSubject.send(.loading)

        if let channel = channelLogin(from: resolution.masterPlaylistURL) {
            loadEmbed(channel: channel)
        } else {
            loadDirect(resolution.masterPlaylistURL)
        }
    }

    func play() {
        evaluate("if (window.embrPlayer) { window.embrPlayer.play(); }")
    }

    func pause() {
        evaluate("if (window.embrPlayer) { window.embrPlayer.pause(); }")
    }

    func setQuality(_ quality: StreamQuality) {
        currentQuality = isAuto(quality) ? nil : quality
        let group = isAuto(quality) ? "auto" : quality.name
        evaluate("if (window.embrPlayer) { window.embrPlayer.setQuality('\(group)'); }")
    }

    func setMuted(_ muted: Bool) {
        evaluate("if (window.embrPlayer) { window.embrPlayer.setMuted(\(muted ? "true" : "false")); }")
    }

    func teardown() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "embrPlayer")
        webView.loadHTMLString("", baseURL: nil)
        stateSubject.send(.idle)
        logger.info("WebView teardown", category: .playback)
    }

    private func loadEmbed(channel: String) {
        var components = URLComponents(url: workerBaseURL.appendingPathComponent("embed"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "parent", value: parentHost)
        ]
        guard let url = components?.url else {
            loadPlayerTwitchFallback(channel: channel)
            return
        }
        webView.load(URLRequest(url: url))
        logger.info("WebView embed channel=\(channel) url=\(url.absoluteString)", category: .playback)
    }

    private func loadPlayerTwitchFallback(channel: String) {
        var components = URLComponents(string: "https://player.twitch.tv/")
        components?.queryItems = [
            URLQueryItem(name: "channel", value: channel),
            URLQueryItem(name: "parent", value: parentHost),
            URLQueryItem(name: "autoplay", value: "true")
        ]
        guard let url = components?.url else {
            stateSubject.send(.error("Unable to build embed URL"))
            return
        }
        webView.load(URLRequest(url: url))
        logger.info("WebView player.twitch.tv fallback channel=\(channel)", category: .playback)
    }

    private func loadDirect(_ url: URL) {
        let html = directHLSHTML(url: url)
        webView.loadHTMLString(html, baseURL: workerBaseURL)
        logger.info("WebView direct HLS url=\(url.absoluteString)", category: .playback)
    }

    private func directHLSHTML(url: URL) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;background:#000;height:100%}video{width:100%;height:100%;object-fit:contain}</style></head>
        <body><video id="v" autoplay playsinline src="\(url.absoluteString)"></video>
        <script>
        var v=document.getElementById('v');
        function post(s){try{window.webkit.messageHandlers.embrPlayer.postMessage(s);}catch(e){}}
        window.embrPlayer={play:function(){v.play();},pause:function(){v.pause();},setMuted:function(m){v.muted=m;},setQuality:function(){}};
        v.addEventListener('playing',function(){post('playing');});
        v.addEventListener('pause',function(){post('paused');});
        v.addEventListener('waiting',function(){post('buffering');});
        v.addEventListener('ended',function(){post('ended');});
        v.addEventListener('error',function(){post('error');});
        </script></body></html>
        """
    }

    private func channelLogin(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard let index = components.firstIndex(where: { $0 == "playback" }), index + 1 < components.count else {
            return nil
        }
        let candidate = components[index + 1]
        return candidate == "vod" ? nil : candidate
    }

    private func isAuto(_ quality: StreamQuality) -> Bool {
        quality.name.caseInsensitiveCompare("auto") == .orderedSame
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
        case "buffering": stateSubject.send(.buffering)
        case "ended": stateSubject.send(.ended)
        case "error": stateSubject.send(.error("Embed playback error"))
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
}
