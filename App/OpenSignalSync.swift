import Foundation
import SwiftData

@MainActor enum OpenSignalSync {
    static func run(context: ModelContext, session: Supabase.Session) async throws {
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        for b in bookmarks { try OpenSignal.seedLegacy(b, context: context) }
        try context.save()
        var remote: [[String: Any]] = []
        var complete = false
        for page in 0..<30 {
            let data = try await Supabase.fetchPage(from: "bookmark_opens", ownerID: session.userID,
                offset: page * 1000, limit: 1000, session: session)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { throw Supabase.Failure.decoding }
            remote += rows
            if rows.count < 1000 { complete = true; break }
        }
        guard complete else { throw Supabase.Failure.http(413, "Revisit backup is incomplete. Please retry.") }
        try merge(remote, context: context)
        let revisions = Dictionary(uniqueKeysWithValues: remote.compactMap { r -> (String, Int)? in
            guard let id = r["id"] as? String, let count = r["open_count"] as? Int else { return nil }
            return (id, count)
        })
        let all = try context.fetch(FetchDescriptor<OpenSignal>())
        let rows: [[String: Any]] = all.filter { $0.count > (revisions[$0.id] ?? -1) }.map {
            ["id": $0.id, "owner_id": session.userID, "bookmark_id": $0.bookmarkID,
             "device_id": $0.deviceID, "open_count": $0.count,
             "last_opened_at": $0.lastOpenedAt.map(SupabaseDate.string) as Any? ?? NSNull(),
             "created_at": SupabaseDate.string(from: $0.createdAt),
             "updated_at": SupabaseDate.string(from: $0.updatedAt)]
        }
        for start in stride(from: 0, to: rows.count, by: 200) {
            let chunk = Array(rows[start..<min(start + 200, rows.count)])
            try await Supabase.upsert(rowsJSON: JSONSerialization.data(withJSONObject: chunk),
                into: "bookmark_opens", onConflict: "owner_id,id", session: session)
        }
        let groups = Dictionary(grouping: all, by: \.bookmarkID)
        for b in bookmarks {
            let signals = groups[b.id] ?? []
            b.openCount = signals.reduce(0) { $0 + $1.count }
            b.lastOpenedAt = signals.compactMap(\.lastOpenedAt).max()
        }
        try context.save()
    }
    static func merge(_ rows: [[String: Any]], context: ModelContext) throws {
        var local = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<OpenSignal>()).map { ($0.id, $0) })
        for row in rows {
            guard let id = row["id"] as? String, let bookmark = row["bookmark_id"] as? String,
                  let device = row["device_id"] as? String, let count = row["open_count"] as? Int,
                  let raw = row["updated_at"] as? String, let updated = SupabaseDate.parse(raw)
            else { throw Supabase.Failure.decoding }
            let signal = local[id] ?? OpenSignal(bookmarkID: bookmark, deviceID: device)
            if local[id] == nil { signal.id = id; context.insert(signal); local[id] = signal }
            signal.count = max(signal.count, count)
            signal.lastOpenedAt = [signal.lastOpenedAt, (row["last_opened_at"] as? String).flatMap(SupabaseDate.parse)].compactMap { $0 }.max()
            signal.updatedAt = max(signal.updatedAt, updated)
        }
        try context.save()
    }
}
