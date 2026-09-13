import Foundation

/// Shared mission wire contract. Todo `text` is the web/database spelling;
/// native `title` is deliberately mapped at the model boundary.
struct QuestSyncRecord: Codable, Sendable {
    struct Todo: Codable, Sendable {
        var id: String
        var text: String
        var done: Bool
        init(id: String, text: String, done: Bool) { self.id = id; self.text = text; self.done = done }
        enum CodingKeys: String, CodingKey { case id, text, title, done }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            text = try c.decodeIfPresent(String.self, forKey: .text)
                ?? c.decode(String.self, forKey: .title)
            done = try c.decode(Bool.self, forKey: .done)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(text, forKey: .text)
            try c.encode(done, forKey: .done)
        }
    }
    var id: String
    var title: String
    var detail: String?
    var categoryID: String?
    var bookmarkIDs: [String]
    var habitName: String?
    var completedDays: [String]
    var todos: [Todo]?
    var isArchived: Bool
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var briefText: String?
    var briefAt: String?
    var briefBorkCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, detail, todos
        case categoryID = "category_id", bookmarkIDs = "bookmark_ids"
        case habitName = "habit_name", completedDays = "completed_days"
        case isArchived = "is_archived", createdAt = "created_at"
        case updatedAt = "updated_at", deletedAt = "deleted_at"
        case briefText = "brief_text", briefAt = "brief_at", briefBorkCount = "brief_bork_count"
    }

    static func rowsJSON(_ records: [Self], ownerID: String) throws -> Data {
        let encoded = try JSONEncoder().encode(records)
        guard var rows = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]]
        else { throw Supabase.Failure.decoding }
        for i in rows.indices {
            rows[i]["owner_id"] = ownerID
            // PostgREST bulk upserts require identical keys, including nulls.
            for key in ["detail", "category_id", "habit_name", "todos", "deleted_at",
                        "brief_text", "brief_at", "brief_bork_count"] where rows[i][key] == nil {
                rows[i][key] = NSNull()
            }
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }

    /// Completion is a calendar day, not an instant in somebody else's zone.
    static func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func dayDate(_ value: String) -> Date? {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: value)
    }
}
