import Foundation

/// Suggests `{category, subcategory, tags}` for a link.
///
/// **Engineering deviation.** The handoff's `detectPreview` is a five-branch
/// if/else covering fitness, food, health, money and wellness — it files
/// everything else as `learning / How-to`, and it fakes a 950ms delay to look
/// like it's thinking. With 50 categories that approach doesn't scale, and
/// hand-writing a keyword table for ~700 subcategories would rot the moment the
/// taxonomy changes.
///
/// Instead the index is **derived from the taxonomy itself**: every
/// subcategory name is already a keyword ("Running", "Mobility", "Cold
/// exposure"), so 700 matchers come for free and stay correct automatically
/// when categories are added. On top of that sits a small curated layer for the
/// cases where the label isn't what people actually write — "HIIT" appears as
/// "interval", "ETFs & index funds" as "etf", "Mental health" as "burnout".
///
/// **What it reads, and what it refuses to.** Two real saves showed the first
/// version filing a hip-mobility reel under *Relationships › Communication*
/// and a foot-training reel under *Science › Space*. Both were the matcher
/// doing exactly what it was told: an Instagram title is
/// `"Author | Bio on Instagram: "caption""`, so the author's *bio* scored like
/// a headline; the caption's opening hook ("I'm not a relationship expert
/// but…") scored like its subject; and a subcategory called "Communication" or
/// "Space" — a plain English word — was treated as if it were as specific as
/// "Sourdough". Meanwhile the one thing the author had actually filed the post
/// under, `#mobility #flatfeet #footarch`, was never read. So now:
///
/// - the title is unwrapped (`SocialTitle`) and only the **caption** is matched
///   at full weight; author and bio are a half-weight hint, like the URL;
/// - **hashtags** are the author's own filing and score double;
/// - a **hook clause** ("nobody tells you…", "I'm not an expert but…") is
///   dropped before matching;
/// - **generic** subcategory names only count once the category already has a
///   specific hit, and then at half weight;
/// - a suggestion is only *confident* on a real headline match, two
///   independent specific hits, or a hashtag that names a subtopic. Everything
///   else is a thin guess and is shown as one.
///
/// It is a *suggestion* by contract. Every caller must let the user override it
/// before saving, and returning nothing is a valid, honest answer — better than
/// confidently filing a link under the wrong thing.
enum Categorizer {

    struct Suggestion: Sendable {
        var categoryID: String?
        var subcategory: String?
        var tags: [String]

        /// Weight of the keyword evidence behind `categoryID`. Zero when
        /// nothing matched. Exposed so callers can tell "I'm sure this is
        /// Fitness" from "one short word happened to line up", which is the
        /// difference between showing the answer and asking a better one.
        var score: Int = 0

        /// Above this, the offline answer is worth trusting on its own.
        ///
        /// Calibrated against the matcher weights: a subcategory match scores
        /// `phrase.count + 6`, halved when it only appears in the URL or the
        /// author line, doubled when it is one of the post's own hashtags.
        /// So the shortest possible single caption match ("Bags" → 10) sits
        /// below this, a real headline match ("Mobility" → 14) or two
        /// independent signals clear it, and evidence that never touched the
        /// caption or the hashtags is capped just under it — see `suggest`.
        static let confidentScore = 14

        /// How much to trust this. Drives the copy above the topic chip:
        /// `.strong` is "Sorted for you", `.thin` is "Our best guess", `.none`
        /// is "Where does this go?". Derived from `score` so the JS port only
        /// has to agree on one number.
        enum Evidence: String, Sendable { case none, thin, strong }

        var evidence: Evidence {
            guard categoryID != nil else { return .none }
            return score >= Self.confidentScore ? .strong : .thin
        }

        var isConfident: Bool { evidence == .strong }
    }

    // MARK: - Curated signals

