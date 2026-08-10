import Foundation
import SwiftData
import Security

/// Signed-in state and two-way sync.
///
/// The app stays **local-first**: everything works signed out, saving never
/// waits on the network, and the phone remains the thing you actually use. Sync
/// is a backup-and-mirror layer on top, not the source of truth. That ordering
/// matters — an app that can't save without a server is worse than one that
/// can't sync.
@MainActor
final class Account: ObservableObject {

    @Published private(set) var session: Supabase.Session?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSynced: Date?
    @Published var lastError: String?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    private let lastSyncKey = "lastSyncedAt"

    init() {
        session = Keychain.loadSession()
        lastSynced = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Auth

    func sendCode(to email: String) async throws {
        try await Supabase.sendCode(to: email.trimmingCharacters(in: .whitespaces).lowercased())
    }

    func verify(code: String, email: String) async throws {
        let new = try await Supabase.verifyCode(
            code.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased()
        )
        Keychain.save(new)
        session = new
    }

    func signOut() {
        Keychain.clear()
        session = nil
        lastSynced = nil
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
    }

    /// A session with a usable access token, or `nil`.
    ///
    /// For callers that want the network *if* it's available and should quietly
    /// do without otherwise — AI categorisation, not sync. Signed out, a failed
    /// refresh and an expired refresh token all look the same from here on
    /// purpose: there is nothing for the caller to do differently.
    func currentSession() async -> Supabase.Session? {
        guard session != nil else { return nil }
        return try? await validSession()
    }

    /// Refreshes silently when the access token is close to expiry.
    private func validSession() async throws -> Supabase.Session {
        guard var current = session else { throw Supabase.Failure.notConfigured }
        if current.isExpired {
            current = try await Supabase.refresh(current)
            Keychain.save(current)
            session = current
        }
        return current
    }

    // MARK: - Sync

    /// Push local changes, then pull remote ones.
    ///
    /// Conflict resolution is last-write-wins on `updatedAt`. That's the right
    /// trade for this data: a bookmark is small, edits are rare, and the cost of
    /// losing one manual re-categorisation is far below the complexity of
    /// merging field-by-field.
    func sync(context: ModelContext) async {
        guard Supabase.isConfigured, isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let session = try await validSession()
            try await push(context: context, session: session)
            try await pull(context: context, session: session)

            lastSynced = .now
            UserDefaults.standard.set(lastSynced, forKey: lastSyncKey)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func push(context: ModelContext, session: Supabase.Session) async throws {
        let cutoff = lastSynced
        let all = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        let changed = all.filter { cutoff == nil || $0.updatedAt > cutoff! }
        guard !changed.isEmpty else { return }

        let rows = changed.map { bookmark -> [String: Any] in
            var row: [String: Any] = [
                "id": bookmark.id,
                "owner_id": session.userID,
                "url": bookmark.urlString,
                "title": bookmark.title,
                "platform": bookmark.platformRaw,
                "kind": bookmark.kindRaw,
                "tags": bookmark.tags,
                "saved_at": SupabaseDate.string(from: bookmark.savedAt),
                "updated_at": SupabaseDate.string(from: bookmark.updatedAt),
            ]
            row["author"] = bookmark.author
            row["category_id"] = bookmark.categoryID
            row["subcategory"] = bookmark.subcategory
            row["body_text"] = bookmark.text
            row["duration_seconds"] = bookmark.durationSeconds
            row["note_text"] = bookmark.noteText
            row["image_url"] = bookmark.imageURLString
            if let deleted = bookmark.deletedAt {
                row["deleted_at"] = SupabaseDate.string(from: deleted)
            }
            return row
        }

        // Chunked so a large first sync doesn't hit request size limits, and
        // encoded here on the main actor so only Sendable `Data` crosses over.
        for start in stride(from: 0, to: rows.count, by: 200) {
            let chunk = Array(rows[start..<min(start + 200, rows.count)])
            let json = try JSONSerialization.data(withJSONObject: chunk)
            try await Supabase.upsert(rowsJSON: json, into: "bookmarks",
                                      onConflict: "owner_id,id", session: session)
        }
    }

    private func pull(context: ModelContext, session: Supabase.Session) async throws {
        let data = try await Supabase.fetchChanged(from: "bookmarks",
                                                   since: lastSynced, session: session)
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !rows.isEmpty else { return }

        for row in rows {
            guard
                let id = row["id"] as? String,
                let urlString = row["url"] as? String,
                let url = URL(string: urlString),
                let updatedRaw = row["updated_at"] as? String,
                let remoteUpdated = SupabaseDate.parse(updatedRaw)
            else { continue }

            var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            let existing = try? context.fetch(descriptor).first

            // Local wins if it's newer — the user is holding this device.
            if let existing, existing.updatedAt >= remoteUpdated { continue }

            let target = existing ?? {
                let fresh = Bookmark(url: url, title: (row["title"] as? String) ?? "")
                context.insert(fresh)
                return fresh
            }()

            target.title = (row["title"] as? String) ?? target.title
            target.author = row["author"] as? String
            target.categoryID = row["category_id"] as? String
            target.subcategory = row["subcategory"] as? String
            target.tags = (row["tags"] as? [String]) ?? []
            target.text = row["body_text"] as? String
            target.durationSeconds = row["duration_seconds"] as? Int
            target.noteText = row["note_text"] as? String
            target.imageURLString = row["image_url"] as? String
            if let savedRaw = row["saved_at"] as? String,
               let saved = SupabaseDate.parse(savedRaw) {
                target.savedAt = saved
            }
            if let deletedRaw = row["deleted_at"] as? String {
                target.deletedAt = SupabaseDate.parse(deletedRaw)
            } else {
                target.deletedAt = nil
            }
            target.updatedAt = remoteUpdated
            target.rebuildSearchBlob()
        }

        try? context.save()
    }
}

/// Tokens are credentials and belong in the Keychain, not UserDefaults —
/// UserDefaults is a plist any backup or file-access bug can read.
private enum Keychain {
    private static let service = "com.jpwilson.borkmarkr"
    private static let account = "session"

    static func save(_ session: Supabase.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func loadSession() -> Supabase.Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Supabase.Session.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
