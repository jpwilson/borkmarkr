import Foundation

/// Bulk import of saves you already have.
///
/// This is the cold-start fix. The premise of the whole product is that you
/// already have thousands of saved posts you can't find — so the first session
/// shouldn't be "save your first link", it should be "here are the 1,400 things
/// you already saved, now sorted and searchable".
///
/// Every platform is legally required to hand users their own data, and these
/// are the formats those exports actually arrive in. Nothing here scrapes, uses
/// an API key, or touches a login — it reads a file the user downloaded from the
/// platform themselves, which is also why no platform can switch it off.
enum Importer {

    struct Candidate: Identifiable, Hashable, Sendable {
        let url: URL
        var title: String?
        var savedAt: Date?
        var author: String?
        var text: String?
        var id: String { url.absoluteString }
    }

    struct Outcome: Sendable {
        var candidates: [Candidate] = []
        var format: Format?
        var skipped: Int = 0
    }

    enum Format: String, CaseIterable, Sendable {
        case browserBookmarks, xArchive, instagram, tiktok, youtube, plainList

        var label: String {
            switch self {
            case .browserBookmarks: "Browser bookmarks"
            case .xArchive: "X archive"
            case .instagram: "Instagram saved"
            case .tiktok: "TikTok favourites"
            case .youtube: "YouTube / Takeout"
            case .plainList: "List of links"
            }
        }

        /// Shown in the import screen so someone can actually go and get the file.
        var howTo: String {
            switch self {
            case .browserBookmarks:
                "Safari: File → Export → Bookmarks. Chrome: Bookmarks → Bookmark Manager → Export."
            case .xArchive:
                "X → Settings → Your account → Download an archive. Use data/like.js or bookmarks.js."
            case .instagram:
                "Instagram → Settings → Accounts Centre → Your information → Download your information (JSON). Use saved_posts.json."
            case .tiktok:
                "TikTok → Settings → Account → Download your data (JSON). Use user_data.json."
            case .youtube:
                "Google Takeout → YouTube → history or playlists (CSV)."
            case .plainList:
                "Any .txt or .csv with one link per line."
            }
        }
    }

    // MARK: - Entry point