    /// Extra phrases that should hit a category but don't appear in any of its
    /// subcategory names. Keep this small — the derived index does the bulk.
    private static let categoryHints: [String: [String]] = [
        "fitness": ["workout", "gym", "reps", "sets", "squat", "deadlift", "bench", "pull up", "push up", "marathon", "5k", "10k", "hypertrophy", "warm up", "exercise", "hips"],
        "nutrition": ["protein", "calorie", "macro", "creatine", "electrolyte", "carb", "keto", "diet", "nutrition"],
        "health": ["doctor", "clinic", "diagnos", "prescription", "blood pressure", "cholesterol", "thyroid", "inflammation", "chronic"],
        "mentalhealth": ["burnout", "panic attack", "overthink", "nervous system", "cbt", "dopamine", "mental load"],
        "wellness": ["routine", "ritual", "calm", "reset", "wind down", "grounding", "sauna", "ice bath"],
        "recipes": ["recipe", "ingredient", "cook", "bake", "dinner", "lunch", "air fry", "sheet pan", "leftovers"],
        "fooddrink": ["restaurant", "cafe", "espresso", "latte", "sourdough", "tasting", "michelin", "brew"],
        "money": ["budget", "debt", "salary", "paycheck", "emergency fund", "net worth", "frugal", "cost of living"],
        "investing": ["etf", "index fund", "portfolio", "s&p", "dividend", "brokerage", "compound", "bear market", "bull market"],
        "crypto": ["bitcoin", "btc", "ethereum", "eth", "wallet", "blockchain", "defi", "altcoin", "on chain"],
        "business": ["startup", "founder", "revenue", "mrr", "arr", "b2b", "saas", "margin", "customer"],
        "marketing": ["seo", "funnel", "conversion", "copywriting", "ad spend", "roas", "landing page", "email list"],
        "creator": ["algorithm", "views", "subscriber", "follower", "thumbnail", "monetiz", "brand deal", "went viral", "content strategy", "hook"],
        "career": ["resume", "cv", "interview", "salary negotiation", "promotion", "manager", "linkedin", "layoff", "onboarding"],
        "learning": ["study", "revision", "flashcard", "anki", "exam", "learn", "tutorial", "explained"],
        "ai": ["ai", "llm", "gpt", "claude", "prompt", "agent", "model", "machine learning", "diffusion", "rag", "fine tune"],
        "coding": ["code", "coding", "python", "javascript", "typescript", "swift", "react", "api", "git", "compiler", "bug", "refactor"],
        "tech": ["iphone", "android", "laptop", "headphone", "usb", "router", "spec", "unboxing", "battery life"],
        "photovideo": ["camera", "lens", "aperture", "iso", "shutter", "lightroom", "premiere", "davinci", "lut", "bokeh", "cinematic"],
        "home": ["living room", "bedroom", "kitchen", "renovat", "interior", "floor plan", "square feet", "landlord"],
        "diy": ["fix", "repair", "leak", "drill", "screw", "caulk", "stud", "wiring"],
        "crafts": ["handmade", "craft", "carve", "stitch", "loom", "kiln", "epoxy", "3d print", "cnc"],
        "cleaning": ["clean", "declutter", "tidy", "organis", "organiz", "stain", "mould", "mold", "vacuum"],
        "trades": ["weld", "apprentice", "jobsite", "contractor", "hvac", "electrician", "plumber", "quote"],
        "cars": ["car", "engine", "turbo", "brake", "tyre", "tire", "horsepower", "ev", "tesla", "mileage", "dealership", "motorbike", "f1"],
        "sports": ["match", "league", "playoff", "goal", "touchdown", "tackle", "referee", "season", "transfer", "fixture"],
        "outdoors": ["trail", "summit", "campsite", "tent", "backpack", "belay", "catch", "tide", "gps"],
        "nature": ["species", "habitat", "migration", "ecosystem", "forest", "reef", "storm", "eclipse"],
        "garden": ["soil", "plant", "seedling", "prune", "mulch", "harvest", "bloom", "weed"],
        "homestead": ["chicken", "goat", "canning", "ferment", "off grid", "rainwater", "smallholding"],
        "travel": ["flight", "airport", "hostel", "airbnb", "itinerary", "layover", "passport", "backpacking", "visa"],
        "fashion": ["outfit", "wardrobe", "fit check", "thrift", "sneaker", "denim", "tailor", "style"],
        "beauty": ["skincare", "serum", "retinol", "spf", "moisturis", "moisturiz", "foundation", "mascara", "glow"],
        "grooming": ["haircut", "barber", "beard", "shave", "fade", "hairline", "shampoo"],
        "relationships": ["partner", "girlfriend", "boyfriend", "husband", "wife", "argument", "attachment", "ex ", "situationship"],
        "parenting": ["toddler", "kid", "child", "tantrum", "nursery", "school run", "screen time"],
        "babyprep": ["pregnan", "trimester", "newborn", "breastfeed", "labour", "labor", "ultrasound", "postpartum"],
        "pets": ["dog", "cat", "puppy", "kitten", "vet", "leash", "litter", "breed"],
        "comedy": ["funny", "meme", "joke", "prank", "fail", "skit", "comedian", "lmao"],
        "filmtv": ["movie", "film", "series", "episode", "season finale", "netflix", "trailer", "cast", "director"],
        "books": ["book", "novel", "read", "author", "chapter", "booktok", "bestseller"],
        "music": ["song", "album", "chord", "guitar", "piano", "beat", "mix", "vocal", "playlist", "bpm"],
        "gaming": ["game", "gameplay", "boss", "loadout", "patch", "fps", "rpg", "steam", "console"],
        "anime": ["anime", "manga", "shonen", "otaku", "cosplay", "webtoon", "arc"],
        "art": ["draw", "sketch", "paint", "canvas", "palette", "typography", "figma", "illustration"],
        "science": ["study finds", "research", "experiment", "theory", "quantum", "neuron", "galaxy", "molecul"],
        "history": ["century", "ancient", "empire", "war", "medieval", "archaeolog", "historic"],
        "news": ["election", "government", "policy", "parliament", "senate", "breaking", "president"],
        "beliefs": ["god", "bible", "quran", "faith", "prayer", "philosoph", "meaning of life", "conspiracy"],
        "truecrime": ["murder", "detective", "suspect", "trial", "verdict", "unsolved", "victim", "forensic"],
    ]

