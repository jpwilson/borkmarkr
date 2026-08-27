import Foundation

/// Minimal Supabase client — auth and REST over `URLSession`.
///
/// No SDK dependency, matching the rest of the project. The official Swift SDK
/// would pull in a package tree for what amounts to a dozen HTTP calls, and the
/// endpoints below are stable, documented, and unlikely to change.
///
/// **Auth is email one-time-code, not a password.** The app never sees, stores,
/// or transmits a password: you type your email, Supabase emails a six-digit
/// code, you type the code. Fewer moving parts than magic links (no deep-link
/// plumbing), and nothing to leak.
enum Supabase {

    /// Filled in once the project exists. The anon key is *designed* to be
    /// public — row-level security in the database is what protects data, not
    /// the secrecy of this string. It is not a credential.
    struct Config {
        var url: URL
        var anonKey: String

        static var current: Config? {
            guard
                let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
                let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
                !raw.isEmpty, !key.isEmpty, !raw.hasPrefix("$("),
                let url = URL(string: raw)
            else { return nil }
            return Config(url: url, anonKey: key)
        }
    }

    static var isConfigured: Bool { Config.current != nil }

    // MARK: - Errors

    enum Failure: LocalizedError {
        case notConfigured
        case http(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .notConfigured: "bookmarker isn't connected to an account server yet."
            case .http(let code, let body):
                // Surface the server's own message — Supabase returns useful
                // ones ("Email rate limit exceeded", "Token has expired").
                body.isEmpty ? "Server error (\(code))" : body
            case .decoding: "Couldn't read the server's reply."
            }
        }
    }

    // MARK: - Session

    struct Session: Codable, Sendable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String

        var isExpired: Bool { Date.now >= expiresAt.addingTimeInterval(-60) }
    }

    // MARK: - Auth

    /// Sends a six-digit code to `email`, creating the account if it's new.
    static func sendCode(to email: String) async throws {
        guard let config = Config.current else { throw Failure.notConfigured }
        let body = ["email": email, "create_user": true] as [String: Any]
        _ = try await post(path: "/auth/v1/otp", body: body, config: config, token: nil)
    }

    /// Exchanges the emailed code for a session.
    static func verifyCode(_ code: String, email: String) async throws -> Session {
        guard let config = Config.current else { throw Failure.notConfigured }
        let body: [String: Any] = ["email": email, "token": code, "type": "email"]
        let data = try await post(path: "/auth/v1/verify", body: body, config: config, token: nil)
        return try session(from: data)
    }

    /// Swaps an expiring refresh token for a fresh session.
    static func refresh(_ session: Session) async throws -> Session {
        guard let config = Config.current else { throw Failure.notConfigured }
        let body = ["refresh_token": session.refreshToken]
        let data = try await post(path: "/auth/v1/token?grant_type=refresh_token",
                                  body: body, config: config, token: nil)
        return try self.session(from: data)
    }

    private static func session(from data: Data) throws -> Session {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let access = json["access_token"] as? String,
            let refresh = json["refresh_token"] as? String,
            let user = json["user"] as? [String: Any],
            let id = user["id"] as? String
        else { throw Failure.decoding }

        let lifetime = (json["expires_in"] as? TimeInterval) ?? 3600
        return Session(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date.now.addingTimeInterval(lifetime),
            userID: id,
            email: (user["email"] as? String) ?? ""
        )
    }

    // MARK: - REST

    /// Upsert rows into a table. `onConflict` names the primary key columns so
    /// re-pushing an unchanged row updates rather than erroring.
    ///
    /// Takes pre-encoded JSON rather than `[[String: Any]]` because a
    /// dictionary of `Any` is not `Sendable` and cannot cross an actor boundary
    /// — Swift 6 flags that as the data race it is. The caller encodes on its
    /// own actor; `Data` travels safely.
    static func upsert(rowsJSON: Data, into table: String,
                       onConflict: String, session: Session) async throws {
        guard let config = Config.current else { throw Failure.notConfigured }

        var request = URLRequest(url: config.url.appendingPathComponent("rest/v1/\(table)"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal",
                         forHTTPHeaderField: "Prefer")
        request.url = request.url?.appending(queryItems: [
            URLQueryItem(name: "on_conflict", value: onConflict)
        ])
        request.httpBody = rowsJSON

        _ = try await send(request)
    }

    /// Rows changed since `since`, oldest first so a partial sync can resume.
    /// Returns raw JSON for the same `Sendable` reason as `upsert`; the caller
    /// decodes on its own actor.
    static func fetchChanged(from table: String, since: Date?, session: Session) async throws -> Data {
        guard let config = Config.current else { throw Failure.notConfigured }

        var items = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "updated_at.asc"),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        if let since {
            items.append(URLQueryItem(name: "updated_at",
                                      value: "gt.\(SupabaseDate.string(from: since))"))
        }

        var request = URLRequest(url: config.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: items))
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        return try await send(request)
    }

    // MARK: - Edge Functions

    /// Calls an Edge Function as the signed-in user.
    ///
    /// Functions are where anything needing a secret lives — the app never
    /// holds a key it shouldn't. `Data` in and out for the same `Sendable`
    /// reason as `upsert`.
    static func invoke(function: String, bodyJSON: Data,
                       session: Session, timeout: TimeInterval = 12) async throws -> Data {
        guard let config = Config.current else { throw Failure.notConfigured }

        var request = URLRequest(url: config.url.appendingPathComponent("functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyJSON
        request.timeoutInterval = timeout

        return try await send(request)
    }

    // MARK: - Plumbing

    private static func post(path: String, body: [String: Any],
                             config: Config, token: String?) async throws -> Data {
        var request = URLRequest(url: config.url.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["msg"] ?? $0["message"] ?? $0["error_description"]) as? String }
                ?? String(data: data, encoding: .utf8)
                ?? ""
            throw Failure.http(http.statusCode, message)
        }
        return data
    }
}

/// Postgres `timestamptz` round-trips through fractional-second ISO8601.
///
/// `ISO8601DateFormatter` isn't `Sendable`, so a shared static instance is
/// global mutable state that Swift 6 rejects — and it genuinely isn't safe to
/// use from two tasks at once. Formatters are cheap; build one per call.
enum SupabaseDate {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Accepts both fractional and whole-second forms — Postgres emits either
    /// depending on the stored precision.
    static func parse(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
