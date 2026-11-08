import XCTest

/// Drives Embr Studio on the Apple TV with the Siri Remote the way a streamer would, on the sample stream, and keeps a
/// screenshot of every screen it reaches so the focus, the sheets and the layouts can be looked at. UI automation
/// needs XCTest.
@MainActor
final class EmbrTVStudioTests: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func testWelcomeOpensTheSampleStream() {
        app.launchArguments += ["-tvRoute", "welcome"]
        app.launch()
        pause(4)
        snap("01-welcome")
        XCTAssertTrue(app.buttons["Try a Sample Stream"].exists || app.staticTexts["EMBR STUDIO"].exists)
        remote.press(.right)
        remote.press(.select)
        pause(6)
        snap("02-sample-stream")
        XCTAssertTrue(app.staticTexts["SAMPLE STREAM"].waitForExistence(timeout: 5))
    }

    func testAdClockStatusLineAndSettings() {
        app.launchArguments += ["-tvRoute", "sample"]
        app.launch()
        pause(6)
        snap("10-studio")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Snooze +5:00"].exists)
        remote.press(.up)
        pause(1)
        snap("11-focus-moved")
        remote.press(.select)
        pause(2)
        snap("12-after-select")
        remote.press(.menu)
        pause(1)
        app.terminate()

        app.launchArguments = ["-tvRoute", "settings"]
        app.launch()
        pause(5)
        snap("13-settings")
        for _ in 0..<6 { remote.press(.down) }
        pause(1)
        snap("14-settings-screen-section")
        for _ in 0..<8 { remote.press(.down) }
        pause(1)
        snap("15-settings-alerts")
    }

    func testMomentsAndMessageActions() {
        for moment in ["raid", "hype", "poll", "adsoon", "adrun", "offline", "actions"] {
            app.launchArguments = ["-tvRoute", "sample", "-tvMoment", moment]
            app.launch()
            pause(8)
            snap("20-moment-\(moment)")
            app.terminate()
        }
    }

    func testPaywall() {
        app.launchArguments += ["-tvRoute", "pro"]
        app.launch()
        pause(5)
        snap("30-pro")
        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 5))
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["MIDGAR_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("tv-\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
    }
}
