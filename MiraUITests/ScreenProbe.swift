import XCTest

/// The stand-in server the simulator tests talk to (`scripts/mira-stub-server.py`).
enum StubServer {
    static let url = "http://127.0.0.1:18765"

    static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_UDID"] != nil
    }

    /// The stub's URL when running in the simulator, nil on a device.
    static var urlIfSimulator: String? { isSimulator ? url : nil }

    /// Every mutating request the stub has received, as "METHOD path".
    static func mutations() -> [String] {
        guard let endpoint = URL(string: url + "/_stub/log") else { return [] }
        let done = DispatchSemaphore(value: 0)
        var result: [String] = []
        URLSession.shared.dataTask(with: endpoint) { data, _, _ in
            if let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let log = obj["log"] as? [[String: Any]] {
                result = log.map { "\($0["method"] as? String ?? "?") \($0["path"] as? String ?? "?")" }
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return result
    }

    /// POST a JSON body to one of the stub's control routes (`/_stub/set`, `/_stub/reset`).
    static func control(_ path: String, _ body: [String: Any] = [:]) {
        guard let endpoint = URL(string: url + path) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 5)
    }

    static func isUp() -> Bool {
        guard let endpoint = URL(string: url + "/health") else { return false }
        let done = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: endpoint) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 3)
        return ok
    }
}

/// One look at the chat screen, taken two ways: a screenshot, measured for how
/// much of the message area differs from the background, and the accessibility
/// tree, read for message text and the app's own state markers. The two can
/// disagree (a list that holds its rows and draws none of them), so "something
/// is on screen" needs both.
struct ScreenSample {
    let tag: String
    let t: TimeInterval
    /// Fraction of the message area that is not background. -1 if unmeasured.
    let ink: Double
    let texts: Int
    let chars: Int
    let loading: Bool
    let error: Bool
    let empty: Bool
    /// The status line above the input bar, or "" when it is not showing.
    let status: String
    /// Every static text in the message area, joined. For content assertions.
    let content: String

    /// A spinner with one line of text measures about 0.002; a blank list is 0.
    static let minimumInk = 0.0004

    var drawsSomething: Bool { ink >= Self.minimumInk }
    var treeShowsSomething: Bool { texts > 0 || loading || error || empty }
    var isBlank: Bool { !drawsSomething || !treeShowsSomething }

    var line: String {
        String(format: "%@ t=%.2f ink=%.4f texts=%d chars=%d loading=%@ error=%@ empty=%@ status=[%@]",
               tag, t, ink, texts, chars, "\(loading)", "\(error)", "\(empty)", status)
    }
}

enum ScreenProbe {

    /// The message area: below the top pills and banners, above the status
    /// line and the input bar. x 4 to 96 %, y 18 to 76 % of the screen.
    private static let top = 0.18, bottom = 0.76

    static func sample(_ app: XCUIApplication, tag: String, since start: Date, attachTo test: XCTestCase) -> ScreenSample {
        let shot = app.screenshot()
        let t = Date().timeIntervalSince(start)
        let inkValue = ink(in: shot)

        var texts = 0, chars = 0
        var loading = false, error = false, empty = false
        var status = ""
        var content: [String] = []
        if let tree = try? app.snapshot() {
            let screen = tree.frame
            let area = CGRect(x: screen.minX, y: screen.minY + screen.height * top,
                              width: screen.width, height: screen.height * (bottom - top))
            // Wider than the judged area: the last line of a reply and the
            // status line sit just above the input bar.
            let reading = CGRect(x: screen.minX, y: screen.minY + screen.height * 0.08,
                                 width: screen.width, height: screen.height * 0.80)
            walk(tree) { node in
                if node.elementType == .staticText, !node.label.isEmpty, node.frame.intersects(reading) {
                    content.append(node.label)
                }
                switch node.identifier {
                case "transcript-loading": loading = true
                case "transcript-error":   error = true
                case "transcript-empty":   empty = true
                case "turn-status":        if !node.label.isEmpty { status = node.label }
                default: break
                }
                if node.elementType == .staticText, !node.label.isEmpty, node.frame.intersects(area) {
                    texts += 1
                    chars += node.label.count
                }
            }
        }

        let result = ScreenSample(tag: tag, t: t, ink: inkValue, texts: texts, chars: chars,
                                  loading: loading, error: error, empty: empty, status: status,
                                  content: content.joined(separator: "\n"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = String(format: "%@-t%05.0fms", tag, t * 1000)
        attachment.lifetime = .keepAlways
        test.add(attachment)
        print("PROBE " + result.line)
        return result
    }

    private static func walk(_ node: XCUIElementSnapshot, _ visit: (XCUIElementSnapshot) -> Void) {
        visit(node)
        for child in node.children { walk(child, visit) }
    }

    /// Fraction of the message area whose colour differs from the area's most
    /// common colour.
    static func ink(in screenshot: XCUIScreenshot) -> Double {
        guard let cg = screenshot.image.cgImage else { return -1 }
        let w = cg.width / 4, h = cg.height / 4
        guard w > 0, h > 0 else { return -1 }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return -1 }

        let x0 = Int(Double(w) * 0.04), x1 = Int(Double(w) * 0.96)
        let y0 = Int(Double(h) * top), y1 = Int(Double(h) * bottom)
        var histogram: [Int: Int] = [:]
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                let key = (Int(pixels[i]) >> 3) << 10 | (Int(pixels[i + 1]) >> 3) << 5 | (Int(pixels[i + 2]) >> 3)
                histogram[key, default: 0] += 1
            }
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key else { return -1 }
        let br = ((background >> 10) & 31) << 3, bg = ((background >> 5) & 31) << 3, bb = (background & 31) << 3
        var different = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * w + x) * 4
                let d = abs(Int(pixels[i]) - br) + abs(Int(pixels[i + 1]) - bg) + abs(Int(pixels[i + 2]) - bb)
                if d > 48 { different += 1 }
            }
        }
        return Double(different) / Double((x1 - x0) * (y1 - y0))
    }
}
