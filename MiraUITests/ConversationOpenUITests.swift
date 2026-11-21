import XCTest

/// "Opening a conversation never shows a blank screen."
///
/// Opens several stored conversations from the sidebar, one after another, and
/// samples the screen as fast as it can for the first seconds after each tap.
/// Every sample must show message text, the loading indicator, the error state
/// or the empty state, both in a screenshot and in the accessibility tree (see
/// `ScreenSample`).
///
/// Runs on a device against the server the phone is already paired with, or in
/// the simulator against `scripts/mira-stub-server.py` (`scripts/test-chat-states.sh`
/// starts it). Read-only either way: it sends no message, and `-MiraNoAutoWake`
/// stops the app waking the engine when a conversation is opened.
///
///   xcodebuild test -project OllamaSearch.xcodeproj -scheme OllamaSearch \
///     -destination id=<udid> -only-testing:MiraUITests/ConversationOpenUITests \
///     -allowProvisioningUpdates
///
/// Samples print as `PROBE ...` lines.
final class ConversationOpenUITests: XCTestCase {

    private var app: XCUIApplication!

    /// How many conversations to open, and for how long to watch each.
    private let conversationsToOpen = 7
    private let watchSeconds: TimeInterval = 7
    /// The sidebar slides away over 0.25 s and covers the chat while it does.
    /// Samples before this are recorded but not judged.
    private let settleSeconds: TimeInterval = 0.6

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-MiraNoAutoWake", "1"]
        // In the simulator there is no paired server: talk to the stub. On a
        // device, use the connection the phone already has.
        if let stub = StubServer.urlIfSimulator {
            try XCTSkipUnless(StubServer.isUp(), "start scripts/mira-stub-server.py first (scripts/test-chat-states.sh does)")
            app.launchArguments += ["-MiraTestServer", stub]
        }
        app.launch()
    }

    private var sidebarButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sidebar-button").firstMatch
    }

    private var rows: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "conversation-row")
    }

    func testOpeningStoredConversationsNeverShowsABlankScreen() throws {
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 45), "the app never reached the chat screen")

        var samples: [(conversation: Int, sample: ScreenSample)] = []
        var opened = 0
        // Twice round: the first pass opens each conversation cold (nothing
        // cached), the second opens it with a saved copy to paint first.
        for pass in 0..<2 {
            for index in 0..<conversationsToOpen {
                sidebarButton.tap()
                guard rows.firstMatch.waitForExistence(timeout: 20) else {
                    XCTFail("no conversation rows in the sidebar")
                    break
                }
                // The list refreshes when the sidebar opens; let it settle.
                Thread.sleep(forTimeInterval: 1.0)
                let row = rows.element(boundBy: index)
                guard row.exists, row.isHittable else {
                    print("PROBE conv=\(index) not on screen")
                    // Close the sidebar again by tapping the scrim on the right edge.
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
                    break
                }
                row.tap()
                let start = Date()
                opened += 1
                while Date().timeIntervalSince(start) < watchSeconds {
                    let s = ScreenProbe.sample(app, tag: "pass\(pass)-conv\(index)", since: start, attachTo: self)
                    samples.append((opened, s))
                }
            }
        }

        XCTAssertGreaterThanOrEqual(opened, 4, "fewer than two stored conversations could be opened twice")

        let judged = samples.filter { $0.sample.t >= settleSeconds }
        let notDrawn = judged.filter { !$0.sample.drawsSomething }
        let notInTree = judged.filter { !$0.sample.treeShowsSomething }
        print("PROBE summary opened=\(opened) samples=\(samples.count) judged=\(judged.count) notDrawn=\(notDrawn.count) notInTree=\(notInTree.count)")
        XCTAssertTrue(notDrawn.isEmpty, "the message area drew nothing at: " +
            notDrawn.map { String(format: "%@ t=%.2f", $0.sample.tag, $0.sample.t) }.joined(separator: ", "))
        XCTAssertTrue(notInTree.isEmpty, "no message text, loading indicator or error at: " +
            notInTree.map { String(format: "%@ t=%.2f", $0.sample.tag, $0.sample.t) }.joined(separator: ", "))
        // The first judged look at each conversation must come within about two
        // seconds of the tap. Later than that means the main thread was stalled
        // and the screen was frozen, whatever it was showing.
        for n in 1...max(opened, 1) {
            if let first = judged.first(where: { $0.conversation == n }) {
                XCTAssertLessThan(first.sample.t, 2.5, "\(first.sample.tag): the first sample came late, the app was not responding")
            }
        }
    }
}
