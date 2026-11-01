import Foundation

/// Writes `Scripts/fixtures/filing_suggest_cases.json`: what `FilingSuggest`,
/// `FilingMemory`, `FilingKeys` and `Categorizer.scores` answer for a fixed
/// set of cases. `Scripts/check_filing_parity.mjs` holds the web's
/// `docs/filing-suggest.js` (and `Filer.scores`) to it.
///
/// From the repo root:
/// `swiftc -parse-as-library -o /tmp/filing-fixture Core/Platform.swift Core/Taxonomy.swift Core/Categorizer.swift Core/LinkPreview.swift Core/FilingMemory.swift Core/FilingSuggest.swift Scripts/gen_filing_fixture.swift`
/// `/tmp/filing-fixture --write Scripts/fixtures/filing_suggest_cases.json`
///
/// The cases live here, not in the JSON: the file is rewritten whole. Each
/// case runs 40 times and every distinct answer is recorded, the way
/// `categorizer_cases.json` is made; more than one `expect` would mean the
/// Swift is not deterministic there, and the JS may land on any of them.
/// Memories are written as the web's own rows, so the checker also exercises
/// `historyFromRows`; this file turns them into history the same way.
@main
enum FilingFixture {

    static let nowString = "2026-11-01T12:00:00Z"

