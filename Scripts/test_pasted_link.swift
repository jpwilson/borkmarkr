import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/pasted-link-tests Core/PastedLink.swift Scripts/test_pasted_link.swift`
///
/// The Add sheet's paste card is one tap that either fills the field with the
/// right link or does nothing visible, so every shape that comes off a real
/// clipboard is worth a line here: a bare link, a link inside a caption, a link
/// with no scheme, and text with no link at all. The `Transferable` half isn't
/// tested — it is two `ProxyRepresentation`s and a struct — but everything it
/// hands to `firstURL` is.

@main
enum PastedLinkTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if condition { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }
        func url(_ raw: String) -> String? { PastedLink.firstURL(in: raw)?.absoluteString }
        func eq(_ raw: String, _ expected: String?, _ message: String) {
            let got = url(raw)
            expect(got == expected, "\(message)\n     expected \(expected ?? "nil")\n     got      \(got ?? "nil")")
        }

        // ── A bare link, which is what "Copy link" writes ──────────────────
        eq("https://www.instagram.com/reel/C8xY/", "https://www.instagram.com/reel/C8xY/", "an Instagram reel link")
        eq("https://x.com/user/status/1234567890", "https://x.com/user/status/1234567890", "an X post link")
        eq("  https://youtu.be/dQw4w9WgXcQ  ", "https://youtu.be/dQw4w9WgXcQ", "surrounding whitespace is trimmed")
        eq("http://example.com/a", "http://example.com/a", "plain http is a web link")
        eq("https://example.com/a?utm_source=x&b=1",
           "https://example.com/a?utm_source=x&b=1",
           "query strings are left exactly as copied — stableID does the normalising")

        // ── No scheme ─────────────────────────────────────────────────────
        eq("instagram.com/p/C8xY", "https://instagram.com/p/C8xY", "a schemeless link gets https")
        eq("www.tiktok.com/@a/video/7", "https://www.tiktok.com/@a/video/7", "www with no scheme")

        // ── A link wrapped in the text the app copied with it ──────────────
        eq("Check this out: https://vimeo.com/12345 — so good",
           "https://vimeo.com/12345",
           "a link inside a caption")
        eq("Loved this https://x.com/a/status/9 via @someone",
           "https://x.com/a/status/9",
           "X's \"via @someone\" tail")
        eq("Recipe\nhttps://example.com/soup\n#dinner",
           "https://example.com/soup",
           "a link on its own line")
        eq("https://first.example.com/a and later https://second.example.com/b",
           "https://first.example.com/a",
           "the first link wins, not the last")
        eq("Read example.com/story first", "http://example.com/story",
           "a schemeless link inside prose is still found")

        // ── Nothing to paste ──────────────────────────────────────────────
        eq("", nil, "empty text has no link")
        eq("   \n  ", nil, "whitespace has no link")
        eq("just some notes to myself", nil, "prose with no link")
        eq("1.5", nil, "a decimal number is not a host")
        eq("v2.0", nil, "a version number is not a host")
        eq("hello", nil, "a bare word is not a host")

        // ── Not every detector match is a bork ────────────────────────────
        eq("mailto:hello@bookmarker.lol", nil, "mailto is not a web link")
        eq("Email hello@bookmarker.lol about it", nil, "a bare email address is not a link")
        eq("ftp://files.example.com/x", nil, "ftp is not a web link")
        eq("example.com:8080/a", "https://example.com:8080/a", "a port is not a scheme")
        eq("Mail hello@bookmarker.lol or see https://bookmarker.lol/help",
           "https://bookmarker.lol/help",
           "the email is skipped and the web link is taken")

        // ── The payload wrapper ───────────────────────────────────────────
        expect(PastedLink(raw: "https://example.com").url?.host == "example.com",
               "a PastedLink exposes its parsed url")
        expect(PastedLink(raw: "nothing here").url == nil, "a PastedLink with no link parses to nil")

        if failures > 0 { print("\n\(failures) failed"); exit(1) }
        print("\nall passed")
    }
}