    /// Subcategory names that are ordinary English words rather than subjects.
    ///
    /// "Communication", "Training", "Space", "Reviews" each sit under exactly
    /// one topic in the taxonomy, so the derived index treated them as precise
    /// as "Sourdough" — and a caption that said "communication" filed under
    /// Relationships whatever it was about. These still name the *subtopic*
    /// once the topic is established by something specific, but on their own
    /// they carry no evidence at all. Judgement call per name; the test is
    /// "would this word, alone, tell a person which of the 50 topics it was?"
    /// Mirrored verbatim in `docs/import.js`.
    static let genericSubcategories: Set<String> = [
        "Accessories", "Activities", "Adoption", "Analysis", "Analytics", "Architecture",
        "Artists", "Audio", "Authors", "Banking", "Bathroom", "Bathrooms", "Behaviour",
        "Betting", "Bills", "Birth", "Builds", "Business", "Career", "Case studies",
        "Cases", "Classics", "Collecting", "Colour", "Communication", "Community",
        "Composition", "Conditions", "Conflict", "Content", "Cost saving", "Courses",
        "Credit", "Deals", "Development", "Directors", "Discipline", "Discoveries",
        "Documentaries", "Economy", "Editing", "Email", "Environment", "Equipment",
        "Estimating", "Ethics", "Explainers", "Family", "Feeding", "Fibre", "Finance",
        "Focus", "Formal", "Gear", "Grooming", "Guides", "Habits", "Hidden gems",
        "Highlights", "Hiring", "Hydration", "Impressions", "Ingredients",
        "Inspiration", "Insurance", "Investigations", "Kitchen", "Kitchens", "Leadership",
        "Legal", "Lighting", "Live", "Local", "Maintenance", "Management", "Maps",
        "Markets", "Maths", "Meals", "Meaning", "Media", "Medicine", "Memory",
        "Milestones", "Mining", "Mixing", "Mobile", "Modern", "Moving", "Names",
        "Navigation", "Networking", "News", "Nursery", "Nutrition", "Ocean", "Operations",
        "Options", "Packing", "Pests", "Phones", "Platform news", "Policy", "Portfolio",
        "Portfolios", "Portraits", "Positioning", "Pricing", "Privacy",
        "Production", "Productivity", "Products", "Programming", "Quick fixes",
        "Recommendations", "Recovery", "Regulation", "Rentals", "Repairs", "Research",
        "Restoration", "Reviews", "Risk", "Routines", "Safety", "Saving", "Scams",
        "Scenes", "School", "Scripting", "Seasonal", "Seasonal jobs", "Seeds", "Series",
        "Setups", "Skills", "Small spaces", "Solar", "Space", "Storage", "Storytime",
        "Strategy", "Streaming", "Stress", "Studios", "Styling", "Sugar", "Summaries",
        "Suppliers", "Sustainable", "Symptoms", "Teens", "Testing", "Theory", "Tips",
        "Tools", "Trading", "Training", "Trains", "Treatments", "Tutorials", "Twins",
        "Weather", "Wholesome", "Workplace", "World", "Writing",
    ]

