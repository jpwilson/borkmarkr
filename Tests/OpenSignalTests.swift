import XCTest
import SwiftData
@testable import borkmarkr

final class OpenSignalTests: XCTestCase {
    @MainActor func testLegacyBackfillAndRetryDoNotDoubleCount() throws {
        let container = try ModelContainer(for: Bookmark.self, OpenSignal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let b = Bookmark(url: URL(string: "https://example.com/open")!, title: "Saved post")
        context.insert(b)
        b.openCount = 8
        b.markOpened()
        try context.save()
        XCTAssertEqual(b.openCount, 9)
        try OpenSignal.seedLegacy(b, context: context)
        var signals = try context.fetch(FetchDescriptor<OpenSignal>())
        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals[0].count, 9)
        let row: [String:Any] = ["id":"web:" + b.id, "bookmark_id":b.id, "device_id":"web",
            "open_count":3, "updated_at":"2026-09-12T00:00:00Z", "last_opened_at":"2026-09-12T00:00:00Z"]
        try OpenSignalSync.merge([row, row], context: context)
        signals = try context.fetch(FetchDescriptor<OpenSignal>())
        XCTAssertEqual(signals.count, 2)
        XCTAssertEqual(signals.reduce(0) { $0 + $1.count }, 12)
        var stale = row; stale["open_count"] = 1
        try OpenSignalSync.merge([stale], context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<OpenSignal>()).reduce(0) { $0 + $1.count }, 12)
    }
}
