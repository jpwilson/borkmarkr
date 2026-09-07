import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/topic-share-tests Core/Copy.swift Core/TopicShare.swift Scripts/test_topic_share.swift`
///
/// The share message is the only part of the app a stranger sees before they
/// have the app, so its failure mode is not a crash — it is being ignored.
/// These checks are the shape of the thing: titles only and never a caption in
/// full, ten of them newest first, an honest count, "+ N more", and links that
/// are still links when they land in Messages.

@main
enum TopicShareTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        func day(_ offset: Int) -> Date {
            Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(Double(offset) * 86_400)
        }
        func item(_ title: String, _ url: String, _ offset: Int) -> TopicShare.Item {
            TopicShare.Item(title: title, url: url, savedAt: day(offset))
        }

        // ── The heading and the count line ────────────────────────────────
        expect(TopicShare.heading(topic: "Fitness") == "Fitness", "no subtopic, no separator")
        expect(
            TopicShare.heading(topic: "Fitness", subtopic: "Strength") == "Fitness › Strength",
            "a selected subtopic is named in the heading"
        )
        expect(
            TopicShare.heading(topic: "Fitness", subtopic: "  ") == "Fitness",
            "a blank subtopic is no subtopic"
        )
        expect(
            TopicShare.countLine(topic: "Fitness", subtopic: "Strength", count: 8)
                == "Fitness › Strength — 8 borks I saved with bookmarker",
            "the count line reads as a person wrote it"
        )
        expect(
            TopicShare.countLine(topic: "Fitness", count: 1) == "Fitness — 1 bork I saved with bookmarker",
            "one bork is not 1 borks"
        )

        // ── Ordering: newest first, deterministically ─────────────────────
        let mixed = [
            item("Oldest", "https://example.com/a", -30),
            item("Newest", "https://example.com/b", -1),
            item("Middle", "https://example.com/c", -10),
        ]
        expect(
            TopicShare.newestFirst(mixed).map(\.title) == ["Newest", "Middle", "Oldest"],
            "most recently saved first"
        )
        let sameDay = [
            item("Beta", "https://example.com/b", -4),
            item("Alpha", "https://example.com/a", -4),
        ]
        expect(
            TopicShare.newestFirst(sameDay).map(\.title) == ["Alpha", "Beta"],
            "two saved in the same second still order the same way every time"
        )

        // ── Truncation: a caption is not a title ──────────────────────────
        let caption = "This 12 minute mobility routine completely changed how my hips feel after long runs and I cannot recommend it enough honestly"
        let cut = TopicShare.shortTitle(caption)
        expect(cut.count <= TopicShare.titleLimit + 1, "a caption is cut to roughly one line")
        expect(cut.hasSuffix("…"), "a cut title says it was cut")
        expect(!cut.hasSuffix(" …"), "no space before the ellipsis")
        expect(!cut.dropLast().hasSuffix("hone"), "the cut lands on a word, not inside one")
        expect(
            TopicShare.shortTitle("Short enough") == "Short enough",
            "a title that fits is left alone"
        )
        expect(
            TopicShare.shortTitle("Two\nlines   and  spaces") == "Two lines and spaces",
            "newlines and runs of whitespace collapse — captions arrive with both"
        )
        expect(
            TopicShare.shortTitle("Averyverylongsingleunbrokenwordthatgoesonandonandonandonandonandonandonandonforever").hasSuffix("…"),
            "a title with no word boundary is still cut"
        )

        // ── Links: short where short still works ──────────────────────────
        expect(
            TopicShare.shortLink("https://www.instagram.com/reel/C8xhamstring") == "instagram.com/reel/C8xhamstring",
            "the scheme and www. come off — Messages still detects the rest"
        )
        expect(
            TopicShare.shortLink("https://example.com/a/") == "example.com/a",
            "a trailing slash comes off"
        )
        expect(
            TopicShare.shortLink("https://www.youtube.com/watch?v=protein30") == nil,
            "a query carries the identity, so that link is never shortened"
        )
        expect(
            TopicShare.shortLink("https://example.com/page#section") == nil,
            "a fragment is not thrown away either"
        )
        expect(
            TopicShare.shortLink("https://example.com/" + String(repeating: "x", count: 80)) == nil,
            "a path too long to fit is not truncated into a dead link"
        )
        expect(TopicShare.shortLink("not a url at all") == nil, "junk is not a link")
        expect(
            TopicShare.linkLine("https://www.youtube.com/watch?v=protein30")
                == "https://www.youtube.com/watch?v=protein30",
            "what cannot be shortened is printed whole, so it stays tappable"
        )
        expect(
            TopicShare.linkLine("https://www.instagram.com/reel/C8xhamstring") == "instagram.com/reel/C8xhamstring",
            "what can be shortened is"
        )
        expect(TopicShare.footer == "bookmarker.lol/get", "the footer is shortened by the same rule")
        expect(TopicShare.getURL == "https://bookmarker.lol/get", "and points at the install page")

        // ── displayURL: the card, where nothing is tappable ───────────────
        expect(
            TopicShare.displayURL("https://www.youtube.com/watch?v=protein30") == "youtube.com/watch?…",
            "the card shows a query as an ellipsis rather than a parameter dump"
        )
        let long = TopicShare.displayURL("https://example.com/" + String(repeating: "x", count: 80))
        expect(long.count == TopicShare.linkLimit && long.hasSuffix("…"), "the card's link always fits")

        // ── The whole message ─────────────────────────────────────────────
        let thirteen = (1...13).map { index in
            item("Bork number \(index)", "https://example.com/\(index)", -index)
        }
        let message = TopicShare.message(topic: "Fitness", subtopic: "Strength", items: thirteen)
        let lines = message.components(separatedBy: "\n")

        expect(lines.first == "Fitness › Strength — 13 borks I saved with bookmarker",
               "the count is the whole slice, not the ten that got listed")
        expect(lines[1].isEmpty, "a blank line under the heading")
        expect(lines[2] == "1. Bork number 1", "the newest bork is number 1")
        expect(lines[3] == "   example.com/1", "its link is indented under it")
        expect(message.contains("10. Bork number 10"), "ten borks are listed")
        expect(!message.contains("11. "), "and no more than ten")
        expect(message.contains("\n+ 3 more"), "the rest are counted, not printed")
        expect(lines.last == "bookmarker.lol/get", "the last line is where to get the app")
        expect(lines[lines.count - 2].isEmpty, "with a blank line above it")
        expect(
            message.count < 700,
            "the whole thing is short enough to read in a chat bubble (\(message.count) chars)"
        )

        // Never a caption, never body text: the message is built from titles
        // and URLs only, so nothing a Bookmark carries in `text` can reach it.
        let captioned = [item(caption, "https://www.instagram.com/reel/abc", -1)]
        let one = TopicShare.message(topic: "Fitness", items: captioned)
        expect(one.contains("1. This 12 minute mobility routine"), "the title leads")
        expect(!one.contains("recommend it enough"), "the tail of a caption never ships")
        expect(one.contains("instagram.com/reel/abc"), "the link is there and it is short")
        expect(one.hasPrefix("Fitness — 1 bork I saved with bookmarker"), "one bork reads correctly")
        expect(!one.contains("+ 0 more"), "nothing left over means nothing to say about it")

        let exactlyTen = (1...10).map { item("Bork \($0)", "https://example.com/\($0)", -$0) }
        expect(
            !TopicShare.message(topic: "Fitness", items: exactlyTen).contains("more"),
            "exactly ten borks does not claim there are more"
        )

        let empty = TopicShare.message(topic: "Fitness", items: [])
        expect(empty.hasPrefix("Fitness — 0 borks"), "an empty slice still says something true")
        expect(empty.hasSuffix("bookmarker.lol/get"), "and still says where to get the app")

        expect(TopicShare.cardLimit == 6, "the image card shows six titles")
        expect(TopicShare.listLimit == 10, "the message lists ten")

        print(failures == 0 ? "\nAll topic share checks passed."
                            : "\n\(failures) topic share check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
