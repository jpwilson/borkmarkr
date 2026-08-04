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
/// It is a *suggestion* by contract. Every caller must let the user override it
/// before saving, and returning nothing is a valid, honest answer — better than
/// confidently filing a link under the wrong thing.
enum Categorizer {

    struct Suggestion: Sendable {
        var categoryID: String?
        var subcategory: String?
        var tags: [String]
    }

    // MARK: - Curated signals

    /// Extra phrases that should hit a category but don't appear in any of its
    /// subcategory names. Keep this small — the derived index does the bulk.
    private static let categoryHints: [String: [String]] = [
        "fitness": ["workout", "gym", "reps", "sets", "squat", "deadlift", "bench", "pull up", "push up", "marathon", "5k", "10k", "hypertrophy", "warm up"],
        "nutrition": ["protein", "calorie", "macro", "creatine", "electrolyte", "carb", "keto", "diet"],
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
            for sub in category.subs {
                let phrase = normalise(sub)
                let trimmed = phrase.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 3, !stopWords.contains(trimmed) else { continue }
                // A subcategory name is a precise signal — weight it above a
                // bare category hint.
                out.append(Matcher(phrase: phrase, label: sub.lowercased(),
                                   categoryID: category.id,
                                   subcategory: sub, weight: trimmed.count + 6))
            }

            for hint in categoryHints[category.id] ?? [] {
                out.append(Matcher(phrase: normalise(hint), label: hint,
                                   categoryID: category.id,
                                   subcategory: nil, weight: hint.count + 2))
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
        // over "health".
        return strongest.values.sorted { $0.phrase.count > $1.phrase.count }
    }()

    // MARK: - Public

    static func suggest(url: URL, title: String, text: String? = nil) -> Suggestion {
        let platform = Platform.detect(from: url)

        // Authored text (title, post body) is a far better signal than a URL
        // slug, so it scores at full weight and the URL at half. Without this
        // split, a stray word in a path can outvote the actual headline.
        let authored = normalise([title, text ?? ""].joined(separator: " "))
        let fromURL = normaliseURL(url)

        var categoryScores: [String: Int] = [:]
        var subScores: [String: (sub: String, score: Int)] = [:]
        var matchedLabels: [String] = []

        for matcher in matchers {
            let inAuthored = authored.contains(matcher.phrase)
            let inURL = fromURL.contains(matcher.phrase)
            guard inAuthored || inURL else { continue }

            let weight = inAuthored ? matcher.weight : max(1, matcher.weight / 2)
            categoryScores[matcher.categoryID, default: 0] += weight
            matchedLabels.append(matcher.label)

            if let sub = matcher.subcategory {
                let current = subScores[matcher.categoryID]
                if weight > (current?.score ?? 0) {
                    subScores[matcher.categoryID] = (sub, weight)
                }
            }
        }

        guard let (bestCategory, bestScore) = categoryScores.max(by: { $0.value < $1.value }),
              bestScore >= 6   // below this it's a coincidental substring, not a signal
        else {
            // Honest "don't know". Uncategorised is a real state and the
            // Explore screen surfaces it, so nothing is lost.
            return Suggestion(categoryID: nil, subcategory: nil, tags: [platform.name.lowercased()])
        }

        let unique: Set<String> = Set(matchedLabels.filter { $0.count > 3 })
        let ranked: [String] = unique.sorted { $0.count > $1.count }
        let topTags: [String] = Array(ranked.prefix(3)).sorted()

        return Suggestion(
            categoryID: bestCategory,
            subcategory: subScores[bestCategory]?.sub,
            tags: topTags + [platform.name.lowercased()]
        )
    }

    /// Readable title from a URL slug, used when no caption came through.
    static func fallbackTitle(for url: URL) -> String {
        let platform = Platform.detect(from: url)
        let slug = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .last { $0.count > 3 && !$0.allSatisfy(\.isNumber) }

        guard let slug else {
            let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
            return platform == .web && !host.isEmpty
                ? "Article from \(host)"
                : "Saved \(platform.defaultKind.rawValue) from \(platform.name)"
        }

        return slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Author is a handle for social posts, a hostname for the web.
    static func fallbackAuthor(for url: URL) -> String? {
        let host = (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return host.isEmpty ? nil : host
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