    static func main() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--write"), args.count > flag + 1 else {
            print("usage: filing-fixture --write Scripts/fixtures/filing_suggest_cases.json")
            exit(2)
        }
        write(to: args[flag + 1])
    }

    // MARK: - Memories, as the web stores rows

    static func row(_ category: String, _ sub: String?, author: String? = nil, url: String, at: String,
                    source: String = "user", deleted: String? = nil) -> [String: Any] {
        [
            "category_id": category,
            "subcategory": orNull(sub),
            "author": orNull(author),
            "url": url,
            "filing_source": source,
            "updated_at": at,
            "deleted_at": orNull(deleted),
        ]
    }

    static let memories: [String: [[String: Any]]] = [
        "none": [],
        // One filing of @kaylawalks, 200 days ago.
        "kaylaOnce": [
            row("fitness", "Mobility", author: "@kaylawalks", url: "https://www.tiktok.com/@kaylawalks/video/7300000000000000001", at: "2026-04-15T12:00:00Z"),
        ],
        // Three, split across two subtopics. The third row's author is the
        // share sheet's placeholder; the handle in the URL still names her.
        "kaylaThrice": [
            row("fitness", "Mobility", author: "@kaylawalks", url: "https://www.tiktok.com/@kaylawalks/video/7300000000000000002", at: "2026-10-29T12:00:00Z"),
            row("fitness", "Mobility", url: "https://www.tiktok.com/@kaylawalks/video/7300000000000000003", at: "2026-10-22T12:00:00Z"),
            row("fitness", "Running", author: "tiktok.com", url: "https://www.tiktok.com/@kaylawalks/video/7300000000000000004", at: "2026-09-22T12:00:00Z"),
        ],
        // Two filings this week under different subtopics: equal points, so
        // the more recent one leads.
        "split": [
            row("fitness", "Running", url: "https://www.tiktok.com/@runwithjo/video/7300000000000000011", at: "2026-10-30T12:00:00Z"),
            row("fitness", "Mobility", url: "https://www.tiktok.com/@runwithjo/video/7300000000000000012", at: "2026-10-27T12:00:00Z"),
        ],
        // One nytimes.com article under News. A web author is never a creator.
        "nytimes": [
            row("news", "Politics", author: "The New York Times", url: "https://www.nytimes.com/2026/10/20/us/politics/budget-vote.html", at: "2026-10-20T12:00:00Z"),
        ],
        // A custom topic, learned only from history.
        "yarn": [
            row("custom.knitting", nil, url: "https://www.tiktok.com/@yarnloop/video/7300000000000000021", at: "2026-10-26T12:00:00Z"),
            row("custom.knitting", "Sweaters", author: "@yarnloop", url: "https://www.tiktok.com/@yarnloop/video/7300000000000000022", at: "2026-10-31T12:00:00Z"),
        ],
        // Instagram reels whose author is only ever the site: no creator.
        "placeholder": [
            row("comedy", "Memes", author: "instagram.com", url: "https://www.instagram.com/reel/DAAAAAAAAA1/", at: "2026-10-29T12:00:00Z"),
            row("comedy", "Skits", author: "Instagram", url: "https://www.instagram.com/reel/DAAAAAAAAA2/", at: "2026-10-12T12:00:00Z"),
        ],
        // Habits, plus three rows that must not count: the app's own guess,
        // a filing over a year old, and a deleted save.
        "habits": [
            row("fashion", "Outfits", url: "https://www.pinterest.com/pin/1000000000000001/", at: "2026-10-30T12:00:00Z"),
            row("cars", "Detailing", url: "https://www.youtube.com/watch?v=detail01", at: "2026-10-30T12:00:00Z"),
            row("home", "Decor", url: "https://www.pinterest.com/pin/1000000000000002/", at: "2026-10-12T12:00:00Z"),
            row("home", "Decor", url: "https://www.pinterest.com/pin/1000000000000003/", at: "2026-10-26T12:00:00Z"),
            row("recipes", "Snacks", url: "https://www.tiktok.com/@snackqueen/video/7300000000000000031", at: "2026-10-31T12:00:00Z", source: "automatic"),
            row("travel", "Itineraries", url: "https://www.tiktok.com/@wanderfrugal/video/7300000000000000032", at: "2025-09-27T12:00:00Z"),
            row("gaming", nil, url: "https://www.youtube.com/watch?v=gone01", at: "2026-10-31T12:00:00Z", deleted: "2026-10-31T13:00:00Z"),
        ],
    ]

    // MARK: - Cases

    static let builtinsPlusKnitting: [String] = Taxonomy.all.map(\.id) + ["custom.knitting"]

    static let cases: [[String: Any]] = [
        ["name": "keyword",
         "input": ["url": "https://www.instagram.com/p/five-hip-mobility-drills/", "title": "5 mobility drills that undo a desk day"],
         "memory": "none"],
        ["name": "hashtag",
         "input": ["url": "https://www.instagram.com/reel/Cpilates01/", "title": "fit.lena on Instagram: \"🔥🔥🔥\"",
                   "description": "🔥🔥🔥 #pilates #coreworkout #homeworkout", "author": "fit.lena"],
         "memory": "none"],
        ["name": "no signal at all",
         "input": ["url": "https://example.com/", "title": "asdkjh qwe zxc"],
         "memory": "none"],
        ["name": "creator, one pick",
         "input": ["url": "https://www.tiktok.com/@kaylawalks/video/7311111111111111111", "title": "@kaylawalks on TikTok"],
         "memory": "kaylaOnce"],
        ["name": "creator, three picks",
         "input": ["url": "https://www.tiktok.com/@kaylawalks/video/7311111111111111112", "title": "@kaylawalks on TikTok"],
         "memory": "kaylaThrice"],
        ["name": "split subtopics",
         "input": ["url": "https://www.tiktok.com/@runwithjo/video/7322222222222222222", "title": "@runwithjo on TikTok"],
         "memory": "split"],
        ["name": "domain",
         "input": ["url": "https://www.nytimes.com/2026/10/30/opinion/the-quiet-case.html", "title": "The quiet case for doing less",
                   "author": "The New York Times"],
         "memory": "nytimes"],
        ["name": "AI high vs keyword",
         "input": ["url": "https://www.tiktok.com/@chefnadia/video/7333333333333333333", "title": "My lunch every day this week"],
         "memory": "none",
         "ai": ["categoryID": "nutrition", "subcategory": "High-protein", "confidence": "high"]],
        ["name": "AI medium",
         "input": ["url": "https://x.com/someone/status/1850000000000000000",
                   "title": "Someone (@someone) on X: \"Okay this changed everything for me\" / X"],
         "memory": "none",
         "ai": ["categoryID": "money", "subcategory": "Budgeting", "confidence": "medium"]],
        ["name": "OCR boost",
         "input": ["url": "https://www.tiktok.com/@mofit/video/7344444444444444444", "title": "@mofit on TikTok",
                   "description": "keeps me full till 2pm, 40g protein",
                   "ocrLines": ["40g PROTEIN", "creatine + oats", "@mofit", "1.2M"]] as [String: Any],
         "memory": "none"],
        ["name": "login-wall OCR ignored",
         "input": ["url": "https://www.instagram.com/reel/DLoginWall1/", "title": "Instagram",
                   "ocrLines": ["Log in to Instagram", "Sign up to see photos and videos from your friends.",
                                "@kaylawalks", "1.2M", "0:15 / 1:02", "Open app"]] as [String: Any],
         "memory": "none"],
        ["name": "OCR alone stays thin",
         "input": ["url": "https://www.instagram.com/reel/DOcrOnly01/", "title": "Instagram",
                   "ocrLines": ["HIP MOBILITY ROUTINE", "10 min stretching for runners", "Day 3/30", "original audio"]] as [String: Any],
         "memory": "none"],
        ["name": "custom topic via history",
         "input": ["url": "https://www.tiktok.com/@yarnloop/video/7355555555555555555", "title": "@yarnloop on TikTok"],
         "memory": "yarn",
         "taxonomyOrder": builtinsPlusKnitting],
        ["name": "deleted custom topic dropped",
         "input": ["url": "https://www.tiktok.com/@yarnloop/video/7355555555555555556", "title": "@yarnloop on TikTok",
                   "description": "chunky cardigan, every stitch handmade"],
         "memory": "yarn"],
        ["name": "placeholder author skipped",
         "input": ["url": "https://www.instagram.com/reel/DPlaceholder1/", "title": "Instagram", "author": "instagram.com"],
         "memory": "placeholder"],
        ["name": "habit fill",
         "input": ["url": "https://www.youtube.com/watch?v=quiet01", "title": "A quiet Sunday", "author": "Some Channel"],
         "memory": "habits"],
        ["name": "starter fill, five seats",
         "input": ["url": "https://www.tiktok.com/@wanderfrugal/video/7231", "title": "Osaka on $60 a day — full itinerary"],
         "memory": "none",
         "limit": 5],
        ["name": "tie broken by taxonomy order",
         "input": ["url": "https://example.org/notes", "title": "Budget laptop"],
         "memory": "none"],
        ["name": "pinned yours",
         "input": ["url": "https://www.instagram.com/p/five-hip-mobility-drills/", "title": "5 mobility drills that undo a desk day"],
         "memory": "none",
         "pinned": ["categoryID": "wellness", "subcategory": "Morning routines", "reason": "yours"]],
        ["name": "pinned guess",
         "input": ["url": "https://www.instagram.com/reel/DGuess0001/", "title": "Instagram",
                   "description": "Sunday reset: laundry, fridge clean out, fresh sheets"],
         "memory": "none",
         "pinned": ["categoryID": "cleaning", "subcategory": NSNull(), "reason": "guess"] as [String: Any]],
        ["name": "triage learns mid-session",
         "input": ["url": "https://www.tiktok.com/@mobilitymo/video/7366666666666666666", "title": "@mobilitymo on TikTok"],
         "memory": "none",
         "adding": [row("fitness", "Mobility", url: "https://www.tiktok.com/@mobilitymo/video/7366666666666666665", at: "2026-11-01T11:59:00Z")]],
    ]

    static let keyCases: [[String: Any]] = [
        ["url": "https://www.tiktok.com/@Kayla.Walks/video/7300000000000000099"],
        ["url": "https://x.com/levelsio/status/1850000000000000001", "author": "Pieter Levels"],
        ["url": "https://x.com/i/status/1850000000000000002", "author": "Pieter Levels"],
        ["url": "https://www.instagram.com/sophie.rink/reel/DBxHipReel/"],
        ["url": "https://www.instagram.com/stories/sophie.rink/3400000000000000000/"],
        ["url": "https://www.instagram.com/reel/DBxHipReel/", "author": "instagram.com"],
        ["url": "https://www.instagram.com/reel/DBxHipReel/", "author": "Instagram"],
        ["url": "https://www.instagram.com/reel/DBxHipReel/", "author": "  Zoë Ståhl-Øvergaard "],
        ["url": "https://www.youtube.com/@SquatMechanics/videos"],
        ["url": "https://www.youtube.com/watch?v=deadliftform", "author": "Squat Mechanics"],
        ["url": "https://youtube.com/shorts/abc123", "author": "youtube.com"],
        ["url": "https://vm.tiktok.com/ZMabc123/", "author": "tiktok.com"],
        ["url": "https://vm.tiktok.com/ZMabc123/", "author": "@kaylawalks"],
        ["url": "https://www.tiktok.com/@caf%C3%A9/video/1", "author": "J"],
        ["url": "https://www.pinterest.com/pin/1000000000000001/", "author": "Home"],
        ["url": "https://www.nytimes.com/2026/10/30/opinion/the-quiet-case.html", "author": "The New York Times"],
        ["url": "https://WWW.Example.COM/a-post", "author": "example.com"],
        ["url": "https://www.threads.net/@zuck/post/C1abc"],
    ]

    static let ocrCases: [[String]] = [
        [],
        ["Log in", "Sign up for TikTok", "@user.name", "12:34", "1.2M"],
        ["  Hip mobility routine  ", "Hip mobility routine", "ok", "Follow for more"],
        ["Short", "txt"],
        ["abc", "de"],
        ["2d ago", "45%", "x2", "Day 3/30"],
        ["We use cookies to improve your experience", "Accept all"],
        [String(repeating: "protein oats creatine ", count: 30)],
        ["\u{FEFF}Morning routine\u{85}", "Zoë’s 5-minute reset"],
    ]

    // MARK: - Running a case

    static func orNull(_ value: Any?) -> Any { value ?? NSNull() }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// The Swift side of the web's `historyFromRows`.
    static func history(_ rows: [[String: Any]]) -> [FilingHistoryItem] {
        rows.compactMap { row in
            if let deleted = row["deleted_at"] as? String, !deleted.isEmpty { return nil }
            guard row["filing_source"] as? String == "user",
                  let category = row["category_id"] as? String, !category.isEmpty else { return nil }
            let stamp = row["updated_at"] is String ? row["updated_at"] : row["saved_at"]
            guard let at = date(stamp) else { return nil }
            let url = (row["url"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
            return FilingHistoryItem(categoryID: category,
                                     subcategory: (row["subcategory"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                     author: row["author"] as? String, url: url, at: at)
        }
    }

    static func scoreJSON(_ s: Categorizer.CategoryScore) -> [String: Any] {
        ["topic": s.categoryID, "score": s.score, "subtopic": orNull(s.subcategory),
         "subWeight": s.subWeight, "label": orNull(s.label), "hashtag": s.fromHashtag]
    }

    static func rankingJSON(_ r: FilingRanking) -> [String: Any] {
        [
            "candidates": r.candidates.map { c -> [String: Any] in
                ["categoryID": c.categoryID, "subcategory": orNull(c.subcategory), "score": c.score,
                 "reasons": c.reasons.map(\.rawValue), "altSubs": c.altSubs, "creator": orNull(c.creator),
                 "creatorPicks": c.creatorPicks, "matched": orNull(c.matched)]
            },
            "preselect": orNull(r.preselect),
            "evidence": r.evidence.rawValue,
        ]
    }

    static func memoryJSON(_ memory: FilingMemory) -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(memory),
              let object = try? JSONSerialization.jsonObject(with: data) else { fatalError("cannot encode memory") }
        return object
    }

    static func answer(_ c: [String: Any], now: Date) -> [String: Any] {
        let raw = c["input"] as! [String: Any]
        let ocrText = (raw["ocrLines"] as? [String]).flatMap(FilingSuggest.cleanOCR)
        let input = FilingInput(url: URL(string: raw["url"] as! String)!,
                                title: raw["title"] as? String ?? "",
                                text: raw["text"] as? String,
                                description: raw["description"] as? String,
                                author: raw["author"] as? String,
                                ocrText: ocrText)
        var memory = FilingMemory.build(from: history(memories[c["memory"] as? String ?? "none"] ?? []), now: now)
        if let more = c["adding"] as? [[String: Any]] { memory = memory.adding(history(more), now: now) }
        let ai = (c["ai"] as? [String: Any]).map { a in
            Categorizer.Suggestion(categoryID: a["categoryID"] as? String,
                                   subcategory: a["subcategory"] as? String,
                                   tags: [],
                                   score: a["confidence"] as? String == "high" ? 28 : 13)
        }
        let pinned = (c["pinned"] as? [String: Any]).map { p in
            FilingPin(categoryID: p["categoryID"] as! String,
                      subcategory: p["subcategory"] as? String,
                      reason: FilingCandidate.Reason(rawValue: p["reason"] as! String)!)
        }
        let ranking = FilingSuggest.rank(input, memory: memory, ai: ai, pinned: pinned,
                                         taxonomyOrder: c["taxonomyOrder"] as? [String] ?? Taxonomy.all.map(\.id),
                                         now: now, limit: c["limit"] as? Int ?? FilingSuggest.ringSize)
        return [
            "creatorKey": orNull(FilingKeys.creator(author: input.author, url: input.url)),
            "creatorLabel": orNull(FilingKeys.creatorLabel(author: input.author, url: input.url)),
            "domain": orNull(FilingKeys.domain(url: input.url)),
            "ocrText": orNull(ocrText),
            "keywordScores": Categorizer.scores(url: input.url, title: input.title, text: input.text,
                                                description: input.description, author: input.author).map(scoreJSON),
            "ocrScores": ocrText.map { Categorizer.scores(url: nil, title: "", text: $0).map(scoreJSON) } ?? [],
            "memory": memoryJSON(memory),
            "ranking": rankingJSON(ranking),
            "reasonLines": ranking.candidates.map { orNull(FilingSuggest.reasonLine($0, input: input)) },
        ]
    }

    /// Every distinct answer over `runs` runs.
    static func distinct(_ runs: Int = 40, _ make: () -> Any) -> [Any] {
        var seen: Set<String> = []
        var out: [Any] = []
        for _ in 0..<runs {
            let value = make()
            guard let data = try? JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys]),
                  let key = String(data: data, encoding: .utf8) else { fatalError("cannot serialise an answer") }
            if seen.insert(key).inserted { out.append(value) }
        }
        return out
    }

    // MARK: - Writing

    static func write(to path: String) {
        guard let now = date(nowString) else { fatalError("bad now") }

        let keys: [[String: Any]] = keyCases.map { k in
            let url = URL(string: k["url"] as! String)!
            let author = k["author"] as? String
            var out = k
            out["expect"] = distinct {
                ["creator": orNull(FilingKeys.creator(author: author, url: url)),
                 "creatorLabel": orNull(FilingKeys.creatorLabel(author: author, url: url)),
                 "domain": orNull(FilingKeys.domain(url: url))] as [String: Any]
            }
            return out
        }
        let ocr: [[String: Any]] = ocrCases.map { lines in
            ["lines": lines, "expect": distinct { orNull(FilingSuggest.cleanOCR(lines)) }]
        }
        var ambiguous = 0
        let written: [[String: Any]] = cases.map { c in
            var out = c
            let answers = distinct { answer(c, now: now) }
            if answers.count > 1 { ambiguous += 1 }
            out["expect"] = answers
            return out
        }

        let doc: [String: Any] = [
            "note": "Ground truth for docs/filing-suggest.js and Filer.scores: what Core/FilingSuggest.swift, Core/FilingMemory.swift and Categorizer.scores answer. Written by Scripts/gen_filing_fixture.swift --write, which runs every case 40 times; `expect` lists every distinct answer (one means the Swift is deterministic there and the JS must match it exactly). Memories are web rows, built with historyFromRows then FilingMemory.build at `now`; `adding` rows are folded in after. Checked by node Scripts/check_filing_parity.mjs.",
            "regenerate": "swiftc -parse-as-library -o /tmp/filing-fixture Core/Platform.swift Core/Taxonomy.swift Core/Categorizer.swift Core/LinkPreview.swift Core/FilingMemory.swift Core/FilingSuggest.swift Scripts/gen_filing_fixture.swift && /tmp/filing-fixture --write Scripts/fixtures/filing_suggest_cases.json",
            "now": nowString,
            "ringSize": FilingSuggest.ringSize,
            "weights": [
                "creatorPerPick": FilingSuggest.Weight.creatorPerPick, "creatorCap": FilingSuggest.Weight.creatorCap,
                "domainPerPick": FilingSuggest.Weight.domainPerPick, "domainCap": FilingSuggest.Weight.domainCap,
                "aiHigh": FilingSuggest.Weight.aiHigh, "aiMedium": FilingSuggest.Weight.aiMedium,
                "ocrCap": FilingSuggest.Weight.ocrCap, "habitCap": FilingSuggest.Weight.habitCap,
                "preselectFloor": FilingSuggest.Weight.preselectFloor, "strong": FilingSuggest.Weight.strong,
            ],
            "limits": [
                "creators": FilingMemory.Limit.creators, "domains": FilingMemory.Limit.domains,
                "picksPerKey": FilingMemory.Limit.picksPerKey, "habits": FilingMemory.Limit.habits,
                "recentPerHabit": FilingMemory.Limit.recentPerHabit, "horizonDays": FilingMemory.Limit.horizonDays,
            ],
            "recency": ["week": FilingMemory.Recency.week, "month": FilingMemory.Recency.month, "year": FilingMemory.Recency.year],
            "starters": Taxonomy.onboardingInterests,
            "furniture": FilingSuggest.furniture,
            "memories": memories,
            "keys": keys,
            "ocr": ocr,
            "cases": written,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            fatalError("cannot encode the fixture")
        }
        FileManager.default.createFile(atPath: path, contents: json + Data("\n".utf8))
        print("wrote \(written.count) cases, \(keys.count) key cases and \(ocr.count) OCR cases to \(path)"
              + (ambiguous > 0 ? " (\(ambiguous) not deterministic)" : ""))

        for c in written {
            guard let first = (c["expect"] as? [[String: Any]])?.first,
                  let ranking = first["ranking"] as? [String: Any],
                  let candidates = ranking["candidates"] as? [[String: Any]] else { continue }
            let lines = first["reasonLines"] as? [Any] ?? []
            let top = candidates.prefix(3).map { cand -> String in
                let sub = (cand["subcategory"] as? String).map { " › \($0)" } ?? ""
                let reasons = (cand["reasons"] as? [String] ?? []).joined(separator: ",")
                return "\(cand["categoryID"] as? String ?? "?")\(sub) \(cand["score"] as? Int ?? 0) [\(reasons)]"
            }
            let line = lines.first as? String ?? "—"
            print("  \(c["name"] as? String ?? "?"): \(top.joined(separator: " | ")) · \(ranking["evidence"] as? String ?? "?") · \(line)")
        }
    }
}