    /// Opening clauses that sell the post rather than describe it. When the
    /// caption's first clause contains one of these it is dropped before
    /// matching — "I'm not a relationship expert but…" is about hips, and
    /// "nobody tells you this about money" is usually about bread.
    static let hookPhrases: [String] = [
        "expert", "secret", "nobody tells you", "no one tells you", "nobody talks about",
        "no one talks about", "you won't believe", "the truth about", "changed my life",
        "unpopular opinion", "hot take", "stop doing", "wait for it", "this is your sign",
    ]

    /// Hashtags that file nothing: platform furniture and reach-bait.
    static let hashtagNoise: Set<String> = [
        "fyp", "fypage", "foryou", "foryoupage", "viral", "trending", "explore", "explorepage",
        "reels", "reel", "reelsinstagram", "shorts", "tiktok", "instagram", "youtube", "video",
        "follow", "like", "likes", "share", "save", "new", "love", "ad", "sponsored",
    ]

    /// Words too generic to carry a signal on their own.
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "your", "you", "how", "what", "why",
        "tips", "guide", "best", "top", "new", "all", "out", "amp", "of", "in",
        "on", "to", "a", "an", "my", "is", "it", "this", "that", "at", "by",
    ]

    // MARK: - Derived index

    private struct Matcher {
        /// Stemmed + space-padded, used for matching.
        let phrase: String
        /// Original human spelling, used when this becomes a visible tag —
        /// users should never see "unsolv" because the stemmer ate the word.
        let label: String
        let categoryID: String
        let subcategory: String?
        let weight: Int
        /// A plain-word subcategory name: names the subtopic, proves nothing.
        let generic: Bool
    }

    /// One matcher found in the text, and where.
    private struct Hit {
        let matcher: Matcher
        let weight: Int
        let fromHashtag: Bool
        /// Found in the caption, the body or a hashtag — as opposed to only
        /// in the URL or the author line.
        let authored: Bool
    }

    /// Routing segments that appear in nearly every social URL and carry no
    /// topical meaning. Left in, they both skew scoring and surface as tags
    /// ("watch", "status", "reel").
    /// Kept deliberately tight. An earlier version included "index", which
    /// silently ate the "index" of "index fund" and made every ETF article
    /// uncategorised — a token only counts as noise if it is pure routing AND
    /// implausible as a content word.
    private static let urlNoise: Set<String> = [
        "watch", "shorts", "video", "status", "reel", "reels", "comments",
        "blog", "html", "php", "www", "com", "net", "org", "amp", "embed",
    ]

    /// Built once. Subcategory names become matchers automatically, so the
    /// index grows with the taxonomy and never falls out of sync with it.
    private static let matchers: [Matcher] = {
        var out: [Matcher] = []

        for category in Taxonomy.all {
            // The topic's own name and id — "#travel", "#diy", "fitness" —
            // between a hint and a subcategory in weight: one word naming the
            // topic is a fair guess, a hashtag naming it is a good one.
            for name in Set([category.name, category.id]) {
                let phrase = normalise(name)
                let trimmed = phrase.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 3, !stopWords.contains(trimmed) else { continue }
                out.append(Matcher(phrase: phrase, label: name.lowercased(),
                                   categoryID: category.id,
                                   subcategory: nil, weight: trimmed.count + 4,
                                   generic: false))
            }

            for sub in category.subs {
                let phrase = normalise(sub)
                let trimmed = phrase.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 3, !stopWords.contains(trimmed) else { continue }
                // A subcategory name is a precise signal — weight it above a
                // bare category hint.
                out.append(Matcher(phrase: phrase, label: sub.lowercased(),
                                   categoryID: category.id,
                                   subcategory: sub, weight: trimmed.count + 6,
                                   generic: genericSubcategories.contains(sub)))
            }

            for hint in categoryHints[category.id] ?? [] {
                out.append(Matcher(phrase: normalise(hint), label: hint,
                                   categoryID: category.id,
                                   subcategory: nil, weight: hint.count + 2,
                                   generic: false))
            }
        }

        // Dedupe per (category, phrase), keeping the strongest.
        //
        // Curated hints frequently stem to the same token as one of their own
        // category's subcategories — "paint" is both Art's hint and Art's
        // subcategory "Painting". Counting both double-scores that category and
        // it wins matches it shouldn't: a car-detailing video scored higher for
        // Art (paint + Painting) than for Cars (detailing + car).
        var strongest: [String: Matcher] = [:]
        for matcher in out {
            let key = matcher.categoryID + "|" + matcher.phrase
            if let existing = strongest[key], existing.weight >= matcher.weight { continue }
            // Prefer the variant that carries a subcategory — it's more specific.
            if let existing = strongest[key], existing.subcategory != nil, matcher.subcategory == nil { continue }
            strongest[key] = matcher
        }

        // Longest first so "index fund" wins over "fund" and "mental health"
        // over "health". Ties break on the phrase, then the category, so the
        // order is the same in every process — the JS port sorts identically.
        return strongest.values.sorted {
            if $0.phrase.count != $1.phrase.count { return $0.phrase.count > $1.phrase.count }
            if $0.phrase != $1.phrase { return $0.phrase < $1.phrase }
            return $0.categoryID < $1.categoryID
        }
    }()

    // MARK: - Public

    /// Where a link belongs, from everything the caller has read about it.
    ///
    /// - `title`: the page or post title, wrapped or not — an Instagram
    ///   `"Author | Bio on Instagram: "caption""` is unwrapped here.
    /// - `text`: the post body, for X and Threads.
    /// - `description`: `og:description`, which on Instagram and TikTok is the
    ///   full caption with its hashtags.
    /// - `hashtags`: pass them if already extracted; otherwise they are read
    ///   out of the title, text and description.
    /// - `author`: a subject hint only, matched at half weight alongside the
    ///   author and bio unwrapped from the title.
    static func suggest(
        url: URL,
        title: String,
        text: String? = nil,
        description: String? = nil,
        hashtags: [String]? = nil,
        author: String? = nil
    ) -> Suggestion {
        let unwrapped = SocialTitle.unwrap(title)
        let caption = unwrapped.isSocial ? (unwrapped.caption ?? "") : title
        let body = SocialTitle.caption(fromDescription: description ?? "")
        let tags = hashtags ?? self.hashtags(in: [title, text ?? "", description ?? ""])

        // What the author wrote scores at full weight, with the hook clause
        // taken off the front. The URL and the author line are hints at half
        // weight: a stray word in a path or a bio must never outvote the
        // caption. Hashtags are the author's own filing and score double.
        let authored = normalise([withoutHook(caption), text ?? "", withoutHook(body)].joined(separator: " "))
        let fromURL = normaliseURL(url)
        let authorLine = [author, unwrapped.author, unwrapped.bio].compactMap { $0 }.joined(separator: " ")
        let fromAuthor = normalise(authorLine)
        let fromTags = normalise(tags.joined(separator: " "))

        var hits: [String: [Hit]] = [:]
        for matcher in matchers {
            let inTags = fromTags.contains(matcher.phrase)
            let inAuthored = authored.contains(matcher.phrase)
            let inHint = fromURL.contains(matcher.phrase) || fromAuthor.contains(matcher.phrase)
            guard inTags || inAuthored || inHint else { continue }

            let weight = inTags ? matcher.weight * 2
                : inAuthored ? matcher.weight
                : max(1, matcher.weight / 2)
            hits[matcher.categoryID, default: []].append(
                Hit(matcher: matcher, weight: weight, fromHashtag: inTags, authored: inTags || inAuthored)
            )
        }

        var categoryScores: [String: Int] = [:]
        var subScores: [String: (sub: String, score: Int)] = [:]

        for (categoryID, found) in hits {
            let specific = found.filter { !$0.matcher.generic }
            // A generic name on its own is not evidence of anything.
            guard !specific.isEmpty else { continue }
            var score = 0
            for hit in found {
                let weight = hit.matcher.generic ? max(1, hit.weight / 2) : hit.weight
                score += weight
                if let sub = hit.matcher.subcategory, weight > (subScores[categoryID]?.score ?? 0) {
                    subScores[categoryID] = (sub, weight)
                }
            }
            // Two independent signals from the author's own words are worth
            // more than their sum — "gym" and "5k" are each a small word, but
            // together they are not a coincidence.
            let independent = specific.filter(\.authored).count
            score += 6 * max(0, independent - 1)
            // Evidence that never touched the caption or the hashtags — a slug,
            // a bio — can be a guess, never a confident one.
            if independent == 0 { score = min(score, Suggestion.confidentScore - 1) }
            categoryScores[categoryID] = score
        }

        // Ties go to taxonomy order rather than to whatever the hash table felt like.
        var best: (id: String, score: Int)?
        for category in Taxonomy.all {
            guard let score = categoryScores[category.id], score > (best?.score ?? 0) else { continue }
            best = (category.id, score)
        }
        guard let best, best.score >= 6 else {   // below this it's a coincidental substring, not a signal
            // Honest "don't know". Uncategorised is a real state and the
            // Explore screen surfaces it, so nothing is lost.
            return Suggestion(categoryID: nil, subcategory: nil, tags: [])
        }

        return Suggestion(
            categoryID: best.id,
            subcategory: subScores[best.id]?.sub,
            tags: tagList(for: hits[best.id] ?? [], hashtags: tags),
            score: best.score
        )
    }

    /// `#\w+` from any of the given strings, lowercased, in order, deduped,
    /// minus platform furniture ("#fyp") and site names. Both platforms read
    /// hashtags the same way so the same post files the same on each.
    static func hashtags(in sources: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "#([\\p{L}\\p{N}_]+)") else { return [] }
        var seen: Set<String> = []
        var out: [String] = []
        for source in sources where source.contains("#") {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                guard let captured = Range(match.range(at: 1), in: source) else { continue }
                let tag = String(source[captured]).lowercased()
                guard tag.count >= 3, !hashtagNoise.contains(tag), !Platform.isSiteName(tag),
                      seen.insert(tag).inserted else { continue }
                out.append(tag)
            }
        }
        return out
    }

    /// Tags for the winning category only. The old list took every matched
    /// label from every category, which is how a foot-mobility reel got
    /// `#experiment #grounding`: labels from the categories that *lost*.
    /// Hashtag hits lead, then the longest labels, then up to two of the
    /// author's own hashtags that matched nothing — "#flatfeet" is a better
    /// tag than anything we could derive.
    private static func tagList(for hits: [Hit], hashtags: [String]) -> [String] {
        func ranked(_ labels: [String]) -> [String] {
            Array(Set(labels)).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        }
        let fromTags = ranked(hits.filter { $0.fromHashtag && $0.matcher.label.count > 3 }.map(\.matcher.label))
        let others = ranked(hits.filter { !$0.fromHashtag && $0.matcher.label.count > 3 }.map(\.matcher.label))
            .filter { !fromTags.contains($0) }
        var out = Array((fromTags + others).prefix(3)).filter { !Platform.isSiteName($0) }

        let loose = hashtags.filter { tag in
            !out.contains(tag) && !hits.contains { $0.matcher.label == tag }
                && tag.allSatisfy(\.isLetter)
        }
        for tag in loose.prefix(2) where out.count < 4 { out.append(tag) }
        return out
    }

    /// Readable title from a URL, used only until real metadata arrives.
    ///
    /// Earlier this took the last path component longer than three characters,
    /// which on `x.com/levelsio/status/123` produced the title **"Status"** —
    /// a routing word presented as if it described the post. Worse than blank,
    /// because it looks deliberate.
    ///
    /// Now: routing segments are excluded outright, a real hyphenated slug wins
    /// if there is one, and otherwise we say something honest about where it
    /// came from rather than inventing a subject.
    static func fallbackTitle(for url: URL) -> String {
        let platform = Platform.detect(from: url)
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        // A hyphen/underscore almost always means a human-readable slug.
        if let slug = segments.last(where: { seg in
            (seg.contains("-") || seg.contains("_"))
                && seg.count > 6
                && !urlNoise.contains(seg.lowercased())
        }) {
            return slug
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".html", with: "")
                .capitalized
        }

        // Social posts: name the author, which is the one thing the URL does
        // reliably tell us.
        if let handle = segments.first(where: { $0.hasPrefix("@") })
            ?? segments.first(where: { seg in
                seg.count > 1
                    && !urlNoise.contains(seg.lowercased())
                    && !seg.allSatisfy(\.isNumber)
                    && platform != .web
            }) {
            let clean = handle.hasPrefix("@") ? handle : "@\(handle)"
            return "\(clean) on \(platform.name)"
        }

        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return host.isEmpty ? "Untitled brk" : "Link from \(host)"
    }

    /// True when the title is one we generated rather than one that came from
    /// the page or the user — i.e. safe to overwrite once real metadata lands.
    static func isDerivedTitle(_ title: String, for url: URL) -> Bool {
        title.isEmpty || title == fallbackTitle(for: url)
    }

    /// Author is a handle for social posts, a hostname for the web.
    static func fallbackAuthor(for url: URL) -> String? {
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return host.isEmpty ? nil : host
    }

    // MARK: - Text

    /// The caption minus its opening hook, when the opening clause is one.
    ///
    /// Only the first clause is ever dropped, and only when it contains a
    /// phrase from `hookPhrases`: a caption that *is* about experts keeps
    /// every mention after the first comma. A one-clause caption is kept
    /// whole — a hook with nothing after it is all we have.
    static func withoutHook(_ caption: String) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lowered = trimmed.lowercased()

        var cut = lowered.endIndex
        for boundary in [". ", "! ", "? ", ", ", "; ", ": ", " but ", " — ", " – ", " - ", "\n", "…"] {
            if let range = lowered.range(of: boundary), range.lowerBound < cut { cut = range.lowerBound }
        }
        guard cut < lowered.endIndex else { return trimmed }
        let clause = lowered[..<cut]
        guard hookPhrases.contains(where: { clause.contains($0) }) else { return trimmed }
        // `lowercased()` can change character counts in exotic scripts, so cut
        // by offset rather than by sharing the index.
        let offset = lowered.distance(from: lowered.startIndex, to: cut)
        var tail = trimmed[trimmed.index(trimmed.startIndex, offsetBy: min(offset, trimmed.count))...]
        let punctuation = ".!?,;:—–- \n\t…"
        while let first = tail.first, punctuation.contains(first) { tail.removeFirst() }
        return String(tail)
    }

    /// Slugs and punctuation become spaces so "/p/five-hip-mobility-drills"
    /// matches "mobility", then every token is stemmed.
    ///
    /// Stemming matters more than it looks: without it "stretches" misses the
    /// subcategory "Stretching", "detailed" misses "Detailing", and "algorithm"
    /// misses "Algorithms" — real titles almost never use the exact inflection
    /// a taxonomy label happens to be written in. Both sides go through the
    /// same function, so they only have to agree with each other, not with
    /// English.
    private static func normalise(_ raw: String) -> String {
        let lowered = raw.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let separators = CharacterSet(charactersIn: "-_/.?=&+%#@:,!|()[]{}\"'’\n\t ")
        let tokens = lowered
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .map(stem)
        return " " + tokens.joined(separator: " ") + " "
    }

    /// Same normalisation, minus the routing segments every social URL carries.
    private static func normaliseURL(_ url: URL) -> String {
        let raw = [url.path, url.host ?? ""].joined(separator: " ")
        let tokens = normalise(raw)
            .split(separator: " ")
            .map(String.init)
            .filter { !urlNoise.contains($0) }
        return " " + tokens.joined(separator: " ") + " "
    }

    /// Deliberately crude suffix stripping. A real Porter stemmer would be
    /// overkill — this only has to make two strings from the same word family
    /// collapse to the same token.
    private static func stem(_ word: String) -> String {
        var w = word
        guard w.count > 4 else { return w }
        for suffix in ["ing", "ies", "ed", "es", "s"] where w.hasSuffix(suffix) {
            // Don't strip into a stub: "sets" -> "set", but "ies" -> "ie".
            if w.count - suffix.count >= 3 {
                w.removeLast(suffix.count)
                if suffix == "ies" { w.append("y") }
            }
            break
        }
        return w
    }
}

