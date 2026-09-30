import XCTest

/// The press-and-hold menu and Revisit's one-at-a-time pile, on the DEBUG
/// `-seed -layoutStress` fixture. Screenshots are kept in the result bundle.
final class BorkActionsTests: XCTestCase {

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "-layoutStress"]
        app.launch()
        return app
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPressAndHoldOffersLabelledActions() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["bork-card"].firstMatch.waitForExistence(timeout: 20))

        // The first cards start below the fold on launch, and a press aimed
        // at an element's centre off screen lands on whatever is there. Bring
        // the feed up, then press a card that is wholly on screen and clear
        // of the dock.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1.0)
        let screen = app.frame
        var target: CGRect?
        func find(_ node: XCUIElementSnapshot) {
            if target == nil, node.identifier == "bork-card",
               node.frame.minY > screen.minY + 120, node.frame.maxY < screen.maxY - 160 {
                target = node.frame
            }
            node.children.forEach(find)
        }
        find(try app.snapshot())
        let card = try XCTUnwrap(target, "No card wholly on screen")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: card.midX, dy: card.midY))
            .press(forDuration: 1.2)
        Thread.sleep(forTimeInterval: 1.0)
        keep(app, "Press and hold a bork")

        // Menu items surface as buttons or menu items depending on the OS;
        // look for the labels anywhere in one snapshot.
        let root = try app.snapshot()
        var labels: Set<String> = []
        func walk(_ node: XCUIElementSnapshot) {
            if !node.label.isEmpty { labels.insert(node.label) }
            node.children.forEach(walk)
        }
        walk(root)
        let note = XCTAttachment(string: labels.sorted().joined(separator: "\n"))
        note.name = "Labels on screen"
        note.lifetime = .keepAlways
        add(note)
        print("MENU_LABELS", labels.filter { $0.count < 40 }.sorted())

        XCTAssertTrue(labels.contains("Copy link"), "No Copy link")
        XCTAssertTrue(labels.contains("Share link"), "No Share link")
        XCTAssertTrue(labels.contains("Delete…"), "No Delete…")
        XCTAssertTrue(labels.contains { $0.hasPrefix("Open in") || $0.hasPrefix("Watch on") || $0 == "Open original" },
                      "No open action")
    }

    func testRevisitDealsTheNeverOpenedPileOneAtATime() {
        let app = launch()
        XCTAssertTrue(app.buttons["bork-card"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Revisit"].firstMatch.tap()

        let start = app.buttons["revisit-go-through"]
        for _ in 0..<6 where !start.exists { app.swipeUp() }
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 of '")).firstMatch.waitForExistence(timeout: 5))
        keep(app, "Revisit: first of the pile")
        app.buttons["queue-next"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '2 of '")).firstMatch.waitForExistence(timeout: 5))
        keep(app, "Revisit: second of the pile")
    }
}
