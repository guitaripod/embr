import XCTest

/// Switches the Apple TV between light and dark while each screen stays open and keeps a screenshot of every switch,
/// so a color that misses the change shows up next to the ones that follow it. UI automation needs XCTest.
@MainActor
final class EmbrTVAppearanceTests: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
    }

    override func tearDown() async throws {
        app?.terminate()
        XCUIDevice.shared.appearance = .dark
    }

    func testBrowse() {
        launch(route: "browse", appearance: .dark)
        cycle("browse")
    }

    func testBrowseLaunchedInLight() {
        launch(route: "browse", appearance: .light)
        snap("browselight-1-light")
        XCUIDevice.shared.appearance = .dark
        pause(3)
        snap("browselight-2-dark")
    }

    func testFavorites() {
        launch(route: "favorites", appearance: .dark)
        cycle("favorites")
    }

    func testChannel() {
        launch(route: "channel", appearance: .dark)
        cycle("channel")
    }

    func testSupporter() {
        launch(route: "supporterowned", appearance: .dark)
        cycle("supporter")
    }

    func testThemeTryOn() {
        launch(route: "supporter", appearance: .dark)
        let midnight = app.buttons["Midnight"].firstMatch
        let row = ["OLED Black", "Midnight", "Dusk"].map { app.buttons[$0].firstMatch }
        for _ in 0..<12 where !row.contains(where: \.hasFocus) {
            remote.press(.down)
            pause(0.5)
        }
        for _ in 0..<5 where !midnight.hasFocus {
            remote.press(app.buttons["Dusk"].firstMatch.hasFocus ? .left : .right)
            pause(0.5)
        }
        remote.press(.select)
        pause(2)
        cycle("tryon")
    }

    func testSignIn() {
        launch(route: "signin", appearance: .dark)
        cycle("signin")
    }

    func testPlayerAndInfoPanel() {
        launch(route: "player", appearance: .dark)
        pause(6)
        cycle("player")
        remote.press(.down)
        pause(3)
        snap("player-4-info-dark")
        XCUIDevice.shared.appearance = .light
        pause(3)
        snap("player-5-info-light")
    }

    func testMultiview() {
        launch(route: "multiview", appearance: .dark)
        pause(4)
        cycle("multiview")
    }

    func testSettingsAndAppearanceSetting() {
        launch(route: "browse", appearance: .dark)
        remote.press(.up)
        pause(1)
        remote.press(.right)
        pause(2)
        remote.press(.down)
        pause(1)
        cycle("settings")
        focusRow("Appearance")
        pause(1)
        remote.press(.select)
        pause(2)
        focusRow("Light")
        remote.press(.select)
        pause(3)
        snap("settings-4-override-light-on-dark")
        focusRow("Appearance")
        remote.press(.select)
        pause(2)
        focusRow("Dark")
        remote.press(.select)
        pause(3)
        snap("settings-5-override-dark")
        focusRow("Appearance")
        remote.press(.select)
        pause(2)
        remote.press(.up)
        remote.press(.up)
        focusRow("Automatic")
        remote.press(.select)
        pause(3)
        snap("settings-6-automatic-dark")
        XCUIDevice.shared.appearance = .light
        pause(3)
        snap("settings-7-automatic-light")
    }

    private func launch(route: String, appearance: XCUIDevice.Appearance) {
        XCUIDevice.shared.appearance = appearance
        app = XCUIApplication()
        app.launchArguments += ["-embrDemo", "-tvRoute", route]
        app.launch()
        pause(8)
    }

    private func cycle(_ name: String) {
        snap("\(name)-1-dark")
        XCUIDevice.shared.appearance = .light
        pause(3)
        snap("\(name)-2-light")
        XCUIDevice.shared.appearance = .dark
        pause(3)
        snap("\(name)-3-dark")
    }

    private func focusRow(_ label: String) {
        let row = app.cells.containing(.staticText, identifier: label).firstMatch
        for _ in 0..<30 where !row.hasFocus {
            remote.press(.down)
            pause(0.4)
        }
        XCTAssertTrue(row.hasFocus, "\(label) never took focus")
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
