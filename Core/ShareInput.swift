import Foundation

/// What the Share Extension is handed, turned into a link and a title.
///
/// The extension has one job — take whatever the host app passed over and get
/// a `BookmarkDraft` into the inbox before the person's attention moves on —
/// and every part of that job which does not need UIKit lives here, so it can
/// be compiled and checked on a Mac with `swiftc`
/// (`Scripts/test_share_input.swift`).
///
/// Hosts are inconsistent. `public.url` arrives as a `URL`, an `NSURL`, a
/// `String` or UTF-8 bytes in `Data` depending on the app; X and Threads put
/// the post in `attributedContentText` and sometimes never call back for the
/// provider at all; a movie attachment can conform to `public.url` as a
/// `file:` URL. The extension that shipped in 1.0.1 accepted only
/// `item as? URL`, so any of those read as "No link found" — or, with a
/// provider that never answered, as an extension that had hung.
enum ShareInput {

    // MARK: Links

    /// The link, if a browser could open it. `file:` (a movie the host also
    /// advertises as a URL), `mailto:`, `tel:` and custom schemes are not
    /// bookmarks; they are refused rather than saved as web pages.
    static func webURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// A `public.url` payload as a web link, whatever shape it came in.
    static func url(from payload: Any?) -> URL? {
        switch payload {
        case let url as URL: return webURL(url)
        case let text as String: return url(fromString: text)
        case let data as Data: return String(data: data, encoding: .utf8).flatMap(url(fromString:))
        default: return nil
        }
    }

    /// A `public.plain-text` payload as text.
    static func text(from payload: Any?) -> String? {
        switch payload {
        case let text as String: return text
        case let rich as NSAttributedString: return rich.string
        case let data as Data: return String(data: data, encoding: .utf8)
        case let url as URL: return url.absoluteString
        default: return nil
        }
    }

    /// The link to save out of a caption or a post body.
    ///
    /// Only links written out in full (`https://…`) count. The data detector
    /// also matches bare domains, and an Instagram caption that mentions
    /// "sophie.co" is not a share of sophie.co. When the text has several — an
    /// X post whose body links an article, then the post's own URL — the post
    /// wins: every app that shares a post as text puts the post's link last,
    /// after the body, and the post is what the person tapped Share on.
    static func firstURL(in text: String?) -> URL? {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        let links = detector.matches(in: text, range: whole).compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }
            let written = text[range].lowercased()
            guard written.hasPrefix("http://") || written.hasPrefix("https://") else { return nil }
            return match.url.flatMap(webURL)
        }
        return links.last { Platform.detect(from: $0) != .web } ?? links.first
    }

    /// The post's own link in the text a host handed over with the share —
    /// an X or Threads post, YouTube's "title, newline, link" — when there is
    /// one. Only a link on a platform bookmarker knows counts here: a caption
    /// that links someone's website is not a share of that website, and the
    /// host's `public.url` says what was actually shared. This is read before
    /// the host is asked for anything; `firstURL(in:)` is the fallback after.
    static func postURL(in text: String?) -> URL? {
        guard let url = firstURL(in: text), Platform.detect(from: url) != .web else { return nil }
        return url
    }

    private static func url(fromString text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Meant to be a bare link, but hosts have been seen sending the whole
        // caption under `public.url` — take the link out of it either way.
        if let url = URL(string: trimmed).flatMap(webURL) { return url }
        return firstURL(in: trimmed)
    }

    // MARK: Words

    /// The caption with its links taken out, or a title derived from the URL
    /// when there is nothing else to go on.
    static func title(from caption: String?, url: URL) -> String {
        if let caption {
            let words = caption
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("http") }
            let cleaned = words.joined(separator: " ").trimmingCharacters(in: danglingPunctuation)
            if cleaned.count > 3 { return String(cleaned.prefix(140)) }
        }
        return Categorizer.fallbackTitle(for: url)
    }

    /// The post body, when there is one worth keeping.
    static func cleanBody(_ caption: String?) -> String? {
        guard let caption else { return nil }
        let cleaned = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > 3 ? cleaned : nil
    }

    /// What "Check this out: https://…" leaves behind once the link goes.
    private static let danglingPunctuation = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: ":-–—|,"))
}

/// What the last run of the Share Extension did, left in the App Group so the
/// app can say so. One entry, overwritten on every run — a breadcrumb for
/// "it didn't work" reports from someone who can't screenshot an extension
/// that has already closed, not a log and not analytics.
enum ShareOutcome: String, Sendable {
    case saved, cancelled, timeout, noLink, couldntSave

    static let key = "lastShareOutcome"

    /// The runs worth mentioning in the share guide. A cancel was the person's
    /// own tap and a save speaks for itself.
    var isFailure: Bool { self != .saved && self != .cancelled }

    /// One plain line about what went wrong.
    var explanation: String {
        switch self {
        case .saved: return "It saved"
        case .cancelled: return "You cancelled it"
        case .timeout: return "The other app never handed over the link"
        case .noLink: return "There was no link in what was shared"
        case .couldntSave: return "The link couldn't be written to bookmarker's inbox"
        }
    }

    struct Record: Sendable {
        let outcome: ShareOutcome
        let at: Date
    }

    static func record(_ outcome: ShareOutcome, in defaults: UserDefaults?, at date: Date = .now) {
        defaults?.set(["reason": outcome.rawValue, "at": date], forKey: key)
    }

    static func last(in defaults: UserDefaults?) -> Record? {
        guard let entry = defaults?.dictionary(forKey: key),
              let reason = entry["reason"] as? String,
              let outcome = ShareOutcome(rawValue: reason),
              let at = entry["at"] as? Date
        else { return nil }
        return Record(outcome: outcome, at: at)
    }
}
