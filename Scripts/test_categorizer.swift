import Foundation

/// Compile:
/// `swiftc -parse-as-library -o /tmp/categorizer-tests Core/Platform.swift Core/Taxonomy.swift Core/Categorizer.swift Core/LinkPreview.swift Scripts/test_categorizer.swift`
///
/// Regenerate the JS-parity fixture from its own inputs (every case run 40
/// times so a non-deterministic answer shows up as more than one `expect`):
/// `/tmp/categorizer-tests --write-fixture Scripts/fixtures/categorizer_cases.json`
@main
enum CategorizerTests {
    static func main() {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--write-fixture"), args.count > flag + 1 {
            writeFixture(to: args[flag + 1])
            return
        }

        var failures = 0
        func expect(_ cond: Bool, _ message: String) {
            if cond { print("ok   \(message)") }
            else { failures += 1; print("FAIL \(message)") }
        }
        func suggest(_ url: String, _ title: String, text: String? = nil,
                     description: String? = nil, author: String? = nil) -> Categorizer.Suggestion {
            Categorizer.suggest(url: URL(string: url)!, title: title, text: text,
                                description: description, author: author)
        }

        // ── SocialTitle ────────────────────────────────────────────────────
        let hip = SocialTitle.unwrap(
            "Sophie Rinkenbach | The Mobility Framework on Instagram: \"I'm not a relationship expert but I do know a thing or two about hips, whi…\""
        )
        expect(hip.author == "Sophie Rinkenbach", "IG: author before the pipe")
        expect(hip.bio == "The Mobility Framework", "IG: bio after the pipe")
        expect(hip.caption?.hasPrefix("I'm not a relationship expert") == true, "IG: caption is the quoted part")
        expect(hip.caption?.hasSuffix("…") == true, "IG: a truncated caption keeps its ellipsis, loses the quote")

        let gabby = SocialTitle.unwrap("Gabby Q on Instagram: \"Years ago, when I first started training my feet, I couldn't move my toes at all…\"")
        expect(gabby.author == "Gabby Q" && gabby.bio == nil, "IG without a bio")
        expect(gabby.caption?.hasPrefix("Years ago") == true, "IG without a bio: caption")

        let pg = SocialTitle.unwrap("Paul Graham (@paulg) on X: \"How to do great work — a thread.\" / X")
        expect(pg.author == "Paul Graham", "X: handle stripped from the author")
        expect(pg.caption == "How to do great work — a thread.", "X: trailing ' / X' removed before the caption is read")

        let tt = SocialTitle.unwrap("wanderfrugal on TikTok")
        expect(tt.isSocial && tt.author == "wanderfrugal" && tt.caption == nil, "TikTok: wrapped title with no caption")

        let plain = SocialTitle.unwrap("5 mobility drills that undo a desk day")
        expect(!plain.isSocial && plain.caption == nil, "a plain headline is not social")
        expect(!SocialTitle.unwrap("My thoughts on X and where it is going").isSocial,
               "'on X' mid-sentence is not a seam")
        expect(SocialTitle.unwrap("Instagram").isSocial == false, "the login-wall title is not social")

        expect(SocialTitle.caption(fromDescription: "1,204 likes, 31 comments - sophie.rink on August 28, 2026: \"Three drills. #mobility\"")
                == "Three drills. #mobility", "IG description: counts and date stripped")
        expect(SocialTitle.caption(fromDescription: "Your feet weren't designed to be passengers.")
                == "Your feet weren't designed to be passengers.", "a plain description is left alone")

        // ── Hashtags ───────────────────────────────────────────────────────
        let tags = Categorizer.hashtags(in: ["Save it #FlatFeet #mobility", "#fyp #mobility #footarch #x"])
        expect(tags == ["flatfeet", "mobility", "footarch"], "hashtags: lowercased, deduped, in order, minus #fyp and one-letter tags — got \(tags)")

        // ── Hook clause ────────────────────────────────────────────────────
        expect(Categorizer.withoutHook("I'm not a relationship expert but I do know a thing or two about hips")
                == "but I do know a thing or two about hips", "the hook clause is dropped")
        expect(Categorizer.withoutHook("Nobody tells you this. Sourdough needs time.") == "Sourdough needs time.",
               "hook then sentence")
        expect(Categorizer.withoutHook("Sourdough needs time, ask any expert.") == "Sourdough needs time, ask any expert.",
               "a hook word past the first clause changes nothing")
        expect(Categorizer.withoutHook("The secret") == "The secret", "a one-clause hook is kept — it is all there is")

