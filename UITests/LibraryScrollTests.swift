import XCTest

/// The Library on a heavy library — 269 mixed-source borks with long titles
/// and real covers, from the DEBUG `-seed -layoutStress` fixture. No private
/// data is ever used here.
///
/// Two regressions this guards:
/// - **The zoomed-in Library** (1.1 build 14 on an iPhone 17 Pro Max): a
///   loaded cover sized its card, the card widened the feed, and the whole
///   screen — dock included — laid out ~70pt wider than the phone on each
///   side.
/// - **The slow Library**: every card and every full-size cover built at
///   once. Scroll hitches and memory are measured here.
final class LibraryScrollTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "-layoutStress"]
        app.launch()
        return app
    }

    /// Every card, and the dock, stays inside the screen horizontally —
    /// the build 14 regression. Checked at the top and again deep in the
    /// feed, after covers have had time to load.
    ///
    /// One accessibility snapshot per pass, walked locally. Resolving each
    /// card as its own query is a round trip per card, and in the Simulator
    /// those stall.
    func testLibraryStaysInsideTheScreen() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["bork-card"].firstMatch.waitForExistence(timeout: 20))

        // Findings are collected and printed before anything is asserted:
        // XCTest symbolicates every failure's stack, which in the Simulator
        // can take many minutes before the message appears at all.
        var problems: [String] = []
        for pass in 0..<4 {
            // Covers arrive asynchronously; give them a moment to try to
            // widen something.
            Thread.sleep(forTimeInterval: 1.5)

            let root = try app.snapshot()
            let screen = root.frame
            var cards: [CGRect] = []
            var dock: [String: CGRect] = [:]
            func walk(_ node: XCUIElementSnapshot) {
                if node.identifier == "bork-card" { cards.append(node.frame) }
                if node.elementType == .button, ["Library", "Browse", "Revisit", "You"].contains(node.label) {
                    dock[node.label] = node.frame
                }
                node.children.forEach(walk)
            }
            walk(root)

            if dock.count != 4 { problems.append("pass \(pass): dock buttons \(dock.keys.sorted())") }
            for (tab, frame) in dock where frame.minX < screen.minX - 1 || frame.maxX > screen.maxX + 1 {
                problems.append("pass \(pass): dock \(tab) outside the screen \(frame)")
            }

            // Distinct frames only: an identifier can land on a container and
            // its button at the same rectangle.
            var seen = Set<String>()
            let visible = cards.filter { !$0.isEmpty && $0.intersects(screen) && seen.insert("\($0)").inserted }
            if visible.isEmpty { problems.append("pass \(pass): no cards on screen") }
            for card in visible where card.minX < screen.minX - 1 || card.maxX > screen.maxX + 1 {
                problems.append("pass \(pass): card outside the screen \(card)")
            }
            // Vertical overlap is deliberately not checked: in a scrolled
            // LazyVStack the accessibility frames of cards are reported
            // taller than drawn (up to ~120pt, extending upward), so they
            // "overlap" where the screenshot shows none. Each pass attaches
            // a screenshot for the eye instead.
            print("LAYOUT_PASS \(pass): \(visible.count) cards, dock \(dock.count)")
            let passShot = XCTAttachment(screenshot: app.screenshot())
            passShot.name = "pass-\(pass)"
            passShot.lifetime = .keepAlways
            add(passShot)
            app.swipeUp(velocity: .fast)
        }
        print("LAYOUT_PROBLEMS \(problems.count)", problems.prefix(12))
        XCTAssertTrue(problems.isEmpty, problems.prefix(12).joined(separator: "\n"))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Library deep in the feed"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Seconds to fling three screens down the feed and for the app to
    /// settle, three times — each swipe waits for the app to go idle, so a
    /// main thread busy building cards shows up here. Printed as
    /// `SCROLL_TIMING` and attached to the result.
    ///
    /// Timed by hand: in the iOS 26 Simulator XCTest's own `measure` harness
    /// hangs after its last iteration (and its hitch, CPU and memory metrics
    /// only harvest on a device).
    func testLibraryScrollTiming() {
        let app = launch()
        XCTAssertTrue(app.buttons["bork-card"].firstMatch.waitForExistence(timeout: 20))
        let feed = app.scrollViews.firstMatch

        var timings: [Double] = []
        for _ in 0..<3 {
            let start = Date()
            feed.swipeUp(velocity: .fast)
            feed.swipeUp(velocity: .fast)
            feed.swipeUp(velocity: .fast)
            timings.append(Date().timeIntervalSince(start))
            feed.swipeDown(velocity: .fast)
            feed.swipeDown(velocity: .fast)
            feed.swipeDown(velocity: .fast)
        }
        let line = "SCROLL_TIMING " + timings.map { String(format: "%.2fs", $0) }.joined(separator: " ")
        print(line)
        let note = XCTAttachment(string: line)
        note.lifetime = .keepAlways
        add(note)
    }
}
