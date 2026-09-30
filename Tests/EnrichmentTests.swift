import XCTest
import SwiftData
@testable import borkmarkr

final class EnrichmentTests: XCTestCase {
    @MainActor func testLegacyAndManualChoicesSurviveResavingFromShareSheet() throws {
        let container = try ModelContainer(for: Bookmark.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let url = URL(string: "https://example.com/a")!
        let existing = Bookmark(url:url,title:"My title",categoryID:"health",subcategory:"Breathing",tags:["mine"])
        existing.filingSource = nil; existing.tagsEdited = nil; existing.titleEdited = true
        context.insert(existing); try context.save()
        let incoming = BookmarkDraft(url:url,title:"Automatic title",categoryID:"fitness",subcategory:"Running",tags:["auto"])
        let saved = try Store.save(incoming,in:context)
        XCTAssertEqual(saved.id,existing.id); XCTAssertEqual(saved.title,"My title")
        XCTAssertEqual(saved.categoryID,"health"); XCTAssertEqual(saved.tags,["mine"])
        XCTAssertFalse(EnrichmentPolicy.mayFile(source:nil)); XCTAssertFalse(EnrichmentPolicy.mayFile(source:"user"))
        XCTAssertTrue(EnrichmentPolicy.mayFile(source:"automatic"))
    }
    func testAttemptsResumeAndStopHammeringUnavailableSources() {
        XCTAssertTrue(EnrichmentPolicy.due(version:nil,attempts:nil,lastAttempt:nil))
        XCTAssertFalse(EnrichmentPolicy.due(version:2,attempts:1,lastAttempt:nil))
        XCTAssertFalse(EnrichmentPolicy.due(version:nil,attempts:3,lastAttempt:nil))
        XCTAssertFalse(EnrichmentPolicy.due(version:nil,attempts:1,lastAttempt:.now))
        XCTAssertTrue(EnrichmentPolicy.due(version:nil,attempts:1,lastAttempt:.now.addingTimeInterval(-3601)))
    }
}
