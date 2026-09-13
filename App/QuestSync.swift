import Foundation
import SwiftData

@MainActor
enum QuestSync {
    static func run(context: ModelContext, session: Supabase.Session) async throws {
        let remote = try await fetch(session)
        try merge(remote, context: context)
        let stamps = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0.updatedAt) })
        // No bookmark watermark: every pre-existing local quest participates.
        let records = try context.fetch(FetchDescriptor<Mission>()).map(record)
        let pending = records.filter { row in
            guard let theirs = stamps[row.id].flatMap(SupabaseDate.parse),
                  let ours = SupabaseDate.parse(row.updatedAt) else { return true }
            return ours > theirs
        }
        for start in stride(from: 0, to: pending.count, by: 200) {
            let chunk = Array(pending[start..<min(start + 200, pending.count)])
            try await Supabase.upsert(rowsJSON: QuestSyncRecord.rowsJSON(chunk, ownerID: session.userID),
                                      into: "missions", onConflict: "owner_id,id", session: session)
        }
        // Includes concurrent remote winners rejected by the stale-write guard.
        if !pending.isEmpty { try merge(try await fetch(session), context: context) }
    }

    private static func fetch(_ session: Supabase.Session) async throws -> [QuestSyncRecord] {
        var result: [QuestSyncRecord] = []
        for page in 0..<30 {
            let data = try await Supabase.fetchPage(from: "missions", ownerID: session.userID,
                offset: page * 1000, limit: 1000, session: session)
            let rows = try JSONDecoder().decode([QuestSyncRecord].self, from: data)
            result += rows
            if rows.count < 1000 { return result }
        }
        throw Supabase.Failure.http(413, "The side-quest backup is incomplete. Please try again.")
    }

    static func record(_ m: Mission) -> QuestSyncRecord {
        QuestSyncRecord(id: m.id, title: m.title, detail: m.detail, categoryID: m.categoryID,
            bookmarkIDs: m.bookmarkIDs, habitName: m.habitName,
            completedDays: m.completedDays.map(QuestSyncRecord.dayString),
            todos: m.todos.map { .init(id: $0.id, text: $0.title, done: $0.done) },
            isArchived: m.isArchived, createdAt: SupabaseDate.string(from: m.createdAt),
            updatedAt: SupabaseDate.string(from: m.updatedAt),
            deletedAt: m.deletedAt.map(SupabaseDate.string),
            briefText: m.briefText, briefAt: m.briefAt.map(SupabaseDate.string),
            briefBorkCount: m.briefBorkCount)
    }

    static func merge(_ rows: [QuestSyncRecord], context: ModelContext) throws {
        var local = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Mission>()).map { ($0.id, $0) })
        for row in rows {
            guard let updated = SupabaseDate.parse(row.updatedAt),
                  let created = SupabaseDate.parse(row.createdAt) else { throw Supabase.Failure.decoding }
            if let current = local[row.id], current.updatedAt >= updated { continue }
            let m = local[row.id] ?? Mission(title: row.title)
            if local[row.id] == nil { m.id = row.id; context.insert(m); local[row.id] = m }
            m.title = row.title; m.detail = row.detail; m.categoryID = row.categoryID
            m.bookmarkIDs = row.bookmarkIDs; m.habitName = row.habitName
            m.completedDays = row.completedDays.compactMap(QuestSyncRecord.dayDate)
            m.todos = (row.todos ?? []).map {
                var todo = QuestTodo(title: $0.text, done: $0.done); todo.id = $0.id; return todo
            }
            m.isArchived = row.isArchived; m.createdAt = created
            m.deletedAt = row.deletedAt.flatMap(SupabaseDate.parse)
            m.briefText = row.briefText; m.briefAt = row.briefAt.flatMap(SupabaseDate.parse)
            m.briefBorkCount = row.briefBorkCount
            m.updatedAt = updated // after todos setter, which stamps local edits
        }
        try context.save()
    }
}
