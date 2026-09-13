import XCTest
import SwiftData
@testable import borkmarkr

final class QuestSyncTests: XCTestCase {
    @MainActor func testBriefInputKeepsCapturedTextAndExcludesPrivateNotes() throws {
        let request = QuestBrief.request(id: "q", title: "Goal", topic: nil, subtopic: nil,
            titles: ["Post"], todos: [], sources: [.init(id: "one", title: "Post", text: String(repeating: "x", count: 2000))])!
        XCTAssertEqual(request.sources[0].text.count, 1600)
        var changed = request; changed.sources[0].id = "two"
        XCTAssertNotEqual(QuestBrief.inputKey(request), QuestBrief.inputKey(changed))
        let encoded = try JSONEncoder().encode(request)
        let keys = (try JSONSerialization.jsonObject(with: encoded) as! [String: Any]).keys
        XCTAssertFalse(keys.contains("notes")); XCTAssertFalse(keys.contains("detail"))
        let brief = QuestBrief.parse(Data(#"{"summary":"Draft","steps":[],"source_ids":["one"],"basis":"saved_text","version":2}"#.utf8))!
        XCTAssertEqual(QuestBrief.decode(QuestBrief.encode(brief)), brief)
    }
    @MainActor func testExistingQuestRoundTripsAllFieldsAndDeletion() throws {
        let container = try ModelContainer(for: Mission.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let mission = Mission(title: "Mobility", detail: "For running", categoryID: "fitness", habitName: "Ten minutes")
        mission.bookmarkIDs = ["one", "two"]
        mission.todos = [QuestTodo(title: "Stretch", done: true)]
        mission.completedDays = [QuestSyncRecord.dayDate("2026-09-12")!]
        mission.briefText = "{}"; mission.briefBorkCount = 2
        mission.updatedAt = Date(timeIntervalSince1970: 100)
        context.insert(mission)
        try context.save()
        var remote = QuestSync.record(mission)
        remote.title = "Updated on web"
        remote.updatedAt = SupabaseDate.string(from: Date(timeIntervalSince1970: 200))
        remote.isArchived = true
        remote.deletedAt = remote.updatedAt
        try QuestSync.merge([remote], context: context)
        XCTAssertEqual(mission.title, "Updated on web")
        XCTAssertEqual(mission.bookmarkIDs, ["one", "two"])
        XCTAssertEqual(mission.todos.first?.title, "Stretch")
        XCTAssertEqual(mission.todos.first?.done, true)
        XCTAssertEqual(mission.todos.first?.id, remote.todos?.first?.id)
        XCTAssertEqual(mission.completedDays.map(QuestSyncRecord.dayString), ["2026-09-12"])
        XCTAssertTrue(mission.isArchived)
        XCTAssertNotNil(mission.deletedAt)
        XCTAssertEqual(mission.briefBorkCount, 2)
        remote.title = "Stale"
        remote.updatedAt = SupabaseDate.string(from: Date(timeIntervalSince1970: 150))
        remote.deletedAt = nil
        try QuestSync.merge([remote], context: context)
        XCTAssertEqual(mission.title, "Updated on web")
        XCTAssertNotNil(mission.deletedAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Mission>()), 1)
    }

    @MainActor func testRemoteQuestCreatesSameIdentityAndLocalNewerWins() throws {
        let container = try ModelContainer(for: Mission.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let original = Mission(title: "Created on web")
        var remote = QuestSync.record(original)
        try QuestSync.merge([remote], context: context)
        let mission = try XCTUnwrap(context.fetch(FetchDescriptor<Mission>()).first)
        XCTAssertEqual(mission.id, original.id)
        mission.title = "Offline edit"
        mission.updatedAt = .now.addingTimeInterval(10)
        remote.title = "Older server copy"
        try QuestSync.merge([remote], context: context)
        XCTAssertEqual(mission.title, "Offline edit")
    }
}
