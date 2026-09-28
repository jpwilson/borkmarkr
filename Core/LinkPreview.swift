import Foundation

/// Fetches real title, author and thumbnail for a link.
///
/// This is what turns a brk from a URL slug into a card. Before this, an X post
/// saved as `x.com/user/status/123` got the title **"Status"** — the last
/// readable path component — which is worse than useless.
///
/// Three sources, cheapest first:
///
/// 1. **oEmbed** — YouTube, TikTok and X publish a documented JSON endpoint:
///    title or caption, creator, thumbnail (TikTok, YouTube) and post date
///    (X). No key, no login, explicitly for this.
/// 2. **Open Graph** — most of the web, including many social pages, ships
///    `og:title` / `og:image` / `og:description` in the first few KB of HTML.
/// 3. **Slug fallback** — what we had, now the last resort rather than the
///    only resort.
///
/// **What doesn't work, honestly.** Instagram gates its oEmbed endpoint behind
/// app review and serves a login wall to unauthenticated requests, so an
/// Instagram post usually returns no metadata and keeps the gradient cover.
/// (An earlier version of this note said the same of TikTok; TikTok's public
/// oEmbed needs no key and returns the caption, creator and cover.) Nothing
/// here scrapes past a login or pretends to be a browser; that would break
/// their terms and would be fragile anyway. The honest position is: good
/// previews where the platform publishes them, graceful gradients where it
/// doesn't.
enum LinkPreview {

    struct Result: Sendable {
        var title: String?
        var author: String?
        /// `og:description`. On Instagram and TikTok this is the full caption
        /// with its hashtags — the part of a post that says what it is about,
        /// where the title says who posted it. Retained when useful.
        var description: String?
        var imageURL: URL?
        var durationSeconds: Int?
        var publishedAt: Date?
    }

    /// Only the first 64KB is read — Open Graph tags live in `<head>`, and some
    /// pages are many megabytes.
    private static let maxBytes = 64 * 1024
    private static let timeout: TimeInterval = 8

    static func fetch(for url: URL) async -> Result {
        // Both at once: one after the other, each with its own timeout, a
        // login-walled page kept the Add sheet on "Reading the link…" for
        // up to sixteen seconds.
        async let oembedTask = fetchOEmbed(for: url)
        async let ogTask = fetchOpenGraph(for: url)
        let oembed = await oembedTask

        // TikTok's and X's oEmbed say everything their pages would, and those
        // pages are login walls anyway — don't wait on them.
        if let oembed, [.tiktok, .x].contains(Platform.detect(from: url)) {
            return oembed
        }

        // YouTube's oEmbed has no upload date, so it is merged with Open
        // Graph / JSON-LD to fill in "posted".
        let og = await ogTask
        var result = oembed ?? og ?? Result()
        if result.title == nil { result.title = og?.title }
        if result.author == nil { result.author = og?.author }
        if result.description == nil { result.description = og?.description }
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
        case .tiktok:
            return URL(string: "https://www.tiktok.com/oembed?url=\(encoded)")
        case .x:
            return URL(string: "https://publish.x.com/oembed?omit_script=1&dnt=true&url=\(encoded)")
        default:
            return nil
        }
    }

    private static func fetchOEmbed(for url: URL) async -> Result? {
        let platform = Platform.detect(from: url)
        // `vm.tiktok.com/ZT…` and `/t/ZT…` share links carry no video id;
        // oEmbed wants the page they redirect to. Only this request uses it —
        // the saved link, and so the bork's identity, stay as shared.
        let target = platform == .tiktok ? await resolvedShortLink(url) : url
        guard let endpoint = oembedEndpoint(for: target),
              let data = try? await load(endpoint) else { return nil }
        return parseOEmbed(data, platform: platform)
    }

    /// The oEmbed half, separated from the network so it can be tested
    /// against the platforms' published sample responses.
    static func parseOEmbed(_ data: Data, platform: Platform) -> Result? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result = Result()
        let name = (json["author_name"] as? String)?.trimmed

        switch platform {
        case .tiktok:
            // The title *is* the caption, hashtags and all — which is what
            // files a TikTok, so it is the description too.
            let caption = (json["title"] as? String)?.trimmed
            result.title = caption
            result.description = caption
            if let id = (json["author_unique_id"] as? String)?.trimmed {
                result.author = "@" + id
            } else if let name, !Platform.isSiteName(name) {
                result.author = name
            }
            if let thumb = json["thumbnail_url"] as? String { result.imageURL = URL(string: thumb) }
            return (result.title == nil && result.imageURL == nil) ? nil : result

        case .x:
            // No title or image: the post is in `html`, a blockquote of the
            // text, "— Name (@handle)", and a link whose text is the date.
            guard let html = json["html"] as? String,
                  let body = firstCapture(#"<p[^>]*>([\s\S]*?)</p>"#, in: html)
                    .map(plainText)?.trimmed
            else { return nil }
            result.description = body
            let handle = (json["author_url"] as? String)
                .flatMap(URL.init(string:))?.lastPathComponent.trimmed
            result.author = handle.map { "@" + $0 } ?? name
            // Shaped like X's own og:title, which the cards already know how
            // to turn back into the post text.
            result.title = "\(name ?? handle ?? "Post") on X: \"\(body)\""
            if let date = firstCapture(#"<a[^>]*>([A-Z][a-z]+ \d{1,2}, \d{4})</a>\s*</blockquote>"#, in: html) {
                let format = DateFormatter()
                format.locale = Locale(identifier: "en_US_POSIX")
                format.dateFormat = "MMMM d, yyyy"
                result.publishedAt = format.date(from: date)
            }
            return result

        default:
            result.title = (json["title"] as? String)?.trimmed
            if let name, !Platform.isSiteName(name) { result.author = name }
            if let thumb = json["thumbnail_url"] as? String { result.imageURL = URL(string: thumb) }
            return result.title == nil ? nil : result
        }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// Tags out, `<br>` to a newline, entities decoded.
    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodedHTMLEntities
    }

    /// Where a TikTok share link lands. Headers only — the body of the page
    /// is never read.
    private static func resolvedShortLink(_ url: URL) async -> URL {
        let host = url.host?.lowercased() ?? ""
        guard host.hasPrefix("vm.") || host.hasPrefix("vt.") || url.path.hasPrefix("/t/") else { return url }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("bookmarker/0.1 (link preview)", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.bytes(for: request),
              let landed = response.url, landed.path.contains("/video/") || landed.path.contains("/photo/")
        else { return url }
        return landed
    }

    // MARK: - Open Graph

    private static func fetchOpenGraph(for url: URL) async -> Result? {
        guard let data = try? await load(url),
              let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return parse(html: html, base: url)
    }

    /// The Open Graph half, separated from the network so it can be exercised
    /// on macOS against a saved page. `nil` when the page said nothing usable.
    static func parse(html: String, base url: URL) -> Result? {
        var result = Result()
        result.title = meta(in: html, property: "og:title")
            ?? meta(in: html, property: "twitter:title")
            ?? titleTag(in: html)
        result.description = meta(in: html, property: "og:description")
            ?? meta(in: html, property: "twitter:description")
            ?? meta(in: html, property: "description")
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
        return (result.title == nil && result.description == nil && result.imageURL == nil && result.publishedAt == nil) ? nil : result
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
