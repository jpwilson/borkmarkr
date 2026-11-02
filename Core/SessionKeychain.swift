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
enum SessionKeychain {
    private static let service = "com.jpwilson.borkmarkr"
    private static let account = "session"

    #if !SHARE_EXTENSION
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

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
    #endif

    static func load() -> Supabase.Session? {
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

    /// The stored session, if the Share Extension may borrow it.
    static func borrow() -> Supabase.Session? { borrowable(load()) }
}
