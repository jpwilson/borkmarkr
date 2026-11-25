import XCTest

/// Typing a tag under the wheel: the field, and the tags it adds, stay above
/// the keyboard; return (or the field's +) adds and keeps the field; return
/// on an empty field closes it without closing the sheet. The Add sheet
/// (DEBUG `-add <url> -quickFileChosen`) and the share sheet's harness
/// (`-quickFileShare <url> -quickFileChosen`). No scrolling by the test: the
/// tag row has to be reachable as the sheet comes up.
///
/// Each step is kept as an attachment and, when `TAGPROBE_OUT` is set, also
/// written there as a PNG.
final class QuickFileTagEntryTests: XCTestCase {
    private static let out = ProcessInfo.processInfo.environment["TAGPROBE_OUT"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let screen = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screen)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if let out = Self.out {
            try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try? screen.pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
    }

    /// A link the library has never seen, so the dial shows rather than
    /// "Already in your library".
    private static func freshLink() -> String {
        "https://www.tiktok.com/@kaylawalks/video/73\(Int(Date().timeIntervalSince1970 * 1000))"
    }

    private func assertAbove(_ element: XCUIElement, _ top: CGFloat, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let frame = element.frame
        XCTAssertFalse(frame.isEmpty, "\(what) has no frame", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, top, "\(what) (\(frame)) is not above y=\(top)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, 0, "\(what) (\(frame)) is off the top", file: file, line: line)
    }

    private func keyboardTop(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGFloat {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "No keyboard", file: file, line: line)
        return keyboard.frame.minY
    }

    /// `typeText` on the simulator arrives as hardware key presses, which
    /// drop the on-screen keyboard for a moment (in the share sheet too); a
    /// person typing on the keys doesn't see that. So wait, up to 3 s, for
    /// the keyboard to be back and `element` to sit above it, then assert.
    private func settledAbove(_ app: XCUIApplication, _ element: XCUIElement, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, !keyboard.frame.isEmpty, element.exists,
               element.frame.maxY <= keyboard.frame.minY, element.frame.minY >= 0 {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.3)
        assertAbove(element, keyboardTop(app, file: file, line: line), what, file: file, line: line)
    }

    /// Steps 2 to 4: open the field, add one tag with return and one with +.
    private func typeTwoTags(_ app: XCUIApplication, prefix: String) {
        app.buttons["New tag"].tap()
        let field = app.textFields["New tag"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "No tag field")
        settledAbove(app, field, "Tag field")
        keep(app, "\(prefix)2-field-open")

        app.typeText("zzone")
        settledAbove(app, field, "Tag field while typing")
        keep(app, "\(prefix)3-typed")
        app.typeText("\n")
        let one = app.buttons["#zzone, tag"]
        XCTAssertTrue(one.waitForExistence(timeout: 5), "#zzone not added")
        settledAbove(app, one, "#zzone")
        keep(app, "\(prefix)4-after-return")
        XCTAssertTrue(field.exists, "Field closed after return")
        // An empty field reports its placeholder as its value.
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == "New tag", "Field not empty: \(value)")
        settledAbove(app, field, "Tag field after return")

        app.typeText("zztwo")
        let plus = app.buttons["Add tag"]
        XCTAssertTrue(plus.waitForExistence(timeout: 3), "No Add tag button")
        settledAbove(app, plus, "Add tag button")
        keep(app, "\(prefix)5-typed-second")
        plus.tap()
        XCTAssertTrue(app.buttons["#zztwo, tag"].waitForExistence(timeout: 5), "#zztwo not added")
        XCTAssertTrue(field.exists, "Field closed after +")
        settledAbove(app, field, "Tag field after +")
        keep(app, "\(prefix)6-after-plus")
    }

    func testAddSheetTagEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "-signedIn", "-add", Self.freshLink(), "-quickFileChosen"]
        app.launch()

        // 1. "+ Tag" is in reach above the pinned Done.
        let add = app.buttons["New tag"]
        XCTAssertTrue(add.waitForExistence(timeout: 30), "No + Tag")
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "No Done")
        Thread.sleep(forTimeInterval: 0.8)
        keep(app, "1-rest")
        XCTAssertTrue(add.isHittable, "+ Tag not hittable")
        assertAbove(add, done.frame.minY, "+ Tag")

        // 2-4.
        typeTwoTags(app, prefix: "")

        // 5. Return on the empty field: the keyboard goes, the sheet stays.
        app.typeText("\n")
        XCTAssertTrue(add.waitForExistence(timeout: 5), "+ Tag not back")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [gone], timeout: 5)
        Thread.sleep(forTimeInterval: 0.6)
        keep(app, "7-closed")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The keyboard came back")
        XCTAssertTrue(add.isHittable, "+ Tag not hittable after closing")
        XCTAssertTrue(app.buttons["#zzone, tag"].exists, "#zzone gone")
        XCTAssertTrue(app.buttons["#zztwo, tag"].exists, "#zztwo gone")
        XCTAssertTrue(done.exists, "The sheet closed")

        // 6. A tag being typed, then Done: the sheet closes.
        add.tap()
        XCTAssertTrue(app.textFields["New tag"].waitForExistence(timeout: 5), "No tag field")
        app.typeText("zzthree")
        done.tap()
        // The app's tab bar is its own dock of buttons, covered by the sheet.
        let library = app.buttons["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10), "No Library tab")
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: library)
        wait(for: [hittable], timeout: 10)
        XCTAssertFalse(done.exists, "The sheet is still up")
        keep(app, "8-closed-sheet")
    }

    func testShareSheetTagEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-quickFileShare", Self.freshLink(), "-quickFileChosen"]
        app.launch()
        XCTAssertTrue(app.buttons["New tag"].waitForExistence(timeout: 30), "No + Tag")
        Thread.sleep(forTimeInterval: 0.8)
        keep(app, "s1-rest")
        typeTwoTags(app, prefix: "s")
    }
}
