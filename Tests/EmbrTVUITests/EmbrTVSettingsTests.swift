import XCTest

/// Walks the Apple TV Settings tab with the remote: every page it opens has to read well, scroll and give the remote
/// back to the list with Menu. UI automation needs XCTest.
@MainActor
final class EmbrTVSettingsTests: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-embrDemo", "-tvRoute", "browse"]
        app.launch()
        pause(8)
        remote.press(.up)
        pause(1)
        remote.press(.right)
        pause(2)
        remote.press(.down)
        pause(1)
    }

    override func tearDown() async throws {
        app?.terminate()
        XCUIDevice.shared.appearance = .dark
    }

    func testTour() {
        snap("01-top")
        for step in 1...4 {
            for _ in 0..<5 { remote.press(.down) }
            pause(1)
            snap("02-scrolled-\(step)")
        }
    }

    func testPrivacyPolicyReturnsToSettings() {
        readAndReturn("Privacy Policy", prefix: "10-privacy")
    }

    func testTermsReturnsToSettings() {
        readAndReturn("Terms of Use", prefix: "20-terms")
    }

    func testOptionsAndBlockedUsers() {
        focusRow("Chat Text Size")
        remote.press(.select)
        pause(2)
        snap("30-options")
        remote.press(.menu)
        pause(2)
        XCTAssertTrue(row("Chat Text Size").hasFocus, "Menu did not return to Settings from the options")
        focusRow("Blocked Users")
        remote.press(.select)
        pause(2)
        snap("31-blocked")
        remote.press(.menu)
        pause(2)
        XCTAssertTrue(row("Blocked Users").hasFocus, "Menu did not return to Settings from Blocked Users")
    }

    func testSupporterMoreAppsAndSignOutReturn() {
        openAndReturn("Become a Founding Supporter", prefix: "40-supporter")
        openAndReturn("More Apps from Midgar", prefix: "41-more-apps")
        openAndReturn("Signed in as emberfan", prefix: "42-sign-out")
    }

    func testLight() {
        XCUIDevice.shared.appearance = .light
        pause(3)
        snap("50-light-top")
        for _ in 0..<12 { remote.press(.down) }
        pause(1)
        snap("51-light-scrolled")
        readAndReturn("Privacy Policy", prefix: "52-light-privacy")
    }

    private func openAndReturn(_ title: String, prefix: String) {
        focusRow(title)
        remote.press(.select)
        pause(3)
        snap("\(prefix)-1-open")
        remote.press(.menu)
        pause(2)
        snap("\(prefix)-2-after-menu")
        XCTAssertTrue(row(title).hasFocus, "Menu did not return to Settings from \(title)")
    }

    private func readAndReturn(_ title: String, prefix: String) {
        focusRow(title)
        remote.press(.select)
        pause(2)
        snap("\(prefix)-1-open")
        for _ in 0..<6 { remote.press(.down) }
        pause(1)
        snap("\(prefix)-2-scrolled")
        remote.press(.menu)
        pause(2)
        snap("\(prefix)-3-after-menu")
        XCTAssertTrue(row(title).waitForExistence(timeout: 3) && row(title).hasFocus, "Menu did not return to Settings from \(title)")
        for _ in 0..<40 { remote.press(.up) }
        pause(1)
        snap("\(prefix)-4-top")
        remote.press(.left)
        pause(2)
        snap("\(prefix)-5-tab-left")
    }

    private func row(_ label: String) -> XCUIElement {
        app.cells.containing(.staticText, identifier: label).firstMatch
    }

    private func focusRow(_ label: String) {
        let target = row(label)
        for _ in 0..<40 where !target.hasFocus {
            remote.press(.down)
            pause(0.3)
        }
        for _ in 0..<40 where !target.hasFocus {
            remote.press(.up)
            pause(0.3)
        }
        XCTAssertTrue(target.hasFocus, "\(label) never took focus")
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
