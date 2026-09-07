import Foundation

/// What "share a topic" actually sends.
///
/// The first version pasted up to fifty `title` + `url` pairs, using whatever
/// the share extension had captured as the title — which for Instagram is the
/// entire caption. In Messages that arrives as a wall of text nobody reads,
/// and the founder's verdict was exactly that: *"it looks terrible, it's just
/// a wall of text; it's not useful."*
///
/// **A share is an invitation, not an archive.** So: titles only, never body
/// text; ten of them, newest first; a count line that says how many there
/// really are; and one link to the app at the end. Someone who wants all four
/// hundred can install it.
///
/// Pure Foundation so `Scripts/test_topic_share.swift` exercises the
/// formatting — truncation, ordering, the count line, "+ N more" — without a
/// store or a simulator.
enum TopicShare {

    /// One bork, reduced to the three things a share needs. A plain value, not
    /// a `Bookmark`, so this file stays testable and free of SwiftData.
    struct Item: Sendable, Equatable {
        let title: String
        let url: String
        let savedAt: Date

        init(title: String, url: String, savedAt: Date) {
            self.title = title
            self.url = url
            self.savedAt = savedAt
        }
    }

    /// How many borks the message lists before it starts counting instead.
    static let listLimit = 10
    /// How many titles fit on the image card without it becoming the same wall
    /// of text in picture form.
    static let cardLimit = 6
    /// Longest a shortened link may be before the real URL is used instead.
    static let linkLimit = 48
    /// Longest a title may be before it is cut. Roughly one line in Messages.
    static let titleLimit = 72

    /// Where the footer points. Kept whole here; `footer` is how it reads.
    static let getURL = "https://bookmarker.lol/get"

    /// `bookmarker.lol/get` — shortened by the same rule as every other link
    /// in the message, so the last line doesn't look like a different app
    /// wrote it.
    static var footer: String { shortLink(getURL) ?? getURL }

    // MARK: Message

    /// "Fitness › Strength", or just "Fitness" when no subtopic is selected.
    static func heading(topic: String, subtopic: String? = nil) -> String {
        guard let subtopic, !subtopic.trimmingCharacters(in: .whitespaces).isEmpty else { return topic }
        return "\(topic) › \(subtopic)"
    }

    /// The first line. Names the slice, says how many are in it, and says who
    /// saved them — `count` is the size of the whole slice, not of the ten
    /// that get listed.
    static func countLine(topic: String, subtopic: String? = nil, count: Int) -> String {
        "\(heading(topic: topic, subtopic: subtopic)) — \(Copy.countedBorks(count)) I saved with bookmarker"
    }

    /// The whole message.
    ///
    ///     Fitness › Strength — 8 borks I saved with bookmarker
    ///
    ///     1. Hip strength for runners
    ///        instagram.com/reel/abc
    ///     2. …
    ///     + 3 more
    ///
    ///     bookmarker.lol/get
    static func message(
        topic: String,
        subtopic: String? = nil,
        items: [Item],
        limit: Int = listLimit
    ) -> String {
        let ordered = newestFirst(items)
        let shown = ordered.prefix(max(0, limit))

        var lines = [countLine(topic: topic, subtopic: subtopic, count: ordered.count), ""]
        for (index, item) in shown.enumerated() {
            lines.append("\(index + 1). \(shortTitle(item.title))")
            lines.append("   \(linkLine(item.url))")
        }
        let remaining = ordered.count - shown.count
        if remaining > 0 { lines.append("+ \(remaining) more") }

        lines.append("")
        lines.append(footer)
        return lines.joined(separator: "\n")
    }

    /// Most recently saved first — the ten worth showing are the ten you most
    /// recently thought were worth keeping. Ties break on title so the same
    /// library always produces the same message.
    static func newestFirst(_ items: [Item]) -> [Item] {
        items.sorted { a, b in
            if a.savedAt != b.savedAt { return a.savedAt > b.savedAt }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    // MARK: Pieces

    /// A title on one line.
    ///
    /// Newlines and runs of whitespace collapse — a caption captured as a
    /// title arrives with both — and anything past `limit` is cut at the last
    /// word boundary in the back half, so the ellipsis never lands mid-word.
    static func shortTitle(_ raw: String, limit: Int = titleLimit) -> String {
        let flattened = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flattened.count > limit, limit > 0 else { return flattened }

        let cut = flattened.prefix(limit)
        if let space = cut.lastIndex(of: " "),
           cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return cut[..<space].trimmingCharacters(in: .whitespaces) + "…"
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The link as it should read: no `https://`, no `www.`, no trailing
    /// slash. `instagram.com/reel/abc` — which Messages, Mail and Notes all
    /// still detect and make tappable.
    ///
    /// Returns `nil` when shortening would change where the link *goes*: a
    /// query string that carries the identity (`youtube.com/watch?v=…`), a
    /// fragment, or a path long enough that it would have to be truncated. A
    /// truncated URL is not a link, and the entire point of sharing is that
    /// the other person can tap it — so those print in full instead.
    static func shortLink(_ raw: String, limit: Int = linkLimit) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.query == nil,
              components.fragment == nil
        else { return nil }

        let candidate = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }

        let short = candidate + path
        return short.count <= limit ? short : nil
    }

    /// The line the message prints under a title: short where short is still a
    /// working link, the real URL where it isn't.
    static func linkLine(_ raw: String, limit: Int = linkLimit) -> String {
        shortLink(raw, limit: limit) ?? raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same link for a surface where nothing is tappable — the image card.
    /// Nothing to protect there, so this one always fits: host + path, cut
    /// with an ellipsis at `limit`.
    static func displayURL(_ raw: String, limit: Int = linkLimit) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return String(trimmed.prefix(limit)) }

        var short = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        short += path
        if components.query != nil { short += "?…" }

        guard short.count > limit, limit > 1 else { return short }
        return String(short.prefix(limit - 1)) + "…"
    }
}
