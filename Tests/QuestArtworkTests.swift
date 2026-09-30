import XCTest
@testable import borkmarkr

final class QuestArtworkTests: XCTestCase {
    func testNamesAndBodyMindFallbacks() {
        XCTAssertEqual(QuestCover.resolve(title: "Breathing", categoryID: "health"), .topic("health"))
        XCTAssertEqual(QuestCover.resolve(title: "Breathing"), .topic("wellness"))
        XCTAssertEqual(QuestCover.resolve(title: "Making OFS profitable"), .motif(.business))
        XCTAssertEqual(QuestCover.resolve(title: "Start a new chapter"), .motif(.compass))
        XCTAssertEqual(QuestCover.resolve(title: "Improve mobility"), .motif(.run))
        XCTAssertEqual(QuestCover.resolve(title: "Go down the rabbit hole"), .motif(.rabbit))
        XCTAssertEqual(QuestCover.resolve(title: "Get on top of anxiety"), .topic("mentalhealth"))
    }
}
