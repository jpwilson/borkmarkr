import XCTest
import SwiftData
@testable import borkmarkr

final class TaxonomySyncTests: XCTestCase {
    @MainActor func testMetadataAndPermanentIdentitySurviveRename() throws {
        let container = try ModelContainer(for: CustomTopic.self, CustomSubtopic.self, Bookmark.self, Mission.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let topic = CustomTopic(name: "Café & ceramics", hue: 77)
        context.insert(topic)
        let originalID = topic.id
        Store.renameTopic(topic, to: "Weekend pottery", in: context)
        Store.foldCustomTopicIDs(in: context)
        XCTAssertEqual(topic.id, originalID)
        let rows = try TaxonomySync.records(table: "custom_topics", context: context, owner: "fixture")
        XCTAssertEqual(rows.first?["name"] as? String, "Weekend pottery")
        XCTAssertEqual(rows.first?["hue"] as? Double, 77)
        var incoming = try XCTUnwrap(rows.first)
        incoming["name"] = "Café & ceramics"
        incoming["updated_at"] = SupabaseDate.string(from: .now.addingTimeInterval(10))
        incoming["image_url"] = "https://example.com/art.jpg"
        try TaxonomySync.merge([incoming], table: "custom_topics", context: context)
        XCTAssertEqual(topic.name, "Café & ceramics")
        XCTAssertEqual(topic.imageURLString, "https://example.com/art.jpg")
        XCTAssertEqual(topic.id, originalID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CustomTopic>()), 1)
    }

    @MainActor func testEmptyLegacySubtopicHasRevisionAndTombstone() throws {
        let container = try ModelContainer(for: CustomTopic.self, CustomSubtopic.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let sub = CustomSubtopic(categoryID: "fitness", name: "Breathing")
        sub.updatedAt = nil
        context.insert(sub)
        var rows = try TaxonomySync.records(table: "custom_subtopics", context: context, owner: "fixture")
        XCTAssertNotNil(rows.first?["updated_at"])
        rows[0]["deleted_at"] = SupabaseDate.string(from: .now.addingTimeInterval(10))
        rows[0]["updated_at"] = rows[0]["deleted_at"]
        try TaxonomySync.merge(rows, table: "custom_subtopics", context: context)
        XCTAssertNotNil(sub.deletedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CustomSubtopic>()), 1)
    }
}
