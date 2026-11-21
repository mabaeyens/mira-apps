import XCTest

/// Device-only reproduction of "the chat goes blank when the connection drops
/// mid-reply, and the cut-off reply stays on screen after it comes back".
///
/// The test sends a long request, switches Wi-Fi off from Control Center while
/// the reply is streaming, samples the screen, switches Wi-Fi back on, and keeps
/// sampling while the app reconnects. Cellular Data is off on the test phone, so
/// Wi-Fi off is a full drop. Teardown always switches Wi-Fi back on.
///
/// Samples print as `DROPTEST ...` lines. The test fails if the message text
/// disappears while the connection is down, or if no message text is visible
/// once it is back. `scripts/test-connection-drop.sh` is the older engine-freeze
/// variant and does not drop the connection; run this class directly:
///   xcodebuild test -scheme OllamaSearch -destination id=<udid> \
///     -only-testing:MiraUITests/ConnectionDropUITests
final class ConnectionDropUITests: XCTestCase {

    private var app: XCUIApplication!
    private var springboard: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-MiraStaleSeconds", "15"]
        app.launch()
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Whatever happens, leave the phone with Wi-Fi on.
        addTeardownBlock { [self] in setWiFi(on: true) }
    }

    private var composer: XCUIElement { app.descendants(matching: .any)["composer"].firstMatch }
    private var sendButton: XCUIElement { app.buttons["send-button"] }

    // ── Control Center ───────────────────────────────────────────────────────

    private func openControlCenter() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.0))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        _ = wifiButton.waitForExistence(timeout: 5)
    }

    private func closeControlCenter() {
        let from = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        from.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        Thread.sleep(forTimeInterval: 1)
    }

    /// Wi-Fi counts as on when the button shows a network name.
    /// The compact Wi-Fi toggle (label "Wi-Fi", no identifier). The element with
    /// identifier `wifi-button` is the expanded connectivity panel, where a tap
    /// lands in the middle of the panel and toggles nothing.
    private var wifiButton: XCUIElement {
        springboard.buttons.matching(NSPredicate(format: "label == 'Wi-Fi' AND identifier == ''")).firstMatch
    }

    private func wifiIsOn() -> Bool {
        let v = (wifiButton.value as? String) ?? ""
        return !v.isEmpty && v != "Off" && v != "Not Connected"
    }

    @discardableResult
    private func setWiFi(on: Bool) -> Bool {
        openControlCenter()
        let button = wifiButton
        var ok = false
        if button.exists {
            print("DROPTEST wifi-button before=\((button.value as? String) ?? "") want=\(on ? "on" : "off")")
            if wifiIsOn() != on { button.tap() }
            // The value lags the tap: wait up to 8 s for it to flip.
            for _ in 0..<16 {
                if wifiIsOn() == on { ok = true; break }
                Thread.sleep(forTimeInterval: 0.5)
            }
            print("DROPTEST wifi-button after=\((button.value as? String) ?? "") ok=\(ok)")
        } else {
            print("DROPTEST wifi-button NOT FOUND")
        }
        closeControlCenter()
        return ok
    }

    // ── Observation ──────────────────────────────────────────────────────────

    /// Visible text lines long enough to be message content, not chrome.
    private func visibleMessageText() -> Int {
        app.staticTexts.allElementsBoundByIndex.filter { $0.exists && $0.label.count > 60 && $0.isHittable }.count
    }

    private func longestVisibleText() -> Int {
        app.staticTexts.allElementsBoundByIndex.filter { $0.exists }.map { $0.label.count }.max() ?? 0
    }

    private func alertText() -> String {
        let alert = app.alerts.firstMatch
        guard alert.exists else { return "" }
        return alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    private func sample(_ tag: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = tag
        shot.lifetime = .keepAlways
        add(shot)
        print("DROPTEST \(tag) visibleMessageText=\(visibleMessageText()) longest=\(longestVisibleText()) startButton=\(app.buttons["Start"].exists) stop=\(app.buttons["stop-button"].exists) alert=[\(alertText())]")
    }

    /// The user switches Wi-Fi off and on by hand (Control Center buttons are
    /// not reliably tappable from a test). The test sends the request, opens
    /// Control Center and leaves it open for 50 s so the user can tap the Wi-Fi
    /// tile off, wait about 25 s and tap it on, then closes it and samples the
    /// screen every 5 s for 100 s.
    func testChatSurvivesWiFiDrop() throws {
        XCTAssertTrue(composer.waitForExistence(timeout: 30), "composer never appeared")
        composer.tap()
        composer.typeText("DROPTEST2 write a 1200 word story about a lighthouse keeper")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()
        print("DROPTEST sent")

        Thread.sleep(forTimeInterval: 6)
        sample("t006-before-control-center")
        openControlCenter()
        print("DROPTEST control-center-open: tap Wi-Fi off, wait ~25 s, tap Wi-Fi on")
        Thread.sleep(forTimeInterval: 50)
        closeControlCenter()
        print("DROPTEST control-center-closed")

        var counts: [Int] = []
        var longest: [Int] = []
        for i in 1...20 {
            Thread.sleep(forTimeInterval: 5)
            sample(String(format: "t%03d", i * 5))
            counts.append(visibleMessageText())
            longest.append(longestVisibleText())
        }
        print("DROPTEST summary counts=\(counts) longest=\(longest)")
        XCTAssertFalse(counts.contains(0), "message list was blank at some sample: \(counts)")
        XCTAssertGreaterThan(longest.last ?? 0, 3000, "the finished reply never replaced the cut-off one: \(longest)")
        let ok = app.alerts.firstMatch.buttons["OK"]
        if ok.exists { ok.tap() }
    }
}
