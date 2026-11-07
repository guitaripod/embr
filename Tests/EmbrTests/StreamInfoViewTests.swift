import EmbrCore
import Testing
import UIKit

@testable import Embr

@MainActor
@Suite struct StreamInfoViewTests {
    private func category(in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.configuration?.title == "Just Chatting" { return button }
        return view.subviews.lazy.compactMap { category(in: $0) }.first
    }

    @Test func theCategoryPillKeepsItsTitleOnOneLineAndComesBackWhole() throws {
        let info = StreamInfoView()
        info.configure(stream: LiveStream(
            id: "s", userID: "1", userLogin: "streamer", userName: "Streamer", gameID: "509658",
            gameName: "Just Chatting", title: "Hanging out", viewerCount: 44_700,
            startedAt: Date(timeIntervalSinceNow: -8_640), language: "en", thumbnailURLTemplate: ""
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 420, height: 912))
        info.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(info)
        let width = info.widthAnchor.constraint(equalToConstant: 420)
        NSLayoutConstraint.activate([info.topAnchor.constraint(equalTo: window.topAnchor), info.leadingAnchor.constraint(equalTo: window.leadingAnchor), width])
        window.layoutIfNeeded()
        let pill = try #require(category(in: info))
        let whole = pill.frame.size

        #expect(pill.configuration?.titleLineBreakMode == .byTruncatingTail)

        width.constant = 200
        window.layoutIfNeeded()
        width.constant = 420
        window.layoutIfNeeded()

        #expect(pill.frame.size == whole)
    }
}