/// Takes apart the titles social platforms publish as `og:title`.
///
/// Instagram: `"Sophie Rinkenbach | The Mobility Framework on Instagram: "I'm
/// not a relationship expert…""` — author, then a bio after the pipe, then the
/// caption in quotes. X: `"Paul Graham on X: "How to do great work…" / X"`.
/// TikTok and Threads: `"Name on TikTok"` with the caption in the description.
/// Three different strings, one shape: *who* wrote it, *what they call
/// themselves*, and *what they said*. Filing must read the last of those and
/// treat the first two as hints, which is impossible while they are one string.
///
/// Pure and platform-agnostic on purpose so it can be tested on macOS and
/// mirrored in the web app.
enum SocialTitle {

    struct Parts: Equatable, Sendable {
        var author: String?
        var bio: String?
        var caption: String?
        /// True when the title had the `… on <Platform>` shape at all — so a
        /// wrapped title with no caption is not mistaken for a plain headline.
        var isSocial: Bool
    }

    private static let platforms = [
        "Instagram", "X", "Twitter", "TikTok", "Threads", "Facebook", "LinkedIn", "Pinterest",
    ]

    static func unwrap(_ title: String) -> Parts {
        var raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // X appends its own name: `… " / X`.
        for suffix in [" / X", " / Twitter"] where raw.hasSuffix(suffix) {
            raw = String(raw.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        guard let (head, rest) = split(raw) else {
            return Parts(author: nil, bio: nil, caption: nil, isSocial: false)
        }

        // `Author | Bio` — the bio is whatever follows the first pipe.
        var author = head
        var bio: String?
        if let pipe = head.range(of: " | ") {
            author = String(head[..<pipe.lowerBound])
            bio = String(head[pipe.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // `Name (@handle)` — the handle adds nothing the URL doesn't.
        if let paren = author.range(of: " (@") {
            author = String(author[..<paren.lowerBound])
        }
        author = author.trimmingCharacters(in: .whitespaces)

        var caption: String?
        if var quoted = rest {
            quoted = quoted.trimmingCharacters(in: .whitespaces)
            if quoted.hasPrefix(":") { quoted.removeFirst() }
            let quotes = CharacterSet(charactersIn: "\"“” \n")
            quoted = quoted.trimmingCharacters(in: quotes)
            if !quoted.isEmpty { caption = quoted }
        }

        return Parts(author: author.isEmpty ? nil : author, bio: bio, caption: caption, isSocial: true)
    }

    /// Instagram's `og:description` is
    /// `"1,204 likes, 31 comments - handle on August 28, 2026: "caption""`.
    /// The counts and the date are furniture; the caption is the content.
    static func caption(fromDescription description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: "^[\\d.,]+[KkMm]? (?:likes?|reactions?), [\\d.,]+[KkMm]? comments? - .+? on .+?: ?[\"“]?"
        ) else { return trimmed }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let matched = Range(match.range, in: trimmed) else { return trimmed }
        return String(trimmed[matched.upperBound...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“” \n"))
    }

    /// `(head, rest-after-the-seam)` when the title has an `… on <Platform>`
    /// seam that ends the head: `… on X: "…"`, `… on TikTok`, or
    /// `… on Instagram: "…"`. "on Instagram" mid-sentence is not one.
    private static func split(_ raw: String) -> (String, String?)? {
        for platform in platforms {
            let seam = " on \(platform)"
            guard let range = raw.range(of: seam) else { continue }
            let after = raw[range.upperBound...]
            guard after.isEmpty || after.hasPrefix(":") else { continue }
            let head = String(raw[..<range.lowerBound])
            guard !head.isEmpty else { continue }
            return (head, after.isEmpty ? nil : String(after))
        }
        return nil
    }
}
