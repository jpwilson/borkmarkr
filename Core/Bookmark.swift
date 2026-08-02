import Foundation
import SwiftData

/// One saved link. Everything except `url` is optional by design — the whole
/// premise is that saving is instant and organising is something you can do
/// later (or never).
@Model
final class Bookmark {
    /// Content-derived so the same link saved twice from different places
    /// collides instead of duplicating.
    @Attribute(.unique) var id: String

    var urlString: String
    var title: String
    var author: String?
    var platformRaw: String

    var categoryID: String?
    var subcategory: String?
    var tags: [String]

    var note: String?
    var noteDate: Date?

    var savedAt: Date
    var isArchived: Bool

    /// Set when the extension saved it and the app hasn't been opened since —
    /// drives the "new since you last looked" affordance in the feed.
    var isUnread: Bool

    init(
        url: URL,
        title: String,
        author: String? = nil,
        platform: Platform? = nil,
        categoryID: String? = nil,
        subcategory: String? = nil,
        tags: [String] = [],
        note: String? = nil,
        noteDate: Date? = nil,
        savedAt: Date = .now,
        isUnread: Bool = false
    ) {
        self.id = Bookmark.stableID(for: url)
        self.urlString = url.absoluteString
        self.title = title
        self.author = author
        self.platformRaw = (platform ?? Platform.detect(from: url)).rawValue
        self.categoryID = categoryID
        self.subcategory = subcategory
        self.tags = tags
        self.note = note
        self.noteDate = noteDate
        self.savedAt = savedAt
        self.isArchived = false
        self.isUnread = isUnread
    }

    var url: URL? { URL(string: urlString) }

    var platform: Platform {
        Platform(rawValue: platformRaw) ?? .web
    }

    var category: Category? { Taxonomy.category(id: categoryID) }

    /// Normalised so `https://x.com/foo/status/1?s=20` and
    /// `https://www.x.com/foo/status/1` are the same bookmark. Tracking params
    /// are the main source of accidental duplicates when saving from a share
    /// sheet.
    static func stableID(for url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var host = comps?.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasPrefix("m.") { host.removeFirst(2) }
        comps?.host = host
        comps?.scheme = "https"
        comps?.fragment = nil

        let junk: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "igshid", "igsh", "si", "s", "t", "fbclid", "gclid", "ref", "ref_src", "ref_url",
        ]
        if let items = comps?.queryItems {
            let kept = items.filter { !junk.contains($0.name.lowercased()) }
            comps?.queryItems = kept.isEmpty ? nil : kept
        }

        var path = comps?.path ?? ""
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        comps?.path = path

        return comps?.url?.absoluteString ?? url.absoluteString
    }
}
