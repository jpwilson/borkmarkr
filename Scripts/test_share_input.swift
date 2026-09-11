import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/share-input-tests Core/Platform.swift Core/Taxonomy.swift Core/Categorizer.swift Core/ShareInput.swift Scripts/test_share_input.swift`
///
/// The Share Extension runs over someone else's app, for under a second, in a
/// process nobody can attach a debugger to on a real share. Everything about
/// it that can be checked without UIKit is checked here: the shapes a host
/// hands a link in, the links that are refused, how a caption becomes a
/// title, and the breadcrumb the app reads back afterwards.

@main
enum ShareInputTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        let reel = "https://www.instagram.com/reel/C9xYz12/?igsh=MWZ1c2Z6Y2Y="

        // ── The shapes a host hands a link in ─────────────────────────────
        // Every one of these is `public.url` from some real app. 1.0.1 took
        // only the first.
        expect(ShareInput.url(from: URL(string: reel)!)?.absoluteString == reel, "a URL payload is taken as-is")
        expect(ShareInput.url(from: NSURL(string: reel)!)?.absoluteString == reel, "an NSURL payload bridges")
        expect(ShareInput.url(from: Data(reel.utf8))?.absoluteString == reel, "UTF-8 bytes under public.url are a link")
        expect(ShareInput.url(from: reel)?.absoluteString == reel, "a String payload is a link")
        expect(ShareInput.url(from: reel as NSString)?.absoluteString == reel, "an NSString payload bridges")
        expect(ShareInput.url(from: "  \(reel)\n")?.absoluteString == reel, "whitespace around a string payload is ignored")
        expect(ShareInput.url(from: "Look at this \(reel) 🔥")?.absoluteString == reel, "a caption sent under public.url still yields its link")
        expect(ShareInput.url(from: nil) == nil, "nil is nil")
        expect(ShareInput.url(from: 42) == nil, "a number is not a link")
        expect(ShareInput.url(from: Data([0xFF, 0xFE])) == nil, "bytes that are not UTF-8 are not a link")
        expect(ShareInput.url(from: "HTTPS://X.com/jp/status/1") != nil, "scheme case does not matter")

        // Instagram's tracking junk stays. The extension is not where identity
        // is decided — `Bookmark.stableID` strips it, and every dedupe path
        // goes through that.
        expect(ShareInput.url(from: URL(string: reel)!)?.query == "igsh=MWZ1c2Z6Y2Y=", "igsh= survives — dedupe is stableID's job, not the extension's")

        // ── Links that are not bookmarks ──────────────────────────────────
        expect(ShareInput.url(from: URL(fileURLWithPath: "/tmp/clip.mov")) == nil, "a file: URL (a movie advertised as public.url) is refused")
        expect(ShareInput.url(from: "file:///private/var/mobile/Media/DCIM/IMG_0001.MOV") == nil, "a file: path as a string is refused too")
        expect(ShareInput.url(from: URL(string: "mailto:hello@bookmarker.lol")!) == nil, "mailto: is refused")
        expect(ShareInput.url(from: URL(string: "tel:+4412345")!) == nil, "tel: is refused")
        expect(ShareInput.url(from: URL(string: "instagram://reel/1")!) == nil, "a custom scheme is refused")
        expect(ShareInput.url(from: "https:///nohost") == nil, "https with no host is refused")

        // ── The link inside a post ────────────────────────────────────────
        expect(ShareInput.firstURL(in: "Check this out https://x.com/jp/status/123")?.absoluteString == "https://x.com/jp/status/123", "a link embedded in text is found")
        expect(ShareInput.firstURL(in: "Great read https://t.co/abc123 https://x.com/jp/status/123")?.host == "x.com", "the post's own link wins over a t.co in its body")
        expect(ShareInput.firstURL(in: "see https://example.com/a and https://example.com/b")?.absoluteString == "https://example.com/a", "with only web links, the first is taken")
        expect(ShareInput.firstURL(in: "Title\nhttps://youtu.be/dQw4w9WgXcQ")?.host == "youtu.be", "YouTube's title-newline-link share is found")
        expect(ShareInput.firstURL(in: "Reel https://www.instagram.com/reel/C9/?igsh=abc 🔥")?.query == "igsh=abc", "a caption's link keeps its query")
        expect(ShareInput.firstURL(in: "This is my bio at sophie.co and vibe.check") == nil, "a bare domain in a caption is not a share of it")
        expect(ShareInput.firstURL(in: "email me hello@bookmarker.lol") == nil, "an email address is not a link")
        expect(ShareInput.firstURL(in: "open file:///tmp/x.mov") == nil, "a file: link in text is refused")
        expect(ShareInput.firstURL(in: "") == nil, "empty text has no link")
        expect(ShareInput.firstURL(in: nil) == nil, "no text has no link")

        // Before the host is asked anything, only the post's own link is
        // trusted. A caption that links a website is not a share of it.
        expect(ShareInput.postURL(in: "Great read https://t.co/abc123 https://x.com/jp/status/123")?.host == "x.com", "an X post's text carries the post's link, and that is taken at once")
        expect(ShareInput.postURL(in: "Title\nhttps://www.youtube.com/watch?v=dQw4w9WgXcQ")?.host == "www.youtube.com", "YouTube's text share carries the video's link")
        expect(ShareInput.postURL(in: "Full routine on my site https://mysite.com/routine") == nil, "a caption linking a website is not the share — the host's public.url is")
        expect(ShareInput.postURL(in: "no links here") == nil, "text without a link has no post link")
        expect(ShareInput.postURL(in: nil) == nil, "no text has no post link")

        // ── Text payloads ─────────────────────────────────────────────────
        expect(ShareInput.text(from: "hello") == "hello", "a String payload is text")
        expect(ShareInput.text(from: NSAttributedString(string: "rich")) == "rich", "an attributed string is its text")
        expect(ShareInput.text(from: Data("bytes".utf8)) == "bytes", "UTF-8 bytes are text")
        expect(ShareInput.text(from: URL(string: "https://a.b/c")!) == "https://a.b/c", "a URL under plain-text is its string")
        expect(ShareInput.text(from: nil) == nil, "nil is nil")

        // ── Titles ────────────────────────────────────────────────────────
        let post = URL(string: "https://x.com/jp/status/123")!
        expect(ShareInput.title(from: "Check this out: https://x.com/jp/status/123", url: post) == "Check this out", "the link, and the colon it hung off, come out of the title")
        expect(ShareInput.title(from: "  Hip mobility in 5 minutes  \n https://www.instagram.com/reel/C9/ ", url: post) == "Hip mobility in 5 minutes", "whitespace and newlines collapse")
        expect(ShareInput.title(from: "https://x.com/jp/status/123", url: post) == Categorizer.fallbackTitle(for: post), "a caption that is only the link falls back to the URL's title")
        expect(ShareInput.title(from: "ok", url: post) == Categorizer.fallbackTitle(for: post), "three characters is not a title")
        expect(ShareInput.title(from: nil, url: post) == Categorizer.fallbackTitle(for: post), "no caption falls back")
        expect(ShareInput.title(from: String(repeating: "word ", count: 60), url: post).count == 140, "a long caption is cut at 140")
        expect(ShareInput.cleanBody("  A real post body  ") == "A real post body", "a body is trimmed")
        expect(ShareInput.cleanBody("ok") == nil, "three characters is not a body")
        expect(ShareInput.cleanBody(nil) == nil, "no body is nothing")

        // ── The breadcrumb ────────────────────────────────────────────────
        let suite = "lol.bookmarker.tests.share-input"
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        expect(ShareOutcome.last(in: defaults) == nil, "no run yet, no breadcrumb")
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        ShareOutcome.record(.timeout, in: defaults, at: when)
        let last = ShareOutcome.last(in: defaults)
        expect(last?.outcome == .timeout && last?.at == when, "a run is read back with its reason and its time")
        ShareOutcome.record(.saved, in: defaults)
        expect(ShareOutcome.last(in: defaults)?.outcome == .saved, "the next run overwrites — one entry, not a log")
        expect(ShareOutcome.last(in: nil) == nil, "no App Group: no breadcrumb, no crash")
        ShareOutcome.record(.noLink, in: nil)
        defaults?.removePersistentDomain(forName: suite)
        expect(ShareOutcome.timeout.isFailure && ShareOutcome.noLink.isFailure && ShareOutcome.couldntSave.isFailure, "a timeout, no link, or a failed write is worth telling the person about")
        expect(!ShareOutcome.saved.isFailure && !ShareOutcome.cancelled.isFailure, "a save, or their own Cancel, is not")

        print(failures == 0 ? "\nAll share input checks passed." : "\n\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
