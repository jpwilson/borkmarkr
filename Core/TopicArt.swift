import Foundation

/// Clay art for the topics you make yourself.
///
/// Browse is a wall of clay scenes because each of the 50 built-in topics
/// ships a bundled `topic{Id}` imageset. A topic you add yourself has no
/// imageset and never can — nobody bundles a picture for "Looksmaxxing"
/// before someone types it — so `ClayArt` fell back to paper and the tile
/// read as a bug next to Marketing and Health.
///
/// So the server draws one, once. `topic-art` renders a scene in the locked
/// house style, stores it in a public bucket and hands back a URL, which
/// lands on `CustomTopic.imageURLString` and renders like a bookmark cover.
///
/// **The key is not in this app.** Same contract as `SmartCategorizer` and
/// `SmartNamer`: an Edge Function holds it, the user's JWT authenticates, and
/// every failure — signed out, no quota, no key configured, server down —
/// leaves the topic exactly as it is today. Art is a decoration; asking for
/// it must never be something a topic waits on.
enum TopicArt {

    /// Don't ask again for a day. The server gives up after three attempts
    /// and says so, but a topic whose art failed for a reason that will fix
    /// itself (offline, quota spent, key not deployed yet) should come back
    /// tomorrow rather than either never or on every Browse appearance.
    static let retryInterval: TimeInterval = 24 * 60 * 60

    /// A day is right when the server has *given up* on a topic. It is far
    /// too long when the failure was the kind that fixes itself — no credit on
    /// the account, the daily quota spent, a timeout — where the picture is
    /// usually there within the hour and the tile sits blank for a day. So a
    /// transient failure is stamped as if it happened most of a day ago, and
    /// the topic comes back after this much instead. (Stamping, rather than a
    /// second stored date, keeps the model unchanged.)
    static let transientRetryInterval: TimeInterval = 60 * 60

    /// The stamp to write after a request, given the server's reason (nil
    /// when the art arrived, or when the server didn't say).
    static func requestStamp(reason: String?, now: Date = .now) -> Date {
        guard let reason else { return now }
        // The server's own "stop asking" answer; everything else may recover.
        if reason == "given-up" { return now }
        return now.addingTimeInterval(transientRetryInterval - retryInterval)
    }

    /// At most this many requests per Browse appearance.
    ///
    /// Backfill is the reason: someone with fifteen blank topics should not
    /// fire fifteen image generations the first time they open Browse. They
    /// fill in over a few visits, oldest first, which is both cheaper and
    /// closer to how the tiles get looked at.
    static let backfillBatch = 3

    /// Mirrors `TOPIC_ID` in supabase/functions/topic-art/index.ts and the
    /// slug half of `CustomTopic.makeID`. Only these are drawable: a built-in
    /// already has bundled art, and the function rejects anything else.
    static func isCustomID(_ id: String) -> Bool {
        guard id.hasPrefix("custom.") else { return false }
        let slug = id.dropFirst("custom.".count)
        guard !slug.isEmpty, slug.first != "-", slug.last != "-" else { return false }
        var previousWasDash = false
        for character in slug {
            if character == "-" {
                if previousWasDash { return false }
                previousWasDash = true
            } else if character.isASCII && (character.isLowercase || character.isNumber) {
                previousWasDash = false
            } else {
                return false
            }
        }
        return true
    }

    /// Whether this topic should be asked about now.
    ///
    /// Pure so the decision is testable without a network or a store: a
    /// custom topic, with no art yet, that we haven't asked about recently.
    static func wants(id: String, hasArt: Bool, requestedAt: Date?, now: Date = .now) -> Bool {
        guard isCustomID(id), !hasArt else { return false }
        guard let requestedAt else { return true }
        return now.timeIntervalSince(requestedAt) >= retryInterval
    }

    /// The topics to ask about this time round, oldest first, capped.
    ///
    /// `created` orders them so the topic you have had longest — and have
    /// therefore been staring at blank the longest — is drawn first.
    static func backfillOrder<T>(_ candidates: [T], id: (T) -> String, hasArt: (T) -> Bool,
                                 requestedAt: (T) -> Date?, created: (T) -> Date,
                                 now: Date = .now, limit: Int = TopicArt.backfillBatch) -> [T] {
        candidates
            .filter { wants(id: id($0), hasArt: hasArt($0), requestedAt: requestedAt($0), now: now) }
            .sorted { created($0) < created($1) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - The call

    private struct Request: Encodable {
        var id: String
        var name: String
    }

    private struct Response: Decodable {
        var url: String?
        var reason: String?
    }

    /// Asks for one topic's art. `nil` means "not this time" for every
    /// reason there is; the caller stamps `artRequestedAt` either way.
    ///
    /// The timeout is long because an image model is slow — the function's
    /// own budget is 60s and there is no point giving up before it does.
    static func fetch(id: String, name: String, session: Supabase.Session?) async -> URL? {
        await fetchOutcome(id: id, name: name, session: session).url
    }

    /// The URL if the art is there, and otherwise the server's reason — which
    /// decides how soon the topic is asked about again (`requestStamp`).
    static func fetchOutcome(id: String, name: String, session: Supabase.Session?) async -> (url: URL?, reason: String?) {
        guard let session, Supabase.isConfigured, isCustomID(id) else { return (nil, "fetch-failed") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return (nil, "given-up") }

        guard
            let body = try? JSONEncoder().encode(Request(id: id, name: trimmed)),
            let data = try? await Supabase.invoke(
                function: "topic-art", bodyJSON: body, session: session, timeout: 75
            ),
            let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return (nil, "fetch-failed") }

        if let raw = decoded.url, let url = URL(string: raw), url.scheme == "https" {
            return (url, nil)
        }
        return (nil, decoded.reason ?? "fetch-failed")
    }
}
