import XCTest

/// "The chat screen always shows something, and says what is going on", for the
/// states that need a server to misbehave.
///
/// Simulator only, against `scripts/mira-stub-server.py`, which can go silent in
/// the middle of a reply and still save the turn the way mira-core does. That
/// makes the dropped-connection path testable without switching Wi-Fi off,
/// which a device test cannot do (the runner reaches the phone over the network).
/// Run with `scripts/test-chat-states.sh`.
///
/// Every test samples the screen continuously (`ScreenProbe`) and fails on any
/// sample where the message area is blank. Samples print as `PROBE ...` lines.
final class ChatStateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(StubServer.isSimulator, "simulator only: these tests drive a stub server on the Mac's loopback")
        try XCTSkipUnless(StubServer.isUp(), "start scripts/mira-stub-server.py first (scripts/test-chat-states.sh does)")
        StubServer.control("/_stub/reset")
        addTeardownBlock { StubServer.control("/_stub/set", ["backend_ready": true]) }
    }

    /// `staleSeconds` shrinks the app's stream-silence watchdog (15 s normally).
    private func launch(staleSeconds: Int? = nil) {
        app = XCUIApplication()
        app.launchArguments += ["-MiraTestServer", StubServer.url, "-MiraNoAutoWake", "1"]
        if let staleSeconds { app.launchArguments += ["-MiraStaleSeconds", "\(staleSeconds)"] }
        app.launch()
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 45), "the app never reached the chat screen")
    }

    private var composer: XCUIElement { app.descendants(matching: .any)["composer"].firstMatch }
    private var sendButton: XCUIElement { app.buttons["send-button"] }
    private var sidebarButton: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sidebar-button").firstMatch
    }

    private func row(titled title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "conversation-row")
            .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func open(conversation title: String) {
        sidebarButton.tap()
        let target = row(titled: title)
        XCTAssertTrue(target.waitForExistence(timeout: 20), "no conversation titled \(title) in the sidebar")
        target.tap()
        Thread.sleep(forTimeInterval: 0.6)   // the sidebar slides away
    }

    private func send(_ text: String) {
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "composer never appeared")
        composer.tap()
        composer.typeText(text)
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        sendButton.tap()
    }

    /// Samples as fast as the probe allows for `seconds`.
    private func watch(_ tag: String, seconds: TimeInterval, since start: Date = Date()) -> [ScreenSample] {
        var samples: [ScreenSample] = []
        let begin = Date()
        while Date().timeIntervalSince(begin) < seconds {
            samples.append(ScreenProbe.sample(app, tag: tag, since: start, attachTo: self))
        }
        return samples
    }

    private func assertNeverBlank(_ samples: [ScreenSample], file: StaticString = #filePath, line: UInt = #line) {
        let blank = samples.filter(\.isBlank)
        print("PROBE summary \(samples.first?.tag ?? "") samples=\(samples.count) blank=\(blank.count)")
        XCTAssertTrue(blank.isEmpty, "the message area was blank at: " +
            blank.map { String(format: "%@ t=%.2f (ink %.4f, texts %d)", $0.tag, $0.t, $0.ink, $0.texts) }.joined(separator: ", "),
            file: file, line: line)
    }

    /// The distinct status lines seen, in order, with the changing seconds removed.
    private func statuses(in samples: [ScreenSample]) -> [String] {
        var seen: [String] = []
        for s in samples where !s.status.isEmpty {
            let key = s.status.replacingOccurrences(of: #"\d+(:\d+)? ?s?"#, with: "#", options: .regularExpression)
            if seen.last != key { seen.append(key) }
        }
        return seen
    }

    private func assertOrder(_ needles: [String], in seen: [String], file: StaticString = #filePath, line: UInt = #line) {
        var from = 0
        for needle in needles {
            guard let at = seen[from...].firstIndex(where: { $0.contains(needle) }) else {
                XCTFail("status line never read \"\(needle)\" (in order). Seen: \(seen)", file: file, line: line)
                return
            }
            from = at + 1
        }
    }

    // ── Tests ────────────────────────────────────────────────────────────────

    /// The first message of a new conversation: the welcome screen is replaced
    /// by the chat while the reply streams.
    func testFirstSendShowsTheReplyThroughout() {
        launch()
        send("first question")
        let start = Date()
        let samples = watch("first-send", seconds: 8, since: start)
        assertNeverBlank(samples)
        XCTAssertTrue(samples.last?.content.contains("STUB-REPLY-END") ?? false, "the end of the reply is not on screen")
        assertOrder(["Receiving"], in: statuses(in: samples))
    }

    /// The reply goes silent mid-stream. The screen must say so, keep the cut-off
    /// text up, wait for the server to finish, and put the finished reply up.
    func testDroppedReplyIsRestoredAndEveryStateIsShown() {
        launch(staleSeconds: 4)
        send("STUBDROP new conversation")
        let start = Date()
        let samples = watch("drop-new", seconds: 30, since: start)
        assertNeverBlank(samples)
        let seen = statuses(in: samples)
        print("PROBE statuses \(seen)")
        assertOrder(["Receiving", "No data", "Connection lost", "Reply restored"], in: seen)
        XCTAssertTrue(samples.last?.content.contains("STUB-REPLY-END for: STUBDROP new conversation") ?? false,
                      "the finished reply never replaced the cut-off one")
        let calls = StubServer.mutations()
        XCTAssertFalse(calls.contains { $0.hasPrefix("POST /cancel") }, "a dropped connection must not cancel the turn: \(calls)")
        XCTAssertFalse(calls.contains { $0.hasPrefix("DELETE") }, "nothing may be deleted: \(calls)")
    }

    /// The same drop in the second turn of an existing conversation, where the
    /// previous turn's reply must not be mistaken for the finished one.
    func testDroppedReplyInAnExistingConversationIsRestored() {
        launch(staleSeconds: 4)
        open(conversation: "Short chat")
        send("STUBDROP later turn")
        let start = Date()
        let samples = watch("drop-existing", seconds: 30, since: start)
        assertNeverBlank(samples)
        let seen = statuses(in: samples)
        print("PROBE statuses \(seen)")
        assertOrder(["Connection lost", "Reply restored"], in: seen)
        XCTAssertTrue(samples.last?.content.contains("STUB-REPLY-END for: STUBDROP later turn") ?? false,
                      "the finished reply never replaced the cut-off one")
        XCTAssertFalse(StubServer.mutations().contains { $0.hasPrefix("POST /cancel") }, "a dropped connection must not cancel the turn")
    }

    /// A banner above the list appears and goes away while a conversation is open.
    func testBannerComingAndGoingDoesNotBlankTheList() {
        launch()
        open(conversation: "Long history")
        var samples = watch("banner-before", seconds: 2)
        StubServer.control("/_stub/set", ["backend_ready": false])
        samples += watch("banner-shown", seconds: 14)     // health is polled every 10 s
        XCTAssertTrue(app.staticTexts["Model loading…"].exists, "the banner never appeared, so this test proved nothing")
        StubServer.control("/_stub/set", ["backend_ready": true])
        samples += watch("banner-gone", seconds: 8)       // every 3 s while not ready
        XCTAssertFalse(app.staticTexts["Model loading…"].exists, "the banner never went away")
        assertNeverBlank(samples)
    }

    /// Leaving a conversation while its first turn is still running must not
    /// delete it or cancel the turn, and the reply must be there afterwards.
    func testLeavingARunningTurnNeverDeletesOrCancelsIt() {
        launch()
        send("STUBSLOW keep going")
        let start = Date()
        var samples = watch("leave-running", seconds: 3, since: start)
        open(conversation: "Short chat")
        samples += watch("leave-other", seconds: 3, since: start)
        // The stub saves the turn 20 s after it started.
        while Date().timeIntervalSince(start) < 24 { Thread.sleep(forTimeInterval: 0.5) }
        let calls = StubServer.mutations()
        XCTAssertFalse(calls.contains { $0.hasPrefix("DELETE") }, "the conversation was deleted while its turn ran: \(calls)")
        XCTAssertFalse(calls.contains { $0.hasPrefix("POST /cancel") }, "the turn was cancelled by leaving: \(calls)")
        open(conversation: "Stub: STUBSLOW")
        samples += watch("leave-back", seconds: 4, since: start)
        assertNeverBlank(samples)
        XCTAssertTrue(samples.last?.content.contains("STUB-REPLY-END for: STUBSLOW keep going") ?? false,
                      "the reply the server finished is not in the conversation")
    }
}
