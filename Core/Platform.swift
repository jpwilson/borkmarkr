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

    /// What to call a post whose page we could not read: "Instagram reel",
    /// "TikTok video". Honest, and recognisable at a glance — the alternative
    /// was a title made from the URL, which for most posts turns an ID into
    /// a fake handle ("@C9xYz12Abc on Instagram").
    func untitledLabel(for url: URL) -> String {
        let path = url.path.lowercased()
        switch self {
        case .instagram:
            if path.contains("/reel") { return "Instagram reel" }
            if path.contains("/stories/") { return "Instagram story" }
            return "Instagram post"
        case .tiktok: return path.contains("/photo/") ? "TikTok photos" : "TikTok video"
        case .youtube: return "YouTube video"
        case .shorts: return "YouTube Short"
        case .x: return "Post on X"
        case .threads: return "Threads post"
        case .pinterest: return "Pinterest pin"
        case .grok: return "Grok answer"
        case .web: return url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? "Saved link"
        }
    }

    /// The account a post belongs to, as `@handle`, when its URL says so.
    ///
    /// This is how people remember a video — "that physio on TikTok" — and
    /// the URL is the one place it is reliably written down for posts whose
    /// page we cannot read (Instagram) or have not read yet. Only paths that
    /// *mean* an account are trusted: `/@x/video/…`, `x.com/x/status/…`,
    /// `instagram.com/x/reel/…`. A bare `/reel/ID` or `/shorts/ID` has no
    /// account in it, and an ID is never passed off as one.
    static func handle(in url: URL) -> String? {
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let first = segments.first else { return nil }

        func clean(_ raw: String) -> String? {
            let name = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            guard !name.isEmpty, name.count <= 40,
                  name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
            return "@" + name
        }

        switch detect(from: url) {
        case .tiktok, .threads, .youtube, .shorts:
            // `/@name/video/…`, `/@name/post/…`, `youtube.com/@name…`
            return first.hasPrefix("@") ? clean(first) : nil
        case .x:
            // `/name/status/ID`. Reserved first segments are pages, not people.
            let reserved: Set<String> = ["i", "home", "search", "hashtag", "intent", "share", "explore", "messages", "notifications", "settings"]
            guard segments.count >= 3, segments[1] == "status",
                  !reserved.contains(first.lowercased()) else { return nil }
            return clean(first)
        case .instagram:
            // `/name/reel/ID` and `/name/p/ID` — the newer share links — and
            // `/stories/name/ID`. Never `/reel/ID`: that ID is not a person.
            if first == "stories", segments.count >= 2 { return clean(segments[1]) }
            let postPaths: Set<String> = ["reel", "reels", "p", "tv"]
            guard segments.count >= 3, postPaths.contains(segments[1]),
                  !postPaths.contains(first) else { return nil }
            return clean(first)
        case .pinterest, .grok, .web:
            return nil
        }
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
