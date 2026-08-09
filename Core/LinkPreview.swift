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
    }

    /// Only the first 64KB is read — Open Graph tags live in `<head>`, and some
    /// pages are many megabytes.
    private static let maxBytes = 64 * 1024
    private static let timeout: TimeInterval = 8

    static func fetch(for url: URL) async -> Result {
        if let oembed = await fetchOEmbed(for: url) { return oembed }
        if let og = await fetchOpenGraph(for: url) { return og }
        return Result()
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
        result.author = (json["author_name"] as? String)?.trimmed
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
        result.author = meta(in: html, property: "og:site_name")
            ?? meta(in: html, property: "author")
        if let image = meta(in: html, property: "og:image")
            ?? meta(in: html, property: "twitter:image") {
            result.imageURL = URL(string: image, relativeTo: url)?.absoluteURL
        }
        if let seconds = meta(in: html, property: "og:video:duration"), let value = Int(seconds) {
            result.durationSeconds = value
        }
        return (result.title == nil && result.imageURL == nil) ? nil : result
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
        request.setValue("borkmarkr/0.1 (link preview)", forHTTPHeaderField: "User-Agent")
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

    /// Titles routinely arrive as `Fitness &amp; Health &#8212; Guide`.
    var decodedHTMLEntities: String {
        var out = self
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                     "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#8217;": "’",
                     "&#8212;": "—", "&#8211;": "–", "&hellip;": "…"]
        for (entity, replacement) in named {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
    }
}
