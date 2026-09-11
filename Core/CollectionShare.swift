import Foundation

/// The pure half of sharing a collection from the phone.
///
/// A collection is a server row (`supabase/migrations/0011_shared_collections.sql`
/// gave it a slug and a public page; 0012 gives it an expiry and a way to
/// create one). The phone never keeps a copy — it asks for one — so what this
/// file holds is everything that can be wrong *without* a network: what each
/// expiry choice means in days and in words, what a link looks like and how
/// to read one back, what the share message says, what a collection is called
/// when nobody named it, and what the server's JSON turns into. All of it is
/// pinned by `Scripts/test_collection_share.swift` under `swiftc`, with no
/// simulator and no account. The requests live in `Supabase`; the screens in
/// `App/Screens/CollectSheet.swift` and `App/Screens/CollectionsList.swift`.
enum CollectionShare {

    // MARK: - Expiry

    /// How long a link stays open. The same three choices everywhere they are
    /// offered — the sheet that makes a link, the list that manages one, and
    /// the web app — so a person never meets a fourth.
    enum Expiry: String, CaseIterable, Sendable, Identifiable {
        case never, oneDay, tenDays

        var id: String { rawValue }

        /// What the server is told (`p_expiry_days`). `nil` is never.
        var days: Int? {
            switch self {
            case .never: nil
            case .oneDay: 1
            case .tenDays: 10
            }
        }

        /// The segment.
        var label: String {
            switch self {
            case .never: "Never"
            case .oneDay: "1 day"
            case .tenDays: "10 days"
            }
        }

        /// The sentence under the segments. Says what the choice does, in the
        /// words the list will later use to describe it.
        var explanation: String {
            switch self {
            case .never: "The link stays open until you turn it off."
            case .oneDay: "The link stops working after a day."
            case .tenDays: "The link stops working after ten days."
            }
        }

        /// The choice behind a stored `expires_at`, for the list's expiry
        /// picker. `nil` means the row carries a date none of the three make
        /// — which only the web app or a hand-edited row can produce.
        static func from(days: Int?) -> Expiry? {
            allCases.first { $0.days == days }
        }

        /// When a link made now would close.
        func expiresAt(from now: Date = .now) -> Date? {
            days.map { now.addingTimeInterval(TimeInterval($0) * 86_400) }
        }
    }

    // MARK: - Links

    /// The custom scheme, registered in `project.yml`. Universal links wait
    /// for a round that can change provisioning; the parser already accepts
    /// the `https` form so that round is a plist change, not a code one.
    static let scheme = "bookmarker"
    static let host = "bookmarker.lol"

    /// Where a stranger opens it.
    static func publicURL(slug: String) -> String {
        "https://\(host)/c/\(slug)"
    }

    /// Where the app opens it.
    static func appURL(slug: String) -> String {
        "\(scheme)://c/\(slug)"
    }

    /// The server's rule (`collections_slug_format`), applied before a
    /// request is made so a mangled link fails here with nothing sent.
    static func isValidSlug(_ slug: String) -> Bool {
        (8...16).contains(slug.count) && slug.allSatisfy { slugAlphabet.contains($0) }
    }

    private static let slugAlphabet = Set("abcdefghijklmnopqrstuvwxyz0123456789")

    /// The slug inside a link the app was handed, or `nil` for anything that
    /// is not a collection link.
    ///
    /// Accepts `bookmarker://c/<slug>` and `https://bookmarker.lol/c/<slug>`
    /// (with or without `www.`, a trailing slash, a query or a fragment).
    /// Anything else — another host, a second path segment, a slug the server
    /// would refuse — is `nil`. Case is not folded: the server's regex is
    /// lowercase-only, and the app should open exactly the links the web does.
    static func slug(from url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased() else { return nil }
        let host = (parts.host ?? "").lowercased()
        let segments = parts.path.split(separator: "/").map(String.init)

        let candidate: String?
        switch scheme {
        case Self.scheme:
            // `bookmarker://c/<slug>` — URL parsing makes the `c` the host.
            candidate = host == "c" && segments.count == 1 ? segments[0] : nil
        case "https", "http":
            let ours = host == Self.host || host == "www." + Self.host
            candidate = ours && segments.count == 2 && segments[0] == "c" ? segments[1] : nil
        default:
            candidate = nil
        }
        guard let candidate, isValidSlug(candidate) else { return nil }
        return candidate
    }

    // MARK: - Words

    /// The server's bound on a name (`collections_name_len`).
    static let nameLimit = 80
    /// And on the line under it (`collections_note_len`).
    static let noteLimit = 500

    /// What a collection is called before anyone types: the topic it came
    /// from ("Fitness › Mobility"), or a plain count from the Library.
    static func defaultName(topic: String? = nil, count: Int) -> String {
        if let topic = topic?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty {
            return trimmed(topic, to: nameLimit)
        }
        return "\(Copy.countedBorks(count)) from bookmarker"
    }

    /// A name as it will be sent: whitespace collapsed, cut at the limit.
    static func cleanName(_ raw: String) -> String {
        trimmed(raw.split(whereSeparator: \.isWhitespace).joined(separator: " "), to: nameLimit)
    }

