import XCTest
@testable import borkmarkr

final class SingleShareTests: XCTestCase {
    func testSingleShareIsCompleteAndPrivateByDefault() {
        func payload(_ include: Bool) -> String {
            SingleBookmarkShare.text(title:"Useful link",url:"https://example.com/post",topic:"Health",
                subtopic:"Breathing",tags:["calm","practice"],note:"PRIVATE NOTE",includeNote:include)
        }
        XCTAssertTrue(payload(false).contains("Health › Breathing"))
        XCTAssertTrue(payload(false).contains("#calm · #practice"))
        XCTAssertFalse(payload(false).contains("PRIVATE NOTE"))
        XCTAssertTrue(payload(true).contains("My note:\nPRIVATE NOTE"))
    }
}
