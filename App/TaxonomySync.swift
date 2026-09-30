import Foundation
import SwiftData

/// Metadata is authoritative. Do not reverse-engineer names/colors from slugs.
@MainActor enum TaxonomySync {
    static func run(context: ModelContext, session: Supabase.Session) async throws {
        for table in ["custom_topics", "custom_subtopics"] {
            let remote = try await fetch(table, session)
            try merge(remote, table: table, context: context)
            let revisions = Dictionary(uniqueKeysWithValues: remote.compactMap { row -> (String, Date)? in
                guard let id = row["id"] as? String, let raw = row["updated_at"] as? String,
                      let stamp = SupabaseDate.parse(raw) else { return nil }
                return (id, stamp)
            })
            let local = try records(table: table, context: context, owner: session.userID)
            let pending = local.filter {
                guard let id = $0["id"] as? String, let raw = $0["updated_at"] as? String,
                      let stamp = SupabaseDate.parse(raw), let theirs = revisions[id] else { return true }
                return stamp > theirs
            }
            for start in stride(from: 0, to: pending.count, by: 200) {
                let chunk = Array(pending[start..<min(start + 200, pending.count)])
                try await Supabase.upsert(rowsJSON: JSONSerialization.data(withJSONObject: chunk),
                    into: table, onConflict: "owner_id,id", session: session)
            }
            if !pending.isEmpty { try merge(try await fetch(table, session), table: table, context: context) }
        }
        let topics = try context.fetch(FetchDescriptor<CustomTopic>())
        let subs = try context.fetch(FetchDescriptor<CustomSubtopic>())
        _ = MergedTaxonomy(topics: topics, subtopics: subs)
        let deletedTopics = Set(topics.filter { $0.deletedAt != nil }.map(\.id))
        let deletedSubs = Set(subs.filter { $0.deletedAt != nil }.map { "\($0.categoryID)|\($0.name)" })
        for b in try context.fetch(FetchDescriptor<Bookmark>()) {
            if let id = b.categoryID, deletedTopics.contains(id) {
                b.categoryID = nil; b.subcategory = nil; b.filingSource = "user"; b.touch()
            } else if let id = b.categoryID, let sub = b.subcategory, deletedSubs.contains("\(id)|\(sub)") {
                b.subcategory = nil; b.filingSource = "user"; b.touch()
            } else { b.rebuildSearchBlob() }
        }
        try context.save()
    }
    private static func fetch(_ table: String, _ session: Supabase.Session) async throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        for page in 0..<30 {
            let data = try await Supabase.fetchPage(from: table, ownerID: session.userID,
                offset: page * 1000, limit: 1000, session: session)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { throw Supabase.Failure.decoding }
            result += rows
            if rows.count < 1000 { return result }
        }
        throw Supabase.Failure.http(413, "Your topic backup is incomplete. Please retry.")
    }
    static func records(table: String, context: ModelContext, owner: String) throws -> [[String: Any]] {
        func null(_ v: Any?) -> Any { v ?? NSNull() }
        if table == "custom_topics" {
            return try context.fetch(FetchDescriptor<CustomTopic>()).map { t in
                ["id": t.id, "owner_id": owner, "name": t.name, "hue": t.hue,
                 "image_url": null(t.imageURLString), "created_at": SupabaseDate.string(from: t.createdAt),
                 "updated_at": SupabaseDate.string(from: t.updatedAt),
                 "deleted_at": null(t.deletedAt.map(SupabaseDate.string))]
            }
        }
        return try context.fetch(FetchDescriptor<CustomSubtopic>()).map { t in
            ["id": t.id, "owner_id": owner, "category_id": t.categoryID, "name": t.name,
             "created_at": SupabaseDate.string(from: t.createdAt),
             "updated_at": SupabaseDate.string(from: t.updatedAt ?? t.deletedAt ?? t.createdAt),
             "deleted_at": null(t.deletedAt.map(SupabaseDate.string))]
        }
    }
    static func merge(_ rows: [[String: Any]], table: String, context: ModelContext) throws {
        var topics = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CustomTopic>()).map { ($0.id, $0) })
        var subs = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CustomSubtopic>()).map { ($0.id, $0) })
        for row in rows {
            guard let id = row["id"] as? String, let name = row["name"] as? String,
                  let raw = row["updated_at"] as? String, let stamp = SupabaseDate.parse(raw),
                  let created = (row["created_at"] as? String).flatMap(SupabaseDate.parse)
            else { throw Supabase.Failure.decoding }
            let deleted = (row["deleted_at"] as? String).flatMap(SupabaseDate.parse)
            if table == "custom_topics" {
                if let t = topics[id], t.updatedAt >= stamp { continue }
                guard let hue = row["hue"] as? Double else { throw Supabase.Failure.decoding }
                let t = topics[id] ?? CustomTopic(name: name, hue: hue)
                if topics[id] == nil { t.id = id; context.insert(t); topics[id] = t }
                t.name = name; t.hue = hue; t.imageURLString = row["image_url"] as? String
                t.createdAt = created; t.updatedAt = stamp; t.deletedAt = deleted
            } else {
                if let t = subs[id], (t.updatedAt ?? t.deletedAt ?? t.createdAt) >= stamp { continue }
                guard let parent = row["category_id"] as? String else { throw Supabase.Failure.decoding }
                let t = subs[id] ?? CustomSubtopic(categoryID: parent, name: name)
                if subs[id] == nil { t.id = id; context.insert(t); subs[id] = t }
                t.name = name; t.categoryID = parent
                t.createdAt = created; t.updatedAt = stamp; t.deletedAt = deleted
            }
        }
        try context.save()
    }
}