        // ── Seb's two saves ────────────────────────────────────────────────
        let hipTitle = "Sophie Rinkenbach | The Mobility Framework on Instagram: \"I'm not a relationship expert but I do know a thing or two about hips, whi…\""
        let hipS = suggest("https://www.instagram.com/reel/DBxHipReel/", hipTitle)
        expect(hipS.categoryID != "relationships", "hip reel: never Relationships — got \(hipS.categoryID ?? "nil")")
        expect(hipS.categoryID == nil || hipS.categoryID == "fitness", "hip reel: fitness or not filed — got \(hipS.categoryID ?? "nil")")
        expect(!hipS.isConfident, "hip reel: a bio hint is never confident")
        expect(hipS.categoryID == "fitness" && hipS.subcategory == "Mobility" && hipS.evidence == .thin,
               "hip reel: the bio gives a thin Fitness › Mobility guess — got \(hipS.categoryID ?? "nil")/\(hipS.subcategory ?? "nil") \(hipS.evidence)")
        expect(!hipS.tags.contains("communication") && !hipS.tags.contains("business"), "hip reel: no tags from losing categories — got \(hipS.tags)")

        let footTitle = "Gabby Q on Instagram: \"Years ago, when I first started training my feet, I couldn't move my toes at all…\""
        let footCaption = "Your feet weren't designed to be passengers. 🦶 These exercises build toe strength, foot control and the muscles that support your arch from the ground up. Looks simple. Your feet might disagree. #flatfeet #mobility #footarch #feet Save it. Try it."
        let footBare = suggest("https://www.instagram.com/reel/DBxFootReel/", footTitle)
        expect(footBare.categoryID != "science" && footBare.categoryID != "pets",
               "foot reel, title only: never Science or Pets — got \(footBare.categoryID ?? "nil")")
        expect(footBare.categoryID == nil || footBare.categoryID == "fitness",
               "foot reel, title only: fitness or not filed — got \(footBare.categoryID ?? "nil")")
        let foot = suggest("https://www.instagram.com/reel/DBxFootReel/", footTitle, description: footCaption, author: "zachtrained")
        expect(foot.categoryID == "fitness" && foot.subcategory == "Mobility",
               "foot reel with its caption: Fitness › Mobility — got \(foot.categoryID ?? "nil")/\(foot.subcategory ?? "nil")")
        expect(foot.isConfident, "foot reel: #mobility names a subtopic, so this is confident (score \(foot.score))")
        expect(foot.tags.first == "mobility", "foot reel: the hashtag hit leads the tags — got \(foot.tags)")
        expect(foot.tags.contains("flatfeet"), "foot reel: the author's own #flatfeet becomes a tag — got \(foot.tags)")
        expect(!foot.tags.contains("grounding") && !foot.tags.contains("experiment"), "foot reel: no #grounding — got \(foot.tags)")

        // ── Evidence rules ─────────────────────────────────────────────────
        let drills = suggest("https://www.instagram.com/p/five-hip-mobility-drills/", "5 mobility drills that undo a desk day")
        expect(drills.categoryID == "fitness" && drills.isConfident, "a real headline match is confident")
        expect(drills.tags == ["mobility"], "tags come from the winning topic only — got \(drills.tags)")

        let generic = suggest("https://x.com/a/status/1", "", text: "Communication is everything")
        expect(generic.categoryID == nil, "a generic subcategory name alone files nothing — got \(generic.categoryID ?? "nil")")
        let genericPlus = suggest("https://x.com/a/status/1", "", text: "Communication is everything with my girlfriend")
        expect(genericPlus.categoryID == "relationships" && genericPlus.subcategory == "Communication",
               "…but names the subtopic once the topic is established — got \(genericPlus.categoryID ?? "nil")/\(genericPlus.subcategory ?? "nil")")

        let twoSmall = suggest("https://www.youtube.com/watch?v=x", "Gym 5k plan for beginners")
        expect(twoSmall.categoryID == "fitness" && twoSmall.isConfident, "two independent small hints are confident (score \(twoSmall.score))")

        let slug = suggest("https://example.com/blog/financial-independence-plan", "")
        expect(slug.categoryID == "money" && !slug.isConfident, "URL-only evidence is a guess, never confident — got \(slug.categoryID ?? "nil") (score \(slug.score))")

        let bio = suggest("https://www.instagram.com/reel/x/", "Dr Rhonda | Longevity Lab on Instagram: \"This one changed how I think about my 40s\"")
        expect(bio.categoryID == "health" && !bio.isConfident, "bio-only evidence is thin — got \(bio.categoryID ?? "nil") \(bio.evidence)")

        let hashtagOnly = suggest("https://www.instagram.com/reel/y/", "fit.lena on Instagram: \"🔥🔥🔥\"", description: "🔥🔥🔥 #pilates #coreworkout #homeworkout")
        expect(hashtagOnly.categoryID == "fitness" && hashtagOnly.subcategory == "Pilates" && hashtagOnly.isConfident,
               "a hashtag naming a subtopic is confident on its own — got \(hashtagOnly.categoryID ?? "nil")/\(hashtagOnly.subcategory ?? "nil") \(hashtagOnly.evidence)")

        let hook = suggest("https://www.instagram.com/reel/z/", "Marco Bakes on Instagram: \"Nobody tells you this about money. Sourdough needs 24 hours, not 4. #sourdough #baking\"")
        expect(hook.categoryID == "recipes" || hook.categoryID == "fooddrink", "the hook clause about money does not file it under Money — got \(hook.categoryID ?? "nil")")

