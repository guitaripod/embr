import XCTest

/// Drives the Apple TV app with the Siri Remote the way a person would and keeps a screenshot of every screen it
/// reaches, so the focus, the gestures and the layouts can be looked at. UI automation needs XCTest.
@MainActor
final class EmbrTVTourTests: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ProcessInfo.processInfo.environment["EMBR_UITEST_DEMO"] == "1" ? ["-embrDemo"] : []
        app.launch()
        pause(8)
    }

    func testBrowseWatchAndPlayerGestures() {
        snap("01-browse")
        remote.press(.select)
        pause(14)
        snap("02-player-chat")
        remote.press(.select)
        pause(2)
        snap("03-transport-bar")
        remote.press(.up)
        pause(1)
        snap("04-transport-items")
        remote.press(.menu)
        pause(2)
        remote.press(.down)
        pause(3)
        snap("05-info-panel")
        remote.press(.menu)
        pause(2)
        remote.press(.up)
        pause(3)
        snap("06-channel-switcher")
        remote.press(.menu)
        pause(2)
        remote.press(.menu)
        pause(3)
        snap("07-back-home")
    }

    func testLongPressMenuAndMultiview() {
        remote.press(.select, forDuration: 2.5)
        pause(2)
        snap("10-context-menu")
        remote.press(.down)
        remote.press(.down)
        pause(1)
        snap("11-context-menu-focus")
        remote.press(.menu)
        pause(2)
    }

    func testTabsSettingsSupporterAndSignIn() {
        remote.press(.up)
        pause(1)
        remote.press(.left)
        remote.press(.left)
        pause(4)
        snap("20-following-signed-out")
        remote.press(.down)
        pause(1)
        remote.press(.select)
        pause(6)
        snap("21-sign-in-code")
        remote.press(.menu)
        pause(2)
        remote.press(.up)
        pause(1)
        for _ in 0..<4 { remote.press(.right) }
        pause(3)
        snap("22-settings")
        remote.press(.down)
        remote.press(.down)
        pause(1)
        remote.press(.select)
        pause(3)
        snap("23-supporter")
        remote.press(.menu)
        pause(2)
        for _ in 0..<6 { remote.press(.down) }
        pause(1)
        snap("24-settings-scrolled")
    }

    func testSearch() {
        remote.press(.up)
        pause(1)
        remote.press(.right)
        pause(3)
        snap("30-search")
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
