import XCTest

/// Demo mode: the app with no server at all.
///
/// Starts from the first-run screen, so it needs a simulator on which the app
/// has no saved connection (a fresh install has none) and it passes no
/// `-MiraTestServer`. Nothing has to be listening anywhere: every request in
/// the demo is answered inside the app by `DemoURLProtocol`.
///
/// `-MiraDemoDiagnostics 1` makes the canned reply end with the protocol's own
/// counters, `served` (requests answered from memory) and `blocked` (requests
/// to any other host, refused). `blocked=0` means the app did not even try to
/// reach another host while the demo was on.
///
///   xcodebuild test -project OllamaSearch.xcodeproj -scheme OllamaSearch \
///     -destination 'platform=iOS Simulator,id=<udid>' \
///     -only-testing:MiraUITests/DemoModeUITests
final class DemoModeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(StubServer.isSimulator, "simulator only: a paired phone starts connected, not on the first-run screen")
        app = XCUIApplication()
        app.launchArguments += ["-MiraDemoDiagnostics", "1", "-MiraNoAutoWake", "1"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var tryDemoButton: XCUIElement { element("try-demo-button") }
    private var exitDemoButton: XCUIElement { element("exit-demo-button") }
    private var demoLabel: XCUIElement { element("demo-label") }
    private var sidebarButton: XCUIElement { element("sidebar-button") }
    private var composer: XCUIElement { app.descendants(matching: .any)["composer"].firstMatch }
    private var sendButton: XCUIElement { app.buttons["send-button"] }

    private func row(titled title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "conversation-row")
            .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// A static text containing `needle`, anywhere in the tree.
    private func text(_ needle: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", needle)).firstMatch
    }

    private func enterDemo() throws {
        guard tryDemoButton.waitForExistence(timeout: 30) else {
            try XCTSkipIf(sidebarButton.exists, "this simulator already has a connection; run on one without")
            XCTFail("the first-run screen never offered the demo")
            return
        }
        XCTAssertTrue(app.buttons["Add connection"].exists, "this is not the first-run screen")
        _ = ScreenProbe.sample(app, tag: "demo-first-run", since: Date(), attachTo: self)
        tryDemoButton.tap()
        XCTAssertTrue(demoLabel.waitForExistence(timeout: 10), "no Demo label after entering the demo")
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 10), "the demo never reached the chat screen")
    }

    private func send(_ message: String) {
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "composer never appeared")
        composer.tap()
        composer.typeText(message)
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()
    }

    // ── Tests ────────────────────────────────────────────────────────────────

    /// First-run screen → demo → the sample list → a conversation with its
    /// thinking → a sent message and its streamed reply → Exit demo.
    func testDemoWalkthroughFromFirstRun() throws {
        try enterDemo()

        // The sample conversations, with the Demo label still over the sidebar.
        sidebarButton.tap()
        for title in ["A weekend in Lisbon", "Why is the sky blue?", "Debounce a search field in SwiftUI"] {
            XCTAssertTrue(row(titled: title).waitForExistence(timeout: 15), "no sample conversation titled \(title)")
        }
        XCTAssertTrue(demoLabel.exists, "no Demo label over the conversation list")
        XCTAssertTrue(exitDemoButton.exists, "no Exit demo action over the conversation list")
        _ = ScreenProbe.sample(app, tag: "demo-sidebar", since: Date(), attachTo: self)

        // Opening one shows its messages, and its thinking section.
        row(titled: "Why is the sky blue?").tap()
        Thread.sleep(forTimeInterval: 0.6)   // the sidebar slides away
        XCTAssertTrue(text("Short answer please").waitForExistence(timeout: 10), "the question is not on screen")
        XCTAssertTrue(text("scatter the short blue wavelengths").waitForExistence(timeout: 10), "the reply is not on screen")
        let thought = app.staticTexts["Thought"]
        XCTAssertTrue(thought.waitForExistence(timeout: 10), "no thinking section on the reply that has one")
        if !text("Rayleigh scattering").waitForExistence(timeout: 3) {
            thought.tap()   // collapsed: open it
        }
        XCTAssertTrue(text("Rayleigh scattering").waitForExistence(timeout: 5), "the thinking text is not shown")
        _ = ScreenProbe.sample(app, tag: "demo-thinking", since: Date(), attachTo: self)

        // A second one, to see that opening is not a one-off.
        sidebarButton.tap()
        XCTAssertTrue(row(titled: "A weekend in Lisbon").waitForExistence(timeout: 15))
        row(titled: "A weekend in Lisbon").tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(text("Lisboa Card").waitForExistence(timeout: 10), "the second conversation did not open")

        // A new chat, and a message sent from it.
        sidebarButton.tap()
        XCTAssertTrue(app.buttons["New Chat"].waitForExistence(timeout: 10))
        app.buttons["New Chat"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        send("Hello from the demo test")
        let start = Date()
        var samples: [ScreenSample] = []
        while Date().timeIntervalSince(start) < 60 {
            let s = ScreenProbe.sample(app, tag: "demo-send", since: start, attachTo: self)
            samples.append(s)
            // The counters are the last words of the reply.
            if s.content.contains("blocked=") { break }
        }
        Thread.sleep(forTimeInterval: 1)   // the last token, then `done`
        let final = ScreenProbe.sample(app, tag: "demo-send-final", since: start, attachTo: self).content
        XCTAssertTrue(final.contains("blocked="), "the canned reply never finished")
        XCTAssertTrue(text("This is a demo").exists, "the reply does not say it is a demo")
        XCTAssertTrue(text("askmira.es").exists, "the reply does not say where to get Mira")
        XCTAssertTrue(text("Pair iPhone").exists, "the reply does not say how to pair")

        // It arrived in pieces: some look at the screen caught it part-way.
        let partial = samples.filter { $0.content.contains("This is a demo") && !$0.content.contains("demo diagnostics") }
        let streamingStatus = samples.filter { !$0.status.isEmpty }
        print("PROBE summary demo-send samples=\(samples.count) partial=\(partial.count) withStatus=\(streamingStatus.count)")
        XCTAssertFalse(partial.isEmpty && streamingStatus.isEmpty,
                       "the reply was never seen streaming: no partial text and no status line in \(samples.count) samples")

        // Nothing tried to leave the demo host.
        let counters = final.range(of: #"served=(\d+) blocked=(\d+)"#, options: .regularExpression).map { String(final[$0]) } ?? ""
        print("PROBE demo counters \(counters)")
        XCTAssertTrue(counters.hasSuffix("blocked=0"), "a request to another host was attempted in the demo: \(counters)")
        XCTAssertFalse(counters.hasPrefix("served=0 "), "no request was answered by the demo: \(counters)")

        // The new conversation is in the list, under the name of its first message.
        sidebarButton.tap()
        XCTAssertTrue(row(titled: "Hello from the demo test").waitForExistence(timeout: 15), "the new conversation is not in the list")

        // Exit goes back to the first-run screen.
        exitDemoButton.tap()
        XCTAssertTrue(tryDemoButton.waitForExistence(timeout: 10), "Exit demo did not return to the first-run screen")
        XCTAssertTrue(app.buttons["Add connection"].exists)
        XCTAssertFalse(demoLabel.exists, "the Demo label outlived the demo")
        XCTAssertFalse(row(titled: "Why is the sky blue?").exists, "a sample conversation outlived the demo")
    }

    /// Quitting inside the demo leaves nothing that makes the next launch think
    /// a connection exists, and a second visit starts from the samples again.
    func testDemoLeavesNothingBehind() throws {
        try enterDemo()
        send("Remember me")
        XCTAssertTrue(text("blocked=").waitForExistence(timeout: 60), "the canned reply never finished")
        // Give a write that should not happen the time to happen.
        Thread.sleep(forTimeInterval: 2)

        app.terminate()
        app.launch()
        XCTAssertTrue(tryDemoButton.waitForExistence(timeout: 30), "after quitting in the demo the app did not start on the first-run screen")
        XCTAssertFalse(demoLabel.exists)

        tryDemoButton.tap()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 10))
        sidebarButton.tap()
        XCTAssertTrue(row(titled: "Why is the sky blue?").waitForExistence(timeout: 15))
        XCTAssertFalse(row(titled: "Remember me").exists, "a conversation from the earlier demo came back")
    }
}
