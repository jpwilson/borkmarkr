import Foundation
import Security

/// The signed-in session, in the Keychain.
///
/// Tokens are credentials and belong in the Keychain, not UserDefaults —
/// UserDefaults is a plist any backup or file-access bug can read.
///
/// **The Share Extension borrows it and nothing more.** Both targets list the
/// app's own application identifier as their one keychain access group
/// (`project.yml`). That was already the app's default group, so the item the
/// app has always written, with no access group named, stays exactly where it
/// is and the extension can now read it. `save` and `clear` don't exist in the
/// extension, and what it borrows has no refresh token: a refresh spends the
/// refresh token (Supabase rotates them), so an extension that refreshed would
/// leave the app holding a dead one. `Supabase.refresh` isn't there either.
///
/// **Beside it, a share key** (`ShareKey`, migration 0018), for when the token
/// has run out: it lasts an hour, and the app may not have been opened for
/// days. The server issues the key for this session, it can do one thing
/// (have `categorize` spend this account's AI quota), and it dies with the
/// session. It is a second item, kept on this device only, so it is never in
/// a backup, and the extension can only read it.
enum SessionKeychain {
    private static let service = "com.jpwilson.borkmarkr"
    private static let account = "session"
    private static let shareKeyAccount = "share-key"

    /// What `Supabase.issueShareKey` gave the app, and for whom.
    struct ShareKey: Codable, Sendable {
        var key: String
        var userID: String
        var issuedAt: Date

        /// 64 lowercase hex characters (`Supabase.isShareKey`).
        static func isWellFormed(_ key: String) -> Bool { Supabase.isShareKey(key) }
    }

    #if !SHARE_EXTENSION
    static func save(_ session: Supabase.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        write(data, account: account, accessible: kSecAttrAccessibleAfterFirstUnlock)
    }

    static func clear() {
        SecItemDelete(item(account) as CFDictionary)
    }

    static func saveShareKey(_ key: ShareKey) {
        guard let data = try? JSONEncoder().encode(key) else { return }
        write(data, account: shareKeyAccount, accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
    }

    static func clearShareKey() {
        SecItemDelete(item(shareKeyAccount) as CFDictionary)
    }

    /// Replaces the item's data in place, or adds the item when there is
    /// none. Never delete-then-add: a crash between the two signed the user
    /// out, and an extension reading in the gap found nothing to borrow.
    private static func write(_ data: Data, account: String, accessible: CFString) {
        let query = item(account)
        let update = [kSecValueData as String: data] as CFDictionary
        guard SecItemUpdate(query as CFDictionary, update) == errSecItemNotFound else { return }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = accessible
        SecItemAdd(insert as CFDictionary, nil)
    }
    #endif

    static func load() -> Supabase.Session? {
        read(account).flatMap { try? JSONDecoder().decode(Supabase.Session.self, from: $0) }
    }

    static func loadShareKey() -> ShareKey? {
        read(shareKeyAccount).flatMap { try? JSONDecoder().decode(ShareKey.self, from: $0) }
    }

    private static func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) -> Data? {
        var query = item(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess else { return nil }
        return found as? Data
    }

    /// What the Share Extension may ask with: `session` while its access token
    /// has at least `minimumLife` left (the page and the model get nine
    /// seconds between them), with the refresh token blanked. Otherwise nil,
    /// and the app refreshes it the next time it opens.
    static func borrowable(_ session: Supabase.Session?, now: Date = .now,
                           minimumLife: TimeInterval = 120) -> Supabase.Session? {
        guard var session, session.expiresAt.timeIntervalSince(now) >= minimumLife else { return nil }
        session.refreshToken = ""
        return session
    }

    /// Who the share sheet asks as: the stored session while it may be
    /// borrowed, exactly as before, and once its token has run out, the
    /// share key, if it was issued to the same account, so a sheet never
    /// asks as the account before a switch. Nil signed out.
    static func caller(stored: Supabase.Session?, key: ShareKey?, now: Date = .now) -> Supabase.Caller? {
        guard let stored else { return nil }
        if let borrowed = borrowable(stored, now: now) { return .session(borrowed) }
        guard let key, key.userID == stored.userID else { return nil }
        return .shareKey(key.key)
    }

    /// `caller`, from what the Keychain holds.
    static func shareSheetCaller() -> Supabase.Caller? { caller(stored: load(), key: loadShareKey()) }
}
