import Foundation
import SwiftData

/// One saved item.
///
/// This deviates from the handoff's `SavedItem` in several places. Each change
/// is deliberate — the prototype models 26 fixed sample items, and some of its
/// choices don't survive contact with real data or a future sync layer:
///
/// | Spec | Here | Why |
/// |---|---|---|
/// | `date: 'YYYY-MM-DD'` | `savedAt: Date` | String dates sort wrong across timezones and can't be range-queried. |
/// | `dur: 'M:SS' \| ''` | `durationSeconds: Int?` | The spec encodes "is a video" in whether a *string is empty*. Duration is a quantity; formatting is a view concern. |
/// | `id: 'n' + seq` | content-derived `stableID` | A sequential counter can't dedupe, and collides the moment two devices sync. |
/// | — | `updatedAt`, `deletedAt` | Required for the Supabase sync fast-follow. Adding them later means a migration; adding them now is free. |
/// | — | `searchBlob` | Precomputed lowercase haystack so search is one `contains` instead of six per item per keystroke. |
@Model
final class Bookmark {
    /// Content-derived from the normalised URL, so the same post saved twice —
    /// once from the share sheet, once pasted — is one bookmark.
    @Attribute(.unique) var id: String

    var urlString: String
    var title: String

    /// Handle (`@physio.jane`) for social posts, hostname for web articles.
    var author: String?

    var platformRaw: String
    var kindRaw: String

    var categoryID: String?
    var subcategory: String?
    var tags: [String]

    /// Post body — only populated for X/Threads text posts, and what makes an
    /// item render as a text card rather than a media cover.
    var text: String?

    /// Video length in seconds. `nil` means not a video.
    var durationSeconds: Int?

    var noteText: String?
    var noteDate: Date?

    /// Real thumbnail from oEmbed/Open Graph. Nil until fetched, or forever if
    /// the platform doesn't publish one — the gradient cover is the fallback.
    var imageURLString: String?
    /// When we last tried, so a failed fetch isn't retried on every scroll.
    var previewFetchedAt: Date?

    /// Usage signal. Platform bookmarks are write-only graveyards precisely
    /// because nothing records whether you ever went back to a thing — these
    /// three fields are what make "surface what I actually revisit", "never
    /// opened", and time-of-day insights possible later.
    var openCount: Int = 0
    var lastOpenedAt: Date?

    var savedAt: Date
    var updatedAt: Date

    /// Soft-delete tombstone. Sync needs to know a thing was deleted, not just
    /// find it absent — otherwise the other device re-adds it.
    var deletedAt: Date?

    /// True while the Share Extension has saved this but the app hasn't been
    /// opened since.
    var isUnread: Bool

    /// Lowercased concatenation of every searchable field, maintained on write.
    /// Search then does one substring test per item instead of six.
    private(set) var searchBlob: String

    init(
        url: URL,
        title: String,
        author: String? = nil,
        platform: Platform? = nil,
        kind: ItemKind? = nil,
        categoryID: String? = nil,
        subcategory: String? = nil,
        tags: [String] = [],
        text: String? = nil,
        durationSeconds: Int? = nil,
        noteText: String? = nil,
        noteDate: Date? = nil,
        savedAt: Date = .now,
        isUnread: Bool = false
    ) {
        let resolvedPlatform = platform ?? Platform.detect(from: url)
        self.id = Bookmark.stableID(for: url)
        self.urlString = url.absoluteString
        self.title = title
        self.author = author
        self.platformRaw = resolvedPlatform.rawValue
        self.kindRaw = (kind ?? resolvedPlatform.defaultKind).rawValue
        self.categoryID = categoryID
        self.subcategory = subcategory
        self.tags = tags
        self.text = text
        self.durationSeconds = durationSeconds
        self.noteText = noteText
        self.noteDate = noteDate
        self.savedAt = savedAt
        self.updatedAt = savedAt
        self.deletedAt = nil
        self.isUnread = isUnread
        self.searchBlob = ""
        rebuildSearchBlob()
    }

    // MARK: - Derived

    var url: URL? { URL(string: urlString) }
    var imageURL: URL? { imageURLString.flatMap(URL.init(string:)) }
    var platform: Platform { Platform(rawValue: platformRaw) ?? .web }

