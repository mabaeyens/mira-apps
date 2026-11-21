import XCTest

/// Takes the App Store screenshots from the demo (no server, no personal chats,
/// no model name). Not a regression test: it writes PNGs to a folder.
///
/// Run on a fresh simulator install, with the status bar pinned beforehand:
///   xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged \
///     --batteryLevel 100 --cellularBars 4 --wifiBars 3
///   SHOTS_DIR=/tmp/claude_shots xcodebuild test ... -only-testing:MiraUITests/StoreScreenshotsUITests
///
/// On an iPad the PNGs are written in the screen's native portrait orientation, so a
/// landscape shot comes out turned 90 degrees: fix with `sips -r 270 file.png`.
///
/// The folder is `/tmp/mira-store-shots` unless `MIRA_SHOTS_DIR` is set in the
/// test runner's environment (xcodebuild: `TEST_RUNNER_MIRA_SHOTS_DIR=...`).
final class StoreScreenshotsUITests: XCTestCase {

    private var app: XCUIApplication!
    private var dir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(StubServer.isSimulator, "simulator only")
        let path = ProcessInfo.processInfo.environment["MIRA_SHOTS_DIR"] ?? "/tmp/mira-store-shots"
        dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        app = XCUIApplication()
        app.launchArguments += ["-MiraNoAutoWake", "1"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func row(titled title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "conversation-row")
            .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Opens the conversation list on the phone; on an iPad in landscape it is
    /// already on screen.
    private func openSidebar() {
        let button = element("sidebar-button")
        if button.exists && button.isHittable { button.tap() }
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1.0)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func testTakeScreenshots() throws {
        let tryDemo = element("try-demo-button")
        XCTAssertTrue(tryDemo.waitForExistence(timeout: 30))
        shot("01-first-run")
        tryDemo.tap()
        XCTAssertTrue(element("sidebar-button").waitForExistence(timeout: 15) || row(titled: "A weekend in Lisbon").waitForExistence(timeout: 15))
        shot("02-demo-welcome")

        openSidebar()
        XCTAssertTrue(row(titled: "A weekend in Lisbon").waitForExistence(timeout: 15))
        shot("03-conversation-list")

        row(titled: "Why is the sky blue?").tap()
        Thread.sleep(forTimeInterval: 1.0)
        let thought = app.staticTexts["Thought"]
        if thought.waitForExistence(timeout: 10),
           !app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Rayleigh scattering")).firstMatch.exists {
            thought.tap()
        }
        shot("04-thinking")

        openSidebar()
        XCTAssertTrue(row(titled: "A weekend in Lisbon").waitForExistence(timeout: 15))
        row(titled: "A weekend in Lisbon").tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("05-lisbon")

        openSidebar()
        XCTAssertTrue(row(titled: "Debounce a search field in SwiftUI").waitForExistence(timeout: 15))
        row(titled: "Debounce a search field in SwiftUI").tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("06-code")

        openSidebar()
        XCTAssertTrue(app.buttons["New Chat"].waitForExistence(timeout: 10))
        app.buttons["New Chat"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let composer = app.descendants(matching: .any)["composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        composer.tap()
        composer.typeText("What can you do?")
        app.buttons["send-button"].tap()
        Thread.sleep(forTimeInterval: 2.0)
        shot("07-streaming")
        Thread.sleep(forTimeInterval: 6.0)
        shot("08-reply")
    }
}
