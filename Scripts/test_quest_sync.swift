import Foundation
@main enum QuestSyncTests {
    static func main() throws {
        let json = """
        [{"id":"q","title":"Mobility","category_id":"health","bookmark_ids":["a","b"],
          "completed_days":["2026-09-12"],"todos":[{"id":"t","text":"Stretch","done":true}],
          "is_archived":true,"created_at":"2026-09-01T00:00:00Z","updated_at":"2026-09-12T00:00:00.123Z",
          "deleted_at":"2026-09-12T00:00:00Z","brief_text":"{}","brief_bork_count":2}]
        """
        let rows = try JSONDecoder().decode([QuestSyncRecord].self, from: Data(json.utf8))
        precondition(rows[0].todos?.first?.text == "Stretch")
        precondition(rows[0].todos?.first?.done == true)
        precondition(rows[0].bookmarkIDs == ["a","b"])
        let encoded = try QuestSyncRecord.rowsJSON(rows, ownerID: "fixture")
        let roundtrip = try JSONDecoder().decode([QuestSyncRecord].self, from: encoded)
        precondition(roundtrip[0].deletedAt != nil && roundtrip[0].isArchived)
        let objects = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        precondition(objects[0]["detail"] is NSNull)
        precondition(objects[0]["habit_name"] is NSNull)
        precondition(objects[0]["owner_id"] as? String == "fixture")
        precondition(QuestSyncRecord.dayString(QuestSyncRecord.dayDate("2026-09-12")!) == "2026-09-12")
        let legacy = Data(#"{"id":"old","title":"Legacy","done":false}"#.utf8)
        let oldTodo = try JSONDecoder().decode(QuestSyncRecord.Todo.self, from: legacy)
        precondition(oldTodo.text == "Legacy")
        print("Quest sync: wire fields, legacy todos, nulls, dates and tombstones passed.")
    }
}