    /// Sniffs the format from the content rather than the filename — exports get
    /// renamed, and `data.json` tells you nothing.
    static func parse(data: Data, filename: String) -> Outcome {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { return Outcome() }

        let lower = filename.lowercased()

        if lower.hasSuffix(".html") || lower.hasSuffix(".htm") || text.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1") {
            return parseBrowserBookmarks(text)
        }
        if text.hasPrefix("window.YTD") {
            return parseXArchive(text)
        }
        if text.contains("saved_saved_media") || text.contains("saved_saved_collection") {
            return parseInstagram(text)
        }
        if text.contains("FavoriteVideoList") || text.contains("\"Favorite Videos\"") {
            return parseTikTok(text)
        }
        if lower.hasSuffix(".csv") {
            return parseCSV(text)
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
            || text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return parseGenericJSON(text)
        }
        return parsePlainList(text)
    }

    // MARK: - Netscape bookmarks (Safari / Chrome / Firefox / Edge)

    /// The universal one. Every browser has exported this same 1990s format for
    /// thirty years, which makes it the single highest-coverage importer.
    private static func parseBrowserBookmarks(_ html: String) -> Outcome {
        var out = Outcome(format: .browserBookmarks)
        let pattern = #"<A\s+HREF="([^"]+)"([^>]*)>([^<]*)</A>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return out
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard
                let hrefRange = Range(match.range(at: 1), in: html),
                let url = normalise(String(html[hrefRange]))
            else { out.skipped += 1; continue }

            var candidate = Candidate(url: url)

            if let titleRange = Range(match.range(at: 3), in: html) {
                candidate.title = String(html[titleRange]).htmlDecoded.nilIfBlank
            }
            if let attrRange = Range(match.range(at: 2), in: html) {
                let attrs = String(html[attrRange])
                if let stamp = attribute("ADD_DATE", in: attrs), let seconds = TimeInterval(stamp) {
                    candidate.savedAt = Date(timeIntervalSince1970: seconds)
                }
            }
            out.candidates.append(candidate)
        }
        return out
    }

    private static func attribute(_ name: String, in attrs: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\(name)=\"([^\"]+)\"", options: .caseInsensitive)
        else { return nil }
        let range = NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)
        guard let match = regex.firstMatch(in: attrs, range: range),
              let captured = Range(match.range(at: 1), in: attrs) else { return nil }
        return String(attrs[captured])
    }

    // MARK: - X archive

    /// `like.js` / `bookmarks.js` are JSON arrays with a JS assignment glued to
    /// the front: `window.YTD.like.part0 = [ … ]`. Strip to the first bracket.
    private static func parseXArchive(_ text: String) -> Outcome {
        var out = Outcome(format: .xArchive)
        guard let start = text.firstIndex(of: "["),
              let data = String(text[start...]).data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return out }

        for entry in array {
            // The payload is nested under whichever key the file is for.
            let payload = (entry["like"] as? [String: Any])
                ?? (entry["tweet"] as? [String: Any])
                ?? (entry["bookmark"] as? [String: Any])
                ?? entry

            let link = (payload["expandedUrl"] as? String)
                ?? (payload["expanded_url"] as? String)
                ?? (payload["tweetId"] as? String).map { "https://x.com/i/status/\($0)" }
                ?? (payload["tweet_id"] as? String).map { "https://x.com/i/status/\($0)" }

            guard let link, let url = normalise(link) else { out.skipped += 1; continue }

            var candidate = Candidate(url: url)
            let body = (payload["fullText"] as? String) ?? (payload["full_text"] as? String)
            candidate.text = body?.nilIfBlank
            // The post body makes a far better title than "i/status/123".
            candidate.title = body.map { String($0.prefix(120)) }?.nilIfBlank
            out.candidates.append(candidate)
        }
        return out
    }

    // MARK: - Instagram

    private static func parseInstagram(_ text: String) -> Outcome {
        var out = Outcome(format: .instagram)
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return out }

        let lists = ["saved_saved_media", "saved_saved_collection"]
            .compactMap { root[$0] as? [[String: Any]] }
            .flatMap { $0 }

        for entry in lists {
            guard let map = entry["string_map_data"] as? [String: Any] else { out.skipped += 1; continue }
            // The key is localised ("Saved on" / "Guardado el"), so take the
            // first value carrying an href rather than matching on the label.
            let hrefEntry = map.values
                .compactMap { $0 as? [String: Any] }
                .first { $0["href"] != nil }

            guard let href = hrefEntry?["href"] as? String, let url = normalise(href) else {
                out.skipped += 1; continue
            }

            var candidate = Candidate(url: url)
            candidate.author = (entry["title"] as? String)?.nilIfBlank.map { "@\($0)" }
            if let stamp = hrefEntry?["timestamp"] as? TimeInterval {
                candidate.savedAt = Date(timeIntervalSince1970: stamp)
            }
            out.candidates.append(candidate)
        }
        return out
    }

    // MARK: - TikTok

    private static func parseTikTok(_ text: String) -> Outcome {
        var out = Outcome(format: .tiktok)
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return out }

        let activity = (root["Activity"] as? [String: Any]) ?? root
        let favourites = (activity["Favorite Videos"] as? [String: Any])?["FavoriteVideoList"] as? [[String: Any]]
        let liked = (activity["Like List"] as? [String: Any])?["ItemFavoriteList"] as? [[String: Any]]

        for entry in (favourites ?? []) + (liked ?? []) {
            let link = (entry["Link"] as? String) ?? (entry["link"] as? String)
            guard let link, let url = normalise(link) else { out.skipped += 1; continue }
            var candidate = Candidate(url: url)
            if let date = entry["Date"] as? String { candidate.savedAt = tiktokDate(date) }
            out.candidates.append(candidate)
        }
        return out
    }

    private static func tiktokDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }

    // MARK: - CSV (Google Takeout and friends)

    private static func parseCSV(_ text: String) -> Outcome {
        var out = Outcome(format: .youtube)
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let header = lines.first else { return out }

        let columns = header.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).lowercased()
        }
        let videoIndex = columns.firstIndex { $0.contains("video id") }
        let urlIndex = columns.firstIndex { $0.contains("url") || $0.contains("link") }
        let titleIndex = columns.firstIndex { $0.contains("title") }

        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
            var link: String?
            if let videoIndex, videoIndex < fields.count, !fields[videoIndex].isEmpty {
                link = "https://www.youtube.com/watch?v=\(fields[videoIndex])"
            } else if let urlIndex, urlIndex < fields.count {
                link = fields[urlIndex]
            }

            guard let link, let url = normalise(link) else { out.skipped += 1; continue }
            var candidate = Candidate(url: url)
            if let titleIndex, titleIndex < fields.count { candidate.title = fields[titleIndex].nilIfBlank }
            out.candidates.append(candidate)
        }
        return out
    }

    // MARK: - Generic

    /// Best-effort over an unknown JSON shape: walk it and take anything that
    /// looks like a link. Covers the long tail of exports without a parser each.
    private static func parseGenericJSON(_ text: String) -> Outcome {
        var out = Outcome(format: .plainList)
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return out }

        var found: [URL] = []
        walk(root, into: &found)
        out.candidates = found.map { Candidate(url: $0) }
        return out
    }

    private static func walk(_ node: Any, into found: inout [URL]) {
        switch node {
        case let string as String:
            if string.hasPrefix("http"), let url = normalise(string) { found.append(url) }
        case let array as [Any]:
            for child in array { walk(child, into: &found) }
        case let dict as [String: Any]:
            for child in dict.values { walk(child, into: &found) }
        default:
            break
        }
    }

    private static func parsePlainList(_ text: String) -> Outcome {
        var out = Outcome(format: .plainList)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return out }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url.flatMap({ normalise($0.absoluteString) }) {
                out.candidates.append(Candidate(url: url))
            }
        }
        return out
    }

    // MARK: - Shared

    /// Rejects junk early so the review screen isn't full of `javascript:` and
    /// `chrome://` rows from a browser export.
    private static func normalise(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http"), let url = URL(string: trimmed), let host = url.host,
              host.contains(".") else { return nil }
        return url
    }

    /// Collapses duplicates using the same identity rule the app saves under, so
    /// importing likes *and* bookmarks from the same archive doesn't double up.
    static func dedupe(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        var out: [Candidate] = []
        for candidate in candidates {
            let id = Bookmark.stableID(for: candidate.url)
            if seen.insert(id).inserted { out.append(candidate) }
        }
        return out
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var htmlDecoded: String {
        var out = self
        for (entity, replacement) in ["&amp;": "&", "&lt;": "<", "&gt;": ">",
                                      "&quot;": "\"", "&#39;": "'", "&nbsp;": " "] {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}
