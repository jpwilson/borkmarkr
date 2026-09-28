import XCTest
@testable import borkmarkr

/// oEmbed parsing, against the platforms' published sample responses.
final class LinkPreviewTests: XCTestCase {
    func testTikTokGivesCaptionCreatorAndCover() throws {
        let json = #"""
        {"version":"1.0","type":"video","title":"Scramble up ur name & I’ll try to guess it😍❤️ #foryoupage #petsoftiktok #aesthetic","author_url":"https://www.tiktok.com/@scout2015","author_name":"Scout, Suki & Stella","thumbnail_width":576,"thumbnail_height":1024,"thumbnail_url":"https://p16-sign.tiktokcdn-us.com/obj/cover.jpeg","provider_name":"TikTok","author_unique_id":"scout2015","embed_product_id":"6718335390845095173"}
        """#
        let result = try XCTUnwrap(LinkPreview.parseOEmbed(Data(json.utf8), platform: .tiktok))
        XCTAssertEqual(result.author, "@scout2015")
        XCTAssertEqual(result.imageURL?.host, "p16-sign.tiktokcdn-us.com")
        XCTAssertTrue(result.title?.hasPrefix("Scramble up ur name") == true)
        // Hashtags reach the categoriser through the description.
        XCTAssertTrue(result.description?.contains("#petsoftiktok") == true)
    }

    func testXGivesPostTextHandleAndDate() throws {
        let json = #"""
        {"url":"https://x.com/jack/status/20","author_name":"jack","author_url":"https://x.com/jack","html":"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">just setting up my twttr &amp; more<br>second line</p>&mdash; jack (@jack) <a href=\"https://x.com/jack/status/20?ref_src=twsrc%5Etfw\">March 21, 2006</a></blockquote>\n\n","type":"rich","provider_name":"X","version":"1.0"}
        """#
        let result = try XCTUnwrap(LinkPreview.parseOEmbed(Data(json.utf8), platform: .x))
        XCTAssertEqual(result.author, "@jack")
        XCTAssertEqual(result.description, "just setting up my twttr & more\nsecond line")
        XCTAssertNil(result.imageURL)
        let posted = try XCTUnwrap(result.publishedAt)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: posted)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2006, 3, 21])
        // The card turns this back into the post text, as it does X's og:title.
        XCTAssertEqual(SavedContent.title(result.title ?? "", body: nil, platform: "x"),
                       "just setting up my twttr & more second line")
    }

    func testGarbageIsNotAPreview() {
        XCTAssertNil(LinkPreview.parseOEmbed(Data("<html>login</html>".utf8), platform: .tiktok))
        XCTAssertNil(LinkPreview.parseOEmbed(Data(#"{"html":"<div></div>"}"#.utf8), platform: .x))
    }
}

/// The "Save a link" shortcut and the share sheet make the same bork.
final class SaveLinkIntentTests: XCTestCase {
    func testFindsThePostLinkInCopiedText() {
        XCTAssertEqual(SaveLinkIntent.link(in: "https://www.tiktok.com/@physio.jen/video/1")?.host, "www.tiktok.com")
        XCTAssertEqual(SaveLinkIntent.link(in: "  https://x.com/jack/status/20 \n")?.path, "/jack/status/20")
        XCTAssertEqual(SaveLinkIntent.link(in: "Hip flow for runners 🔥 https://www.instagram.com/reel/C9x/?igsh=abc")?.path, "/reel/C9x")
        XCTAssertNil(SaveLinkIntent.link(in: "no link here"))
        XCTAssertNil(SaveLinkIntent.link(in: "mailto:someone@example.com"))
    }

    func testHandedOverDraftIsWhatTheShareSheetQueues() {
        let url = URL(string: "https://www.tiktok.com/@physio.jen/video/1")!
        let draft = BookmarkDraft.handedOver(url: url, caption: nil)
        XCTAssertEqual(draft.platform, .tiktok)
        XCTAssertEqual(draft.kind, .clip)
        XCTAssertEqual(draft.title, Categorizer.fallbackTitle(for: url))
        XCTAssertEqual(draft.author, Categorizer.fallbackAuthor(for: url))
        XCTAssertTrue(draft.isUnread)
        XCTAssertNil(draft.text)

        let post = BookmarkDraft.handedOver(url: URL(string: "https://x.com/jack/status/20")!,
                                            caption: "just setting up my twttr https://x.com/jack/status/20")
        XCTAssertEqual(post.text, ShareInput.cleanBody("just setting up my twttr https://x.com/jack/status/20"))
    }
}
