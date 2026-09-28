import XCTest
import SwiftData
@testable import borkmarkr

/// Who made a saved post, as the cards show it.
final class CreatorTests: XCTestCase {
    private func handle(_ raw: String) -> String? { Platform.handle(in: URL(string: raw)!) }

    func testHandlesComeOnlyFromPathsThatNameAnAccount() {
        XCTAssertEqual(handle("https://www.tiktok.com/@physio.jen/video/7312345678901234567"), "@physio.jen")
        XCTAssertEqual(handle("https://x.com/jack/status/20"), "@jack")
        XCTAssertEqual(handle("https://twitter.com/jack/status/20?s=46"), "@jack")
        XCTAssertEqual(handle("https://www.threads.net/@zuck/post/C1abc"), "@zuck")
        XCTAssertEqual(handle("https://www.instagram.com/dirt.miles/reel/C9xYz12Abc/"), "@dirt.miles")
        XCTAssertEqual(handle("https://www.instagram.com/stories/dirt.miles/3312/"), "@dirt.miles")
        XCTAssertEqual(handle("https://www.youtube.com/@longwaydown"), "@longwaydown")

        // IDs are not people.
        XCTAssertNil(handle("https://www.instagram.com/reel/C9xYz12Abc/"))
        XCTAssertNil(handle("https://www.instagram.com/p/C9xYz12Abc/"))
        XCTAssertNil(handle("https://www.youtube.com/shorts/dQw4w9WgXcQ"))
        XCTAssertNil(handle("https://vm.tiktok.com/ZTabc123/"))
        XCTAssertNil(handle("https://www.tiktok.com/t/ZTabc123/"))
        XCTAssertNil(handle("https://x.com/i/status/20"))
        XCTAssertNil(handle("https://x.com/jack"))
        XCTAssertNil(handle("https://www.pinterest.com/pin/123456/"))
        XCTAssertNil(handle("https://www.nytimes.com/2026/09/01/well/move/hips.html"))
    }

    func testTheSiteIsNotTheCreatorOnSocialPosts() {
        let reel = URL(string: "https://www.instagram.com/reel/C9x/")!
        XCTAssertTrue(Bookmark.isPlaceholderAuthor(nil, url: reel, platform: .instagram))
        XCTAssertTrue(Bookmark.isPlaceholderAuthor("", url: reel, platform: .instagram))
        XCTAssertTrue(Bookmark.isPlaceholderAuthor("instagram.com", url: reel, platform: .instagram))
        XCTAssertTrue(Bookmark.isPlaceholderAuthor("www.instagram.com", url: reel, platform: .instagram))
        XCTAssertTrue(Bookmark.isPlaceholderAuthor("Instagram", url: reel, platform: .instagram))
        XCTAssertTrue(Bookmark.isPlaceholderAuthor("tiktok.com", url: URL(string: "https://vm.tiktok.com/ZT1/")!, platform: .tiktok))
        XCTAssertTrue(Bookmark.isPlaceholderAuthor("youtube.com", url: URL(string: "https://youtube.com/shorts/a")!, platform: .shorts))
        XCTAssertFalse(Bookmark.isPlaceholderAuthor("@dirt.miles", url: reel, platform: .instagram))
        XCTAssertFalse(Bookmark.isPlaceholderAuthor("Sophie Rinkenbach", url: reel, platform: .instagram))

        // On the web, the host is a fine byline.
        let article = URL(string: "https://www.nytimes.com/a")!
        XCTAssertFalse(Bookmark.isPlaceholderAuthor("nytimes.com", url: article, platform: .web))
    }

    @MainActor func testCardsFallBackToTheHandleInTheLink() throws {
        // Models need a loaded container even when they are never saved.
        let container = try ModelContainer(for: Bookmark.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        _ = container
        let tiktok = Bookmark(url: URL(string: "https://www.tiktok.com/@physio.jen/video/1")!,
                              title: "Hip flow", author: "tiktok.com")
        XCTAssertEqual(tiktok.displayAuthor, "@physio.jen")

        let learned = Bookmark(url: URL(string: "https://www.tiktok.com/@physio.jen/video/1")!,
                               title: "Hip flow", author: "Jen Physio")
        XCTAssertEqual(learned.displayAuthor, "Jen Physio")

        let reel = Bookmark(url: URL(string: "https://www.instagram.com/reel/C9x/")!,
                            title: "Reel", author: "instagram.com")
        XCTAssertNil(reel.displayAuthor)

        let article = Bookmark(url: URL(string: "https://www.nytimes.com/a")!, title: "A", author: "nytimes.com")
        XCTAssertEqual(article.displayAuthor, "nytimes.com")
    }
}