    /// A note as it will be sent, or `nil` when there isn't one.
    static func cleanNote(_ raw: String) -> String? {
        let note = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? nil : trimmed(note, to: noteLimit)
    }

    private static func trimmed(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }

    /// "20 Sep" — the day a link closes. A link lives ten days at most, so the
    /// year is noise; the time of day is a detail nobody plans around.
    static func closingDay(_ date: Date, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
    }

    /// The line under a finished link, and in the message that carries it.
    static func openUntilLine(expiresAt: Date?, locale: Locale = .current) -> String {
        guard let expiresAt else { return "Open until you turn it off." }
        return "Link open until \(closingDay(expiresAt, locale: locale))."
    }

    /// What the share sheet sends. Same voice as `TopicShare`: a name, an
    /// honest count, one link, and — when there is one — the day it closes,
    /// so the person receiving it knows not to save it for next month.
    ///
    ///     Hip rehab — week 1
    ///     8 borks I saved with bookmarker
    ///     https://bookmarker.lol/c/abc123def456
    ///
    ///     Link open until 20 Sep.
    ///
    /// The link is printed whole, not shortened like a topic share's list:
    /// it is the only thing in the message that has to work.
    static func message(name: String, count: Int, url: String,
                        expiresAt: Date?, locale: Locale = .current) -> String {
        var lines = [
            name,
            "\(Copy.countedBorks(count)) I saved with bookmarker",
            url,
        ]
        if let expiresAt {
            lines.append("")
            lines.append(openUntilLine(expiresAt: expiresAt, locale: locale))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Wire: making one

    /// The body of `POST /rest/v1/rpc/collection_create`. Named parameters,
    /// every one present — a missing key would fall to the function's
    /// default, which is the same thing today and a silent change the day
    /// the default moves.
    static func createBody(name: String, note: String?, categoryID: String?,
                           expiry: Expiry, bookmarkIDs: [String]) throws -> Data {
        let body: [String: Any] = [
            "p_name": name,
            "p_note": note ?? NSNull(),
            "p_category_id": categoryID ?? NSNull(),
            "p_expiry_days": expiry.days ?? NSNull(),
            "p_bookmark_ids": bookmarkIDs,
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// What `collection_create` answers with.
    struct Created: Sendable, Equatable {
        let id: String
        let slug: String
        let url: String
        let expiresAt: Date?
        /// How many of the ids the server actually put in. Fewer than were
        /// sent means some never reached the server — say so, never hide it.
        let added: Int

        var appURL: String { CollectionShare.appURL(slug: slug) }
    }

    static func created(from data: Data) throws -> Created {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let slug = json["slug"] as? String
        else { throw Supabase.Failure.decoding }
        return Created(
            id: id,
            slug: slug,
            url: (json["url"] as? String) ?? publicURL(slug: slug),
            expiresAt: date(json["expires_at"]),
            added: (json["added"] as? Int) ?? 0
        )
    }

    // MARK: - Wire: opening one

    /// One bork on a shared page, as `collection_by_slug` describes it. Not a
    /// `Bookmark`: these are somebody else's, and they become yours only
    /// through `collection_save`.
    struct SharedItem: Sendable, Equatable, Identifiable {
        let id: String
        let url: String
        let title: String
        let author: String?
        let platform: String
        let kind: String
        let imageURL: String?
    }

    /// The title as a card shows it: the same rule as `Bookmark.displayTitle`,
    /// for a bork that is not yours and so is never a `Bookmark`. Instagram's
    /// og:title is `Name on Instagram: "caption"`; the caption is the title.
    static func displayTitle(_ raw: String, platform: String) -> String {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard platform == "instagram",
              let range = title.range(of: " on Instagram:", options: .caseInsensitive)
        else { return title }
        let caption = String(title[range.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"“”"))
        if caption.count >= 6 { return caption }
        return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// A collection somebody sent you.
    struct Shared: Sendable, Equatable {
        let id: String
        let name: String
        let note: String?
        let ownerName: String
        let expiresAt: Date?
        let items: [SharedItem]
    }

    /// `nil` is the server's one answer for a wrong slug, a link that was
    /// turned off, a deleted collection and an expired one — it does not say
    /// which, and neither should the screen.
    static func shared(from data: Data) throws -> Shared? {
        // `null` is a bare JSON document, which Foundation refuses by default.
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if object is NSNull { return nil }
        guard let json = object as? [String: Any],
              let id = json["id"] as? String,
              let name = json["name"] as? String
        else { throw Supabase.Failure.decoding }

        let items = ((json["items"] as? [[String: Any]]) ?? []).compactMap { row -> SharedItem? in
            guard let id = row["id"] as? String, let url = row["url"] as? String else { return nil }
            return SharedItem(
                id: id,
                url: url,
                title: (row["title"] as? String) ?? "",
                author: row["author"] as? String,
                platform: (row["platform"] as? String) ?? "web",
                kind: (row["kind"] as? String) ?? "article",
                imageURL: row["image_url"] as? String
            )
        }
        return Shared(
            id: id,
            name: name,
            note: (json["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            ownerName: (json["owner_name"] as? String) ?? "Someone",
            expiresAt: date(json["expires_at"]),
            items: items
        )
    }

    /// What `collection_save` answers with, or `nil` when the link was gone
    /// by the time the button was tapped.
    struct Saved: Sendable, Equatable {
        let added: Int
        let skipped: Int

        /// "8 borks added" / "3 added, 5 were already in your library".
        var line: String {
            if skipped == 0 { return "\(Copy.countedBorks(added)) added to your library." }
            if added == 0 { return "All \(skipped) were already in your library." }
            return "\(added) added, \(skipped) already in your library."
        }
    }

    static func saved(from data: Data) throws -> Saved? {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if object is NSNull { return nil }
        guard let json = object as? [String: Any] else { throw Supabase.Failure.decoding }
        return Saved(added: (json["added"] as? Int) ?? 0, skipped: (json["skipped"] as? Int) ?? 0)
    }

    // MARK: - Wire: your own

    /// The query behind the list. One request, count included, newest change
    /// first — the collection you just made is the one you are looking for.
    static let listQuery =
        "collections?select=id,name,note,slug,visibility,expires_at,updated_at,category_id,collection_items(count)"
        + "&deleted_at=is.null&order=updated_at.desc"

    /// A collection you made, as the list shows it.
    struct Owned: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let note: String?
        let slug: String?
        let visibility: String
        let expiresAt: Date?
        let updatedAt: Date?
        let categoryID: String?
        let count: Int

        var isLinkOn: Bool { visibility == "public" }

        func isExpired(at now: Date = .now) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }

        /// A link that works right now.
        func isOpen(at now: Date = .now) -> Bool {
            isLinkOn && slug != nil && !isExpired(at: now)
        }

        var url: String? { slug.map { CollectionShare.publicURL(slug: $0) } }

        /// One line that says whether the link works, in the same words the
        /// sheet used when it was made.
        func statusLine(now: Date = .now, locale: Locale = .current) -> String {
            if !isLinkOn { return "Link off" }
            guard let expiresAt else { return "Open until you turn it off" }
            if expiresAt <= now { return "Expired \(closingDay(expiresAt, locale: locale))" }
            return "Open until \(closingDay(expiresAt, locale: locale))"
        }
    }

    static func owned(from data: Data) throws -> [Owned] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Supabase.Failure.decoding
        }
        return rows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            // PostgREST spells an aggregate as a one-element array.
            let count = ((row["collection_items"] as? [[String: Any]])?.first?["count"] as? Int) ?? 0
            return Owned(
                id: id,
                name: name,
                note: (row["note"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                slug: row["slug"] as? String,
                visibility: (row["visibility"] as? String) ?? "private",
                expiresAt: date(row["expires_at"]),
                updatedAt: date(row["updated_at"]),
                categoryID: row["category_id"] as? String,
                count: count
            )
        }
    }

    /// Bodies for `PATCH /rest/v1/collections?id=eq.<id>`.
    enum Patch {
        static func visibility(on: Bool) throws -> Data {
            try encode(["visibility": on ? "public" : "private"])
        }

        /// A new closing day counted from now — and, because an expired link
        /// being given more time is a link being turned back on, `public`.
        static func expiry(_ expiry: Expiry, from now: Date = .now) throws -> Data {
            try encode([
                "expires_at": expiry.expiresAt(from: now).map(SupabaseDate.string(from:)) ?? NSNull(),
                "visibility": "public",
            ])
        }

        static func delete(at now: Date = .now) throws -> Data {
            try encode(["deleted_at": SupabaseDate.string(from: now)])
        }

        private static func encode(_ fields: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        }
    }

    /// PostgREST answers a `PATCH` with `return=representation` by echoing the
    /// rows it changed. Zero rows is how row-level security says no, with a
    /// 200 — so it has to be counted, never assumed.
    static func rowsChanged(in data: Data) -> Int {
        ((try? JSONSerialization.jsonObject(with: data)) as? [Any])?.count ?? 0
    }

    // MARK: - Wire: the name on the page

    /// The query and body for the name a shared page prints ("by Jean-Paul").
    static func profileQuery(userID: String) -> String {
        "profiles?id=eq.\(userID)&select=display_name"
    }

    /// The name in a `profiles` row, or `nil` when there is none — an empty
    /// or whitespace name counts as none, because the page treats it so.
    static func displayName(from data: Data) -> String? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let raw = rows.first?["display_name"] as? String else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The server's bound on a display name is only the column type; forty
    /// characters is where a name stops being one.
    static let displayNameLimit = 40

    static func cleanDisplayName(_ raw: String) -> String? {
        let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return name.isEmpty ? nil : trimmed(name, to: displayNameLimit)
    }

    static func displayNameBody(_ name: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["display_name": name])
    }

    // MARK: - Plumbing

    private static func date(_ raw: Any?) -> Date? {
        (raw as? String).flatMap(SupabaseDate.parse)
    }
}
