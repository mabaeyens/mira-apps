import XCTest

/// Device-only checks for the mira-core engine lifecycle (idle unload / wake).
///
/// These tests assume the app is already installed, paired and connected to a
/// server with `engine_idle_unload_minutes` set, and that the engine is
/// *sleeping* when a test starts. `scripts/test-engine-lifecycle.sh` arranges
/// that (POST /engine/unload, wait for `sleeping`) before each test and checks
/// the server state afterwards. The app's auth token is never touched here: the
/// app already holds it.
final class EngineLifecycleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Shrink the app's 15 s stream-silence watchdog to 3 s. Every wake takes
        // 9 s or more, so without the wake grace period the first-message test
        // would self-cancel every time instead of only on a slow wake.
        app.launchArguments += ["-MiraStaleSeconds", "3"]
        app.launch()
    }

    private var banner: XCUIElement { app.descendants(matching: .any)["engine-banner"].firstMatch }
    private var composer: XCUIElement { app.descendants(matching: .any)["composer"].firstMatch }
    private var sendButton: XCUIElement { app.buttons["send-button"] }

    /// Poll until `condition` holds or `timeout` seconds pass.
    private func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }

    private func bannerText() -> String {
        banner.exists ? banner.label : ""
    }

    /// A sleeping engine must show the quiet banner, never the offline one.
    func testSleepingShowsQuietBannerNotOffline() throws {
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "Composer never appeared: is the app connected?")
        // Health is polled every 10 s, so allow two cycles.
        XCTAssertTrue(wait(25) { self.bannerText().contains("Asleep") },
                      "No 'Asleep' banner. Got: '\(bannerText())'. Is the engine sleeping and the lifecycle on?")
        XCTAssertFalse(app.buttons["Start"].exists, "Manual-start (offline) banner showed for a sleeping engine")
    }

    /// Focusing the composer wakes the engine; the banner goes Asleep -> Waking -> gone.
    func testFocusingComposerWakesEngine() throws {
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(25) { self.bannerText().contains("Asleep") },
                      "Precondition failed: engine not shown as asleep. Got '\(bannerText())'")

        composer.tap()

        XCTAssertTrue(wait(15) { !self.bannerText().contains("Asleep") },
                      "Banner still says Asleep 15 s after focusing the composer")
        XCTAssertFalse(app.buttons["Start"].exists, "Manual-start banner appeared during a wake")
        // The wake takes 9-25 s; the banner must clear once the engine is up.
        XCTAssertTrue(wait(90) { !self.banner.exists },
                      "Banner never cleared after the wake. Got '\(bannerText())'")
        XCTAssertFalse(app.buttons["Start"].exists)
    }

    /// Typing then sending straight away: the server holds the request while the
    /// engine wakes. It must finish without a timeout, an error or the Start banner.
    func testFirstMessageAfterSleepCompletes() throws {
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(25) { self.bannerText().contains("Asleep") },
                      "Precondition failed: engine not shown as asleep. Got '\(bannerText())'")

        composer.tap()
        composer.typeText("Reply with the single word: ok")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        // The stop button replaces send while a turn is in flight and goes away
        // when it ends. Worst-case wake is ~260 s, typical 15-25 s.
        let stop = app.buttons["stop-button"]
        XCTAssertTrue(stop.waitForExistence(timeout: 30), "Turn never started streaming")
        XCTAssertTrue(wait(300) { !stop.exists }, "Turn never finished (still streaming after 300 s)")
        XCTAssertFalse(app.buttons["Start"].exists, "Manual-start banner appeared during the wake")
        let alert = app.alerts.firstMatch
        if alert.exists {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.lifetime = .keepAlways
            add(shot)
            let texts = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
            XCTFail("An alert appeared: title='\(alert.label)' texts=[\(texts)]")
        }
        XCTAssertFalse(app.staticTexts["Request timed out. Check your connection and try again."].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Connection lost'")).firstMatch.exists,
                       "The stale-connection watchdog cancelled the turn during the wake")
    }
}
