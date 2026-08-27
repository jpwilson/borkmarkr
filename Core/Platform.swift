import Foundation

/// Sources bookmarker knows about. One of the two browse axes —
/// see `Taxonomy` for the other.
enum Platform: String, Codable, CaseIterable, Sendable {
    case x, instagram, tiktok, youtube, shorts, threads, pinterest, grok, web

    /// Display order used everywhere platforms are listed.
    static let ordered: [Platform] = [.x, .instagram, .tiktok, .youtube, .shorts, .threads, .pinterest, .grok, .web]

    var name: String {
        switch self {
        case .x: "X"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .shorts: "Shorts"
        case .threads: "Threads"
        case .pinterest: "Pinterest"
        case .grok: "Grok"
        case .web: "Web"
        }
    }

    /// Short badge label — the small rounded square on every card.
    var short: String {
        switch self {
        case .x: "X"
        case .instagram: "IG"
        case .tiktok: "TT"
        case .youtube: "YT"
        case .shorts: "SH"
        case .threads: "TH"
        case .pinterest: "PIN"
        case .grok: "GK"
        case .web: "WWW"
        }
    }

    /// Descriptor shown under the name on Browse › Sources.
    var descriptor: String {
        switch self {
        case .x: "Posts & threads"
        case .instagram: "Reels & posts"
        case .tiktok: "Clips"
        case .youtube: "Videos"
        case .shorts: "Short videos"
        case .threads: "Text posts"
        case .pinterest: "Pins & boards"
        case .grok: "Answers & shares"
        case .web: "Articles & pages"
        }
    }

    /// The kind of item this platform produces by default.
    var defaultKind: ItemKind {
        switch self {
        case .tiktok: .clip
        case .instagram: .reel
        case .shorts: .short
        case .youtube: .video
        case .x, .threads: .thread
        case .pinterest: .pin
        case .grok: .article
        case .web: .article
        }
    }

    /// Text posts only render as text cards on X and Threads — an Instagram
    /// caption is not a post body.
    var carriesTextPosts: Bool { self == .x || self == .threads }

    /// Site names that sneak in as "author" from Open Graph. Not a person.
    static func isSiteName(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("formerly twitter") { return true }
        if value == "twitter" || value == "x.com" { return true }
        if value == "youtube shorts" || value == "youtu.be" { return true }
        return ordered.contains { value == $0.name.lowercased() }
    }

    /// Detects the source from the URL's **host**, not a substring of the whole
    /// URL.
    ///
    /// The prototype's `detectPreview` does `url.includes('x.com')` against the
    /// entire lowercased URL, which files `netflix.com`, `max.com` and
    /// `sfx.com` as X, and any URL with "threads" anywhere in its path — e.g.
    /// `reddit.com/r/sewing/comments/threads_vs_cord` — as Threads. Matching
    /// the registrable host fixes that class of bug outright.
    ///
    /// Ordering still matters within YouTube: `/shorts/` must be checked before
    /// falling through to `.youtube`, or every Short files as a full video and
    /// gets the wrong card height.
    static func detect(from url: URL) -> Platform {
        guard var host = url.host?.lowercased() else { return .web }
        for prefix in ["www.", "m.", "mobile.", "vm.", "vt."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }

        let path = url.path.lowercased()

        switch host {
        case "tiktok.com", "tiktok.net":
            return .tiktok
        case "instagram.com", "instagr.am", "ig.me":
            return .instagram
        case "youtube.com", "youtu.be", "music.youtube.com":
            return path.hasPrefix("/shorts/") ? .shorts : .youtube
        case "x.com", "twitter.com", "t.co":
            return .x
        case "threads.net", "threads.com":
            return .threads
        case "pinterest.com", "pin.it":
            return .pinterest
        case "grok.com", "grok.x.ai":
            return .grok
        default:
            // Country domains: instagram.com.br, pinterest.co.uk, x.com.au…
            let labels = host.split(separator: ".")
            if labels.count >= 2 {
                let root = labels[labels.count > 2 ? labels.count - 3 : 0]
                switch root {
                case "tiktok": return .tiktok
                case "instagram": return .instagram
                case "youtube": return path.hasPrefix("/shorts/") ? .shorts : .youtube
                case "twitter": return .x
                case "pinterest": return .pinterest
                default: break
                }
            }
            return .web
        }
    }
}

/// Content type. Drives which card shape an item gets in the masonry feed and
/// how tall its cover is.
enum ItemKind: String, Codable, CaseIterable, Sendable {
    case clip, reel, short, video, thread, pin, article, post

    /// Media cover height in points. 0 means "not a media card".
    var coverHeight: CGFloat {
        switch self {
        case .clip, .reel, .short: 200
        case .video: 118
        case .pin: 176
        case .post: 148
        case .thread, .article: 0
        }
    }
}
