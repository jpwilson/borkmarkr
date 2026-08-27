import Foundation

/// Fetches real title, author and thumbnail for a link.
///
/// This is what turns a brk from a URL slug into a card. Before this, an X post
/// saved as `x.com/user/status/123` got the title **"Status"** — the last
/// readable path component — which is worse than useless.
///
/// Three sources, cheapest first:
///
/// 1. **oEmbed** — YouTube and Vimeo publish a documented JSON endpoint with
///    title, author and thumbnail. No key, no scraping, explicitly for this.
/// 2. **Open Graph** — most of the web, including many social pages, ships
///    `og:title` / `og:image` / `og:description` in the first few KB of HTML.
/// 3. **Slug fallback** — what we had, now the last resort rather than the
///    only resort.
///
/// **What doesn't work, honestly.** Instagram and TikTok now gate their oEmbed
/// endpoints behind app review, and both serve a login wall to unauthenticated
/// requests — so those return no metadata and keep the gradient cover. X is
/// similar for most posts. Nothing here scrapes past a login or pretends to be
/// a browser; that would break their terms and would be fragile anyway. The
/// honest position is: good previews where the platform publishes them,
/// graceful gradients where it doesn't.
enum LinkPreview {

    struct Result: Sendable {
        var title: String?
        var author: String?
        var imageURL: URL?
        var durationSeconds: Int?
        var publishedAt: Date?
    }

    /// Only the first 64KB is read — Open Graph tags live in `<head>`, and some
    /// pages are many megabytes.
    private static let maxBytes = 64 * 1024
    private static let timeout: TimeInterval = 8

    static func fetch(for url: URL) async -> Result {
        // oEmbed is great for title/thumb on YouTube, but it has no upload
        // date. Merge with Open Graph / JSON-LD so "posted" can be filled in.
        let oembed = await fetchOEmbed(for: url)
        let og = await fetchOpenGraph(for: url)
        var result = oembed ?? og ?? Result()
        if result.title == nil { result.title = og?.title }
        if result.author == nil { result.author = og?.author }
        if result.imageURL == nil { result.imageURL = og?.imageURL }
        if result.durationSeconds == nil { result.durationSeconds = og?.durationSeconds }
        if result.publishedAt == nil { result.publishedAt = og?.publishedAt }
        return result
    }

    // MARK: - oEmbed

    private static func oembedEndpoint(for url: URL) -> URL? {
        let encoded = url.absoluteString.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? ""
        switch Platform.detect(from: url) {
        case .youtube, .shorts:
            return URL(string: "https://www.youtube.com/oembed?format=json&url=\(encoded)")
        default:
            return nil
        }
    }

    private static func fetchOEmbed(for url: URL) async -> Result? {
        guard let endpoint = oembedEndpoint(for: url) else { return nil }
        guard let data = try? await load(endpoint),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var result = Result()
        result.title = (json["title"] as? String)?.trimmed
        if let name = (json["author_name"] as? String)?.trimmed, !Platform.isSiteName(name) {
            result.author = name
        }
        if let thumb = json["thumbnail_url"] as? String { result.imageURL = URL(string: thumb) }
        return result.title == nil ? nil : result
    }

    // MARK: - Open Graph

    private static func fetchOpenGraph(for url: URL) async -> Result? {
        guard let data = try? await load(url),
              let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        var result = Result()
        result.title = meta(in: html, property: "og:title")
            ?? meta(in: html, property: "twitter:title")
            ?? titleTag(in: html)
        let site = meta(in: html, property: "og:site_name")
        let pageAuthor = meta(in: html, property: "author")
        if let pageAuthor, !Platform.isSiteName(pageAuthor) {
            result.author = pageAuthor
        } else if let site, !Platform.isSiteName(site) {
            result.author = site
        }
        if let image = meta(in: html, property: "og:image")
            ?? meta(in: html, property: "twitter:image") {
            result.imageURL = URL(string: image, relativeTo: url)?.absoluteURL
        }
        if let seconds = meta(in: html, property: "og:video:duration"), let value = Int(seconds) {
            result.durationSeconds = value
        }
        result.publishedAt = publishedDate(in: html)
        return (result.title == nil && result.imageURL == nil && result.publishedAt == nil) ? nil : result
    }

    /// article:published_time, JSON-LD uploadDate / datePublished.
    /// Instagram and TikTok almost never emit these to an anonymous fetch.
    private static func publishedDate(in html: String) -> Date? {
        let metaKeys = [
            "article:published_time",
            "og:article:published_time",
            "datePublished",
            "pubdate",
        ]
        for key in metaKeys {
            if let raw = meta(in: html, property: key), let date = parseDate(raw) {
                return date
            }
        }
        let jsonKeys = [
            "\"uploadDate\"\\s*:\\s*\"([^\"]+)\"",
            "\"datePublished\"\\s*:\\s*\"([^\"]+)\"",
        ]
        for pattern in jsonKeys {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, range: range),
               match.numberOfRanges > 1,
               let captured = Range(match.range(at: 1), in: html),
               let date = parseDate(String(html[captured])) {
                return date
            }
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(trimmed.prefix(10)))
    }

    /// Deliberately a regex rather than a full HTML parse: we want four tags
    /// from the head of a document that is often malformed, and pulling in a
    /// parser for that is not a good trade.
    private static func meta(in html: String, property: String) -> String? {
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(property)[\"'][^>]+content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(property)[\"']",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, range: range),
               match.numberOfRanges > 1,
               let captured = Range(match.range(at: 1), in: html) {
                return String(html[captured]).decodedHTMLEntities.trimmed
            }
        }
        return nil
    }

    private static func titleTag(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]+)</title>",
                                                   options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[captured]).decodedHTMLEntities.trimmed
    }

    // MARK: - Networking

    private static func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        // Identify honestly. Spoofing a browser UA to get past a block is both
        // a terms violation and something that silently breaks.
        request.setValue("bookmarker/0.1 (link preview)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        var data = Data()
        data.reserveCapacity(maxBytes)
        for try await byte in bytes {
            data.append(byte)
            if data.count >= maxBytes { break }
        }
        return data
    }
}

private extension String {
    var trimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Titles routinely arrive as `Fitness &amp; Health &#8212; Guide`, and
    /// Instagram in particular emits hex entities: `&#x201c;I&#x2019;m
    /// stronger&#x201d;`. Handling only the named set left that raw on screen.
    ///
    /// So: named entities first, then *any* numeric (`&#8217;`) or hex
    /// (`&#x2019;`) reference by code point, rather than an ever-growing lookup
    /// table that's always missing the one you just hit.
    var decodedHTMLEntities: String {
        var out = self
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                     "&apos;": "'", "&nbsp;": " ", "&hellip;": "…",
                     "&mdash;": "—", "&ndash;": "–", "&rsquo;": "’",
                     "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”"]
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }

        guard out.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#([xX]?)([0-9a-fA-F]+);")
        else { return out }

        // Replace back-to-front so earlier ranges stay valid.
        let range = NSRange(out.startIndex..<out.endIndex, in: out)
        for match in regex.matches(in: out, range: range).reversed() {
            guard
                let full = Range(match.range, in: out),
                let prefixRange = Range(match.range(at: 1), in: out),
                let digitsRange = Range(match.range(at: 2), in: out)
            else { continue }

            let isHex = !out[prefixRange].isEmpty
            let digits = String(out[digitsRange])
            guard
                let value = UInt32(digits, radix: isHex ? 16 : 10),
                let scalar = Unicode.Scalar(value)
            else { continue }

            out.replaceSubrange(full, with: String(Character(scalar)))
        }
        return out
    }
}
