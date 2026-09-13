import XCTest
import SwiftData
@testable import borkmarkr

final class QuestSyncTests: XCTestCase {
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