    /// True when we've never tried, or tried long enough ago that a retry is
    /// reasonable (pages gain OG tags; CDN thumbnails expire).
    var needsPreview: Bool {
        guard imageURLString == nil else { return false }
        guard let previewFetchedAt else { return true }
        return Date.now.timeIntervalSince(previewFetchedAt) > 60 * 60 * 24 * 7
    }

    func markOpened() {
        openCount += 1
        lastOpenedAt = .now
    }
    var kind: ItemKind { ItemKind(rawValue: kindRaw) ?? .article }
    var category: Topic? { Taxonomy.category(id: categoryID) }
    var hasNote: Bool { !(noteText ?? "").isEmpty }

    /// Text card if there's a post body AND the platform actually carries text
    /// posts. An Instagram caption is not a post body.
    var isTextPost: Bool {
        !(text ?? "").isEmpty && platform.carriesTextPosts
    }

    var isArticle: Bool { kind == .article && !isTextPost }
    var isMedia: Bool { !isTextPost && !isArticle }
    var isVideo: Bool { durationSeconds != nil }

    /// "M:SS" for display. Formatting lives here, not in storage.
    var durationLabel: String? {
        guard let durationSeconds else { return nil }
        let m = durationSeconds / 60, s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var coverHeight: CGFloat { isMedia ? kind.coverHeight : 0 }

    // MARK: - Mutation

    /// Every mutation must go through here (or set `updatedAt` itself) or the
    /// search index and sync clock drift out of date.
    func touch() {
        updatedAt = .now
        rebuildSearchBlob()
    }

    func rebuildSearchBlob() {
        var parts = [title, author ?? "", text ?? "", noteText ?? "", subcategory ?? ""]
        parts.append(contentsOf: tags)
        if let category { parts.append(category.name) }
        parts.append(platform.name)
        parts.append(urlString)
        searchBlob = parts
            .joined(separator: " ")
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    // MARK: - Identity

    /// Normalises a URL so trivially-different links to the same post collide.
    ///
    /// Share sheets are the main source of accidental duplicates: Instagram
    /// appends `igshid`, X appends `s` and `t`, everything appends `utm_*`.
    static func stableID(for url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var host = comps?.host?.lowercased() ?? ""
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }
        comps?.host = host
        comps?.scheme = "https"
        comps?.fragment = nil
        comps?.port = nil

        let junk: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "igshid", "igsh", "si", "s", "t", "fbclid", "gclid", "ref", "ref_src",
            "ref_url", "feature", "app", "is_from_webapp", "sender_device", "_r", "_t",
        ]
        if let items = comps?.queryItems {
            let kept = items
                .filter { !junk.contains($0.name.lowercased()) }
                .sorted { $0.name < $1.name }   // order shouldn't change identity
            comps?.queryItems = kept.isEmpty ? nil : kept
        }

        var path = comps?.path ?? ""
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        comps?.path = path

        return comps?.url?.absoluteString ?? url.absoluteString
    }
}

/// A curated set of saves. Scaffolding for the friend-feed fast-follow — the
/// model exists and the You screen lists collections, but sharing to other
/// people is deliberately not wired up yet.
@Model
final class BookmarkCollection {
    @Attribute(.unique) var id: String
    var name: String
    var categoryID: String?
    var bookmarkIDs: [String]
    var visibilityRaw: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(name: String, categoryID: String? = nil, bookmarkIDs: [String] = [], visibility: CollectionVisibility = .privateOnly) {
        self.id = UUID().uuidString
        self.name = name
        self.categoryID = categoryID
        self.bookmarkIDs = bookmarkIDs
        self.visibilityRaw = visibility.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    var visibility: CollectionVisibility {
        CollectionVisibility(rawValue: visibilityRaw) ?? .privateOnly
    }

    var category: Topic? { Taxonomy.category(id: categoryID) }
    var count: Int { bookmarkIDs.count }
}

enum CollectionVisibility: String, Codable, CaseIterable, Sendable {
    case privateOnly = "private"
    case people
    case publicLink = "public"

    var label: String {
        switch self {
        case .privateOnly: "Private"
        case .people: "Shared"
        case .publicLink: "Public link"
        }
    }

    var symbol: String {
        switch self {
        case .privateOnly: "lock.fill"
        case .people: "person.2.fill"
        case .publicLink: "link"
        }
    }
}