        let bare = suggest("https://www.instagram.com/reel/C9xyz123/", "")
        expect(bare.categoryID == nil && bare.evidence == .none, "a bare URL is not filed")
        expect(suggest("https://example.com/", "asdkjh qwe zxc").categoryID == nil, "nonsense is not filed")

        let osaka = suggest("https://www.tiktok.com/@wanderfrugal/video/7231", "Osaka on $60 a day — full itinerary")
        expect(osaka.categoryID == "travel" && osaka.subcategory == "Itineraries" && osaka.isConfident, "the existing headline cases still hold")

        // ── LinkPreview.parse ──────────────────────────────────────────────
        let html = """
        <html><head><title>Instagram</title>
        <meta property="og:title" content="Gabby Q on Instagram: &quot;Years ago&#x2026;&quot;" />
        <meta property="og:description" content="812 likes, 14 comments - gabbyq on September 1, 2026: &quot;Your feet #flatfeet #mobility&quot;" />
        <meta property="og:image" content="https://cdn.example/x.jpg" />
        </head></html>
        """
        let parsed = LinkPreview.parse(html: html, base: URL(string: "https://www.instagram.com/reel/x/")!)
        expect(parsed?.title == "Gabby Q on Instagram: \"Years ago…\"", "parse: og:title with entities decoded — got \(parsed?.title ?? "nil")")
        expect(parsed?.description?.contains("#flatfeet #mobility") == true, "parse: og:description is read — got \(parsed?.description ?? "nil")")
        let twitterOnly = LinkPreview.parse(html: "<meta name=\"twitter:title\" content=\"T\"><meta name=\"twitter:description\" content=\"D\">", base: URL(string: "https://a.b/")!)
        expect(twitterOnly?.description == "D", "parse: twitter:description is the fallback")

        // ── Fixture parity with the JS port ────────────────────────────────
        // The fixture is generated from this binary, so this only guards
        // against editing the cases without regenerating.
        if let cases = loadFixture("Scripts/fixtures/categorizer_cases.json") {
            var drift = 0
            for c in cases {
                let got = run(c)
                let hit = (c["expect"] as? [[String: Any]] ?? []).contains { e in
                    (e["topic"] as? String) == got.categoryID
                        && (e["subtopic"] as? String) == got.subcategory
                        && (e["score"] as? Int) == got.score
                        && (e["tags"] as? [String]) == got.tags
                }
                if !hit { drift += 1; print("     drift: \(c["url"] ?? "") → \(got.categoryID ?? "nil") \(got.score) \(got.tags)") }
            }
            expect(drift == 0, "fixture matches this build (\(cases.count) cases; regenerate with --write-fixture)")
        }

        print(failures == 0 ? "\nAll categorizer checks passed." : "\n\(failures) categorizer check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Fixture

    static func loadFixture(_ path: String) -> [[String: Any]]? {
        guard let data = FileManager.default.contents(atPath: path),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return doc["cases"] as? [[String: Any]]
    }

    static func run(_ c: [String: Any]) -> Categorizer.Suggestion {
        let url = URL(string: c["url"] as? String ?? "")!
        let title = (c["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Categorizer.fallbackTitle(for: url)
        let text = (c["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let description = (c["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let author = (c["author"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Categorizer.suggest(url: url, title: title, text: text, description: description, author: author)
    }

    /// Recomputes every `expect` from the case inputs and rewrites the file.
    static func writeFixture(to path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              var doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = doc["cases"] as? [[String: Any]]
        else { print("cannot read \(path)"); exit(1) }

        var out: [[String: Any]] = []
        for var c in cases {
            let url = URL(string: c["url"] as? String ?? "")!
            var answers: [[String: Any]] = []
            var seen: Set<String> = []
            for _ in 0..<40 {
                let s = run(c)
                let entry: [String: Any] = [
                    "score": s.score,
                    "subtopic": s.subcategory as Any? ?? NSNull(),
                    "tags": s.tags,
                    "topic": s.categoryID as Any? ?? NSNull(),
                ]
                let key = "\(s.categoryID ?? "-")|\(s.subcategory ?? "-")|\(s.score)|\(s.tags.joined(separator: ","))"
                if seen.insert(key).inserted { answers.append(entry) }
            }
            c["fallbackTitle"] = Categorizer.fallbackTitle(for: url)
            c["fallbackAuthor"] = Categorizer.fallbackAuthor(for: url) as Any? ?? NSNull()
            c["evidence"] = run(c).evidence.rawValue
            c["expect"] = answers
            out.append(c)
        }
        doc["cases"] = out
        doc["_regenerate"] = "swiftc -parse-as-library -o /tmp/categorizer-tests Core/Platform.swift Core/Taxonomy.swift Core/Categorizer.swift Core/LinkPreview.swift Scripts/test_categorizer.swift && /tmp/categorizer-tests --write-fixture Scripts/fixtures/categorizer_cases.json"
        guard let json = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            print("cannot encode"); exit(1)
        }
        FileManager.default.createFile(atPath: path, contents: json)
        print("wrote \(out.count) cases to \(path)")
    }
}
