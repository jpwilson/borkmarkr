import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/collection-share-tests Core/Copy.swift Core/Supabase.swift Core/CollectionShare.swift Scripts/test_collection_share.swift`
///
/// The contract between the phone and migration 0012, pinned: what each
/// expiry choice sends, what a link looks like and which links the app will
/// open, what the share message says, what a collection is called when nobody
/// named it, and what the server's JSON turns into on the way back. The
/// network is not here on purpose — these are the parts that can be wrong
/// without one.

@main
enum CollectionShareTests {
    static func main() {
        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }

        let gb = Locale(identifier: "en_GB")
        let us = Locale(identifier: "en_US")
        // 2027-01-15 12:00:00 UTC — a fixed "now" so the closing days are known.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        // ── Expiry ────────────────────────────────────────────────────────
        expect(CollectionShare.Expiry.never.days == nil, "never sends null days")
        expect(CollectionShare.Expiry.oneDay.days == 1, "1 day sends 1")
        expect(CollectionShare.Expiry.tenDays.days == 10, "10 days sends 10")
        expect(CollectionShare.Expiry.allCases.map(\.label) == ["Never", "1 day", "10 days"],
               "the three choices, in order, worded the same everywhere")
        expect(CollectionShare.Expiry.from(days: nil) == .never, "null reads back as never")
        expect(CollectionShare.Expiry.from(days: 10) == .tenDays, "10 reads back as ten days")
        expect(CollectionShare.Expiry.from(days: 3) == nil, "a day count none of the segments make is nil")
        expect(CollectionShare.Expiry.never.expiresAt(from: now) == nil, "never has no closing day")
        expect(CollectionShare.Expiry.tenDays.expiresAt(from: now) == now.addingTimeInterval(10 * 86_400),
               "ten days is ten days from now")

        // ── Links: building ───────────────────────────────────────────────
        expect(CollectionShare.publicURL(slug: "abc123def456") == "https://bookmarker.lol/c/abc123def456",
               "the public link is bookmarker.lol/c/<slug>")
        expect(CollectionShare.appURL(slug: "abc123def456") == "bookmarker://c/abc123def456",
               "the app link is bookmarker://c/<slug>")

        // ── Links: reading ────────────────────────────────────────────────
        func slug(_ raw: String) -> String? {
            URL(string: raw).flatMap(CollectionShare.slug(from:))
        }
        expect(slug("bookmarker://c/abc123def456") == "abc123def456", "the app scheme opens")
        expect(slug("https://bookmarker.lol/c/abc123def456") == "abc123def456", "the public link opens")
        expect(slug("https://www.bookmarker.lol/c/abc123def456/") == "abc123def456",
               "www and a trailing slash are still the same link")
        expect(slug("https://bookmarker.lol/c/abc123def456?utm_source=x#top") == "abc123def456",
               "a query and a fragment are ignored")
        expect(slug("BOOKMARKER://c/abc123def456") == "abc123def456", "the scheme is case-insensitive")
        expect(slug("https://bookmarker.lol/c/2hjuxv1ldzp7") == "2hjuxv1ldzp7", "the demo slug opens")

        expect(slug("bookmarker://c/") == nil, "no slug, no link")
        expect(slug("bookmarker://c/abc") == nil, "too short is refused before anything is sent")
        expect(slug("bookmarker://c/abcdefghijklmnopq") == nil, "seventeen characters is too long")
        expect(slug("bookmarker://c/ABC123DEF456") == nil, "uppercase is not a slug the server would accept")
        expect(slug("bookmarker://c/abc123-ef456") == nil, "a hyphen is not in the alphabet")
        expect(slug("bookmarker://x/abc123def456") == nil, "another path in our scheme is not a collection")
        expect(slug("bookmarker://c/abc123def456/extra") == nil, "a second path segment is refused")
        expect(slug("https://evil.example/c/abc123def456") == nil, "another host is not ours")
        expect(slug("https://bookmarker.lol.evil.example/c/abc123def456") == nil,
               "a host that merely starts with ours is not ours")
        expect(slug("https://bookmarker.lol/get") == nil, "the install page is not a collection")
        expect(slug("https://bookmarker.lol/c/abc123def456/more") == nil, "a deeper path is refused")
        expect(slug("mailto:c@bookmarker.lol") == nil, "another scheme is nothing")

        // ── Names ─────────────────────────────────────────────────────────
        expect(CollectionShare.defaultName(topic: "Fitness › Mobility", count: 8) == "Fitness › Mobility",
               "a topic share is named for the topic")
        expect(CollectionShare.defaultName(topic: "  ", count: 8) == "8 borks from bookmarker",
               "a blank topic is no topic")
        expect(CollectionShare.defaultName(count: 1) == "1 bork from bookmarker", "one bork is not 1 borks")
        let long = String(repeating: "a", count: 100)
        expect(CollectionShare.defaultName(topic: long, count: 1).count == 80,
               "a name is cut at the server's 80")
        expect(CollectionShare.cleanName("  Hip\n rehab   week 1 ") == "Hip rehab week 1",
               "a typed name is one line with single spaces")
        expect(CollectionShare.cleanNote("   ") == nil, "a blank note is no note")
        expect(CollectionShare.cleanNote(" Do the mobility one daily. ") == "Do the mobility one daily.",
               "a note is trimmed")
        expect(CollectionShare.cleanNote(String(repeating: "n", count: 600))?.count == 500,
               "a note is cut at the server's 500")
        expect(CollectionShare.cleanDisplayName("  Jean  Paul ") == "Jean Paul", "a display name is tidied")
        expect(CollectionShare.cleanDisplayName(" \n") == nil, "a blank display name is none")

        // ── Closing day and the line that carries it ──────────────────────
        let closes = CollectionShare.Expiry.tenDays.expiresAt(from: now)!
        let day = utc.component(.day, from: closes)
        expect(CollectionShare.closingDay(closes, locale: gb).contains("\(day)"),
               "the closing day names the day")
        expect(!CollectionShare.closingDay(closes, locale: gb).contains("2027"),
               "and not the year — a link lives ten days at most")
        expect(CollectionShare.openUntilLine(expiresAt: nil) == "Open until you turn it off.",
               "no expiry says so in words")
        expect(CollectionShare.openUntilLine(expiresAt: closes, locale: us).hasPrefix("Link open until "),
               "an expiry gives the day")

        // ── The message ───────────────────────────────────────────────────
        let forever = CollectionShare.message(
            name: "Hip rehab — week 1", count: 8,
            url: "https://bookmarker.lol/c/abc123def456", expiresAt: nil, locale: gb
        )
        expect(forever == """
            Hip rehab — week 1
            8 borks I saved with bookmarker
            https://bookmarker.lol/c/abc123def456
            """, "name, count, link — and nothing about expiry when there is none")

        let closing = CollectionShare.message(
            name: "Hip rehab — week 1", count: 1,
            url: "https://bookmarker.lol/c/abc123def456", expiresAt: closes, locale: gb
        )
        let lines = closing.split(separator: "\n", omittingEmptySubsequences: false)
        expect(lines.count == 5 && lines[3] == "" && lines[4].hasPrefix("Link open until "),
               "an expiry adds a blank line and the closing day")
        expect(lines[1] == "1 bork I saved with bookmarker", "one bork, singular, in the message too")
        expect(closing.contains("https://bookmarker.lol/c/abc123def456"),
               "the link is printed whole — it is the one thing that has to work")

        // ── Wire: the create body ─────────────────────────────────────────
        let body = try! CollectionShare.createBody(
            name: "Hip rehab", note: nil, categoryID: "fitness",
            expiry: .oneDay, bookmarkIDs: ["https://instagram.com/reel/a", "https://youtube.com/watch?v=b"]
        )
        let sent = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        expect(Set(sent.keys) == ["p_name", "p_note", "p_category_id", "p_expiry_days", "p_bookmark_ids"],
               "the RPC's five named parameters, every one present")
        expect(sent["p_name"] as? String == "Hip rehab", "p_name")
        expect(sent["p_note"] is NSNull, "a missing note is an explicit null, not a missing key")
        expect(sent["p_category_id"] as? String == "fitness", "p_category_id")
        expect(sent["p_expiry_days"] as? Int == 1, "p_expiry_days is the day count")
        expect((sent["p_bookmark_ids"] as? [String])?.count == 2, "p_bookmark_ids is the id list")
        let neverBody = try! CollectionShare.createBody(name: "x", note: "n", categoryID: nil,
                                                       expiry: .never, bookmarkIDs: [])
        let neverSent = try! JSONSerialization.jsonObject(with: neverBody) as! [String: Any]
        expect(neverSent["p_expiry_days"] is NSNull, "never is a null day count")
        expect(neverSent["p_category_id"] is NSNull, "no topic is a null category")
        expect((neverSent["p_bookmark_ids"] as? [String]) == [], "an empty list is still a list")

        // ── Wire: the create reply ────────────────────────────────────────
        let createdJSON = """
            {"id":"e0c0ea05-7b3f-4542-967f-a43e8d3f54b4","slug":"abc123def456",
             "url":"https://bookmarker.lol/c/abc123def456","expires_at":"2027-01-25T12:00:00+00:00","added":7}
            """
        let created = try! CollectionShare.created(from: Data(createdJSON.utf8))
        expect(created.slug == "abc123def456" && created.added == 7, "id, slug and added read back")
        expect(created.url == "https://bookmarker.lol/c/abc123def456", "the server's url is used as given")
        expect(created.expiresAt != nil, "expires_at parses")
        expect(created.appURL == "bookmarker://c/abc123def456", "and the app link follows from the slug")
        let bare = try! CollectionShare.created(from: Data(#"{"id":"x","slug":"abc123def456","added":0}"#.utf8))
        expect(bare.url == "https://bookmarker.lol/c/abc123def456" && bare.expiresAt == nil,
               "a reply without url or expires_at still yields a link and no expiry")
        expect((try? CollectionShare.created(from: Data("{}".utf8))) == nil, "a reply without a slug is an error")

        // ── Wire: opening one ─────────────────────────────────────────────
        let sharedJSON = """
            {"id":"e0c0","name":"Hip rehab — week 1","note":"Six things that helped.","owner_name":"Seb",
             "updated_at":"2026-09-01T10:00:00+00:00","expires_at":null,
             "items":[{"id":"https://instagram.com/reel/a","url":"https://www.instagram.com/reel/a/","title":"Hips",
                       "author":"@physio","platform":"instagram","kind":"reel","category_id":"fitness",
                       "subcategory":"Mobility","tags":["hips"],"image_url":null,"duration_seconds":42,"body_text":null},
                      {"id":"https://youtube.com/watch?v=b","url":"https://youtube.com/watch?v=b","title":"Feet",
                       "author":null,"platform":"youtube","kind":"video","category_id":null,"subcategory":null,
                       "tags":[],"image_url":"https://i.ytimg.com/vi/b/hq.jpg","duration_seconds":null,"body_text":null}]}
            """
        let shared = try! CollectionShare.shared(from: Data(sharedJSON.utf8))
        expect(shared?.name == "Hip rehab — week 1" && shared?.ownerName == "Seb", "name and owner read back")
        expect(shared?.items.count == 2, "both items read back")
        expect(shared?.items.first?.platform == "instagram" && shared?.items.first?.author == "@physio",
               "an item carries its source and author")
        expect(shared?.items.last?.imageURL == "https://i.ytimg.com/vi/b/hq.jpg", "and its cover when it has one")
        expect(shared?.expiresAt == nil, "a null expires_at is no expiry")
        expect(try! CollectionShare.shared(from: Data("null".utf8)) == nil,
               "the server's null — wrong slug, link off, expired — is nil, not an error")
        let noExpiryKey = try! CollectionShare.shared(from: Data(#"{"id":"x","name":"n","owner_name":"Someone","items":[]}"#.utf8))
        expect(noExpiryKey?.expiresAt == nil && noExpiryKey?.items.isEmpty == true,
               "the 0011 shape, before 0012 adds expires_at, still opens")

        expect(CollectionShare.displayTitle("Noah on Instagram: \"Loaded Bodyweight Neck Routine\"", platform: "instagram")
               == "Loaded Bodyweight Neck Routine", "an Instagram og:title shows its caption, as a card does")
        expect(CollectionShare.displayTitle("Noah on Instagram: \"Hi\"", platform: "instagram") == "Noah",
               "a caption too short to be a title falls back to the name")
        expect(CollectionShare.displayTitle("Someone on Instagram: \"x\"", platform: "youtube")
               == "Someone on Instagram: \"x\"", "the rule is Instagram's only")

        // ── Wire: saving one ──────────────────────────────────────────────
        let savedAll = try! CollectionShare.saved(from: Data(#"{"added":8,"skipped":0}"#.utf8))
        expect(savedAll?.line == "8 borks added to your library.", "all new")
        let savedSome = try! CollectionShare.saved(from: Data(#"{"added":3,"skipped":5}"#.utf8))
        expect(savedSome?.line == "3 added, 5 already in your library.", "some new")
        let savedNone = try! CollectionShare.saved(from: Data(#"{"added":0,"skipped":4}"#.utf8))
        expect(savedNone?.line == "All 4 were already in your library.", "none new")
        expect(try! CollectionShare.saved(from: Data("null".utf8)) == nil, "gone by the time you tapped")

        // ── Wire: your own ────────────────────────────────────────────────
        expect(CollectionShare.listQuery.hasPrefix("collections?select=id,name,note,slug,visibility,expires_at,updated_at,category_id,collection_items(count)"),
               "the list asks for exactly the contract's columns")
        expect(CollectionShare.listQuery.contains("&deleted_at=is.null") && CollectionShare.listQuery.hasSuffix("&order=updated_at.desc"),
               "live rows only, newest change first")

        let ownedJSON = """
            [{"id":"a","name":"Hip rehab","note":null,"slug":"abc123def456","visibility":"public",
              "expires_at":"2027-01-25T12:00:00+00:00","updated_at":"2027-01-15T12:00:00+00:00",
              "category_id":"fitness","collection_items":[{"count":8}]},
             {"id":"b","name":"Old one","note":"n","slug":"bbb123def456","visibility":"private",
              "expires_at":null,"updated_at":"2026-12-01T00:00:00+00:00","category_id":null,
              "collection_items":[{"count":0}]},
             {"id":"c","name":"Ran out","note":null,"slug":"ccc123def456","visibility":"public",
              "expires_at":"2027-01-10T12:00:00+00:00","updated_at":"2027-01-01T00:00:00+00:00",
              "category_id":null,"collection_items":[{"count":3}]}]
            """
        let owned = try! CollectionShare.owned(from: Data(ownedJSON.utf8))
        expect(owned.count == 3, "three rows")
        expect(owned[0].count == 8, "the count comes out of PostgREST's one-element array")
        expect(owned[0].isOpen(at: now) && owned[0].statusLine(now: now, locale: gb).hasPrefix("Open until "),
               "a public link with a future expiry is open until that day")
        expect(!owned[1].isOpen(at: now) && owned[1].statusLine(now: now) == "Link off",
               "private is the link off, whatever the expiry")
        expect(owned[1].count == 0, "an empty collection counts zero")
        expect(owned[2].isExpired(at: now) && !owned[2].isOpen(at: now)
               && owned[2].statusLine(now: now, locale: gb).hasPrefix("Expired "),
               "a public link past its expiry is expired, not open")
        expect(owned[0].url == "https://bookmarker.lol/c/abc123def456", "a row's link follows from its slug")
        let openForever = CollectionShare.Owned(id: "d", name: "n", note: nil, slug: "ddd123def456",
                                                visibility: "public", expiresAt: nil, updatedAt: nil,
                                                categoryID: nil, count: 1)
        expect(openForever.statusLine(now: now) == "Open until you turn it off", "no expiry says so")

        // ── Wire: patches ─────────────────────────────────────────────────
        func fields(_ data: Data) -> [String: Any] {
            try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        expect(fields(try! CollectionShare.Patch.visibility(on: false))["visibility"] as? String == "private",
               "turning the link off is visibility private")
        expect(fields(try! CollectionShare.Patch.visibility(on: true))["visibility"] as? String == "public",
               "turning it on is public")
        let tenMore = fields(try! CollectionShare.Patch.expiry(.tenDays, from: now))
        expect((tenMore["expires_at"] as? String)?.hasPrefix("2027-01-25") == true,
               "ten more days is a closing day ten days out")
        expect(tenMore["visibility"] as? String == "public", "giving a link more time turns it on")
        expect(fields(try! CollectionShare.Patch.expiry(.never, from: now))["expires_at"] is NSNull,
               "never clears the closing day")
        expect((fields(try! CollectionShare.Patch.delete(at: now))["deleted_at"] as? String)?.hasPrefix("2027-01-15") == true,
               "delete is a tombstone, not a DELETE")
        expect(CollectionShare.rowsChanged(in: Data("[]".utf8)) == 0, "no rows echoed is no rows changed")
        expect(CollectionShare.rowsChanged(in: Data(#"[{"id":"a"}]"#.utf8)) == 1, "one row echoed is one changed")

        // ── Wire: the name on the page ────────────────────────────────────
        expect(CollectionShare.profileQuery(userID: "u1") == "profiles?id=eq.u1&select=display_name",
               "the profile is read by id, one column")
        expect(CollectionShare.displayName(from: Data(#"[{"display_name":"Seb"}]"#.utf8)) == "Seb", "a name")
        expect(CollectionShare.displayName(from: Data(#"[{"display_name":null}]"#.utf8)) == nil,
               "null — every production profile today — is no name")
        expect(CollectionShare.displayName(from: Data(#"[{"display_name":"  "}]"#.utf8)) == nil,
               "whitespace is no name, which is what the page thinks too")
        expect(CollectionShare.displayName(from: Data("[]".utf8)) == nil, "no row is no name")
        expect(fields(try! CollectionShare.displayNameBody("Seb"))["display_name"] as? String == "Seb",
               "the patch sets display_name")

        print(failures == 0 ? "\nAll collection share checks passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
