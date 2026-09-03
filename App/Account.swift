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

    /// When this device last finished a sync.
    ///
    /// Two jobs, and neither is "what to download". It decides which local rows
    /// still need uploading, and it's the "Backed up 5 minutes ago" line on the
    /// You tab. It is never sent to the server as a filter on what comes back —
    /// see `pull(context:session:)` for what that cost us.
    private let lastSyncKey = "lastSyncedAt"

    /// A thousand borks per request; most libraries are one request.
    private static let pullPageSize = 1000
    /// A runaway pull is worse than a short one. 30 pages is 30,000 borks.
    private static let pullPageLimit = 30

    init() {
        session = Keychain.loadSession()
        lastSynced = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Auth

    func sendCode(to email: String, createIfNew: Bool) async throws {
        try await Supabase.sendCode(to: email.trimmingCharacters(in: .whitespaces).lowercased(),
                                    createIfNew: createIfNew)
    }

    func verify(code: String, email: String) async throws {
        let new = try await Supabase.verifyCode(
            code.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces).lowercased()
        )
        Keychain.save(new)
        session = new
    }

    /// Password sign-in, for the App Review demo account only.
    func signIn(email: String, password: String) async throws {
        let new = try await Supabase.signIn(
            email: email.trimmingCharacters(in: .whitespaces).lowercased(),
            password: password
        )
        Keychain.save(new)
        session = new
    }

    /// Deletes the account server-side, then signs out. Local borks stay on
    /// the phone — the app is local-first and the user's device is theirs.
    func deleteAccount() async throws {
        let current = try await validSession()
        try await Supabase.deleteAccount(session: current)
        signOut()
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
        // Unchanged, and safe in a way the old pull wasn't: both sides of this
        // comparison were stamped by *this* device's clock, so it can only
        // over-send (a row we already pushed), never under-send.
        let cutoff = lastSynced
        let all = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        let changed = all.filter { cutoff == nil || $0.updatedAt > cutoff! }
        guard !changed.isEmpty else { return }

        // PostgREST rejects a bulk upsert whose rows don't share an identical
        // key set (PGRST102 "All object keys must match"). Assigning a nil
        // Optional to a dictionary subscript *removes* the key, so the old
        // per-row optional assignments made every mixed batch fail. Absent
        // values must be explicit nulls, never missing keys.
        func nullable(_ value: Any?) -> Any { value ?? NSNull() }
        let rows = changed.map { bookmark -> [String: Any] in
            [
                "id": bookmark.id,
                "owner_id": session.userID,
                "url": bookmark.urlString,
                "title": bookmark.title,
                "platform": bookmark.platformRaw,
                "kind": bookmark.kindRaw,
                "tags": bookmark.tags,
                "saved_at": SupabaseDate.string(from: bookmark.savedAt),
                "updated_at": SupabaseDate.string(from: bookmark.updatedAt),
                "author": nullable(bookmark.author),
                "category_id": nullable(bookmark.categoryID),
                "subcategory": nullable(bookmark.subcategory),
                "body_text": nullable(bookmark.text),
                "duration_seconds": nullable(bookmark.durationSeconds),
                "note_text": nullable(bookmark.noteText),
                "image_url": nullable(bookmark.imageURLString),
                "deleted_at": nullable(bookmark.deletedAt.map { SupabaseDate.string(from: $0) }),
            ]
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

    /// Read the **whole** library, every sync. Never a since-cursor.
    ///
    /// `updated_at` is stamped by whichever *client* wrote the row — there is no
    /// server clock in this design — so a row routinely reaches the server
    /// carrying a timestamp older than a cursor this device saved earlier: a
    /// phone that saved while offline and pushed later, a second device whose
    /// clock is a few seconds behind, or simply a phone save at 20:48Z followed
    /// by a web edit that advanced the cursor past it. `updated_at=gt.<cursor>`
    /// then hides that row from this device *permanently* — it is never newer
    /// than the cursor again — and two devices editing on the same day silently
    /// diverge. That is exactly what happened to a bork saved on the phone on
    /// 30 Aug; the web app reached the same conclusion first and now always
    /// pulls in full (`pull()` in `docs/index.html`).
    ///
    /// So: read everything, merge last-writer-wins, respect the tombstones. One
    /// request per thousand borks, on foreground, is the price of never losing
    /// one — and it is the cheap half of the sync anyway, since `push` still
    /// only uploads what changed.
    private func pull(context: ModelContext, session: Supabase.Session) async throws {
        // One fetch of what's already here rather than one per row. A full pull
        // visits every row every sync, and a predicate fetch each time is
        // thousands of SQLite round-trips on the main actor.
        var local: [String: Bookmark] = [:]
        for bookmark in (try? context.fetch(FetchDescriptor<Bookmark>())) ?? [] {
            local[bookmark.id] = bookmark
        }

        for page in 0..<Self.pullPageLimit {
            let data = try await Supabase.fetchPage(
                from: "bookmarks", ownerID: session.userID,
                offset: page * Self.pullPageSize, limit: Self.pullPageSize, session: session
            )
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !rows.isEmpty else { return }

            for row in rows { merge(row, into: context, local: &local) }
            // Save per page, so a pull that dies on page four keeps the first
            // three rather than starting over.
            try? context.save()

            if rows.count < Self.pullPageSize { return }
            await Task.yield()
        }
    }

    /// Fold one remote row into the local store: last-writer-wins on
    /// `updated_at`, tombstones included.
    ///
    /// A `deleted_at` row with no local copy is still inserted — soft-deleted,
    /// so it stays out of every view — because that is what stops a device that
    /// missed the delete from re-uploading the bork on its next push.
    private func merge(_ row: [String: Any], into context: ModelContext,
                       local: inout [String: Bookmark]) {
        guard
            let id = row["id"] as? String,
            let urlString = row["url"] as? String,
            let url = URL(string: urlString),
            let updatedRaw = row["updated_at"] as? String,
            let remoteUpdated = SupabaseDate.parse(updatedRaw)
        else { return }

        let existing = local[id]

        // Local wins if it's newer — the user is holding this device.
        if let existing, existing.updatedAt >= remoteUpdated { return }

        let target = existing ?? {
            let fresh = Bookmark(url: url, title: (row["title"] as? String) ?? "")
            context.insert(fresh)
            local[id] = fresh
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
