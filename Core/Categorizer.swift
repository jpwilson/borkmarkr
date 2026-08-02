import Foundation

/// Suggests a category, subcategory and tags for a link.
///
/// The design prototype simulated this with hardcoded results. This is a real
/// keyword scorer over the URL slug and whatever title we have — no network, no
/// API key, instant, works offline. It is deliberately a *suggestion*: the brief
/// said "AI suggests, I can override or add tags", so every result is editable
/// before saving.
///
/// Swapping in a real model later means replacing `suggest(...)` only; callers
/// already treat the result as advisory.
enum Categorizer {

    struct Suggestion {
        var categoryID: String?
        var subcategory: String?
        var tags: [String]
    }

    /// category id -> (subcategory -> keywords). A hit on a subcategory keyword
    /// also counts as a hit for its parent category.
    private static let keywords: [String: [String: [String]]] = [
        "fitness": [
            "Running": ["run", "running", "5k", "10k", "marathon", "pace", "cadence", "sprint"],
            "Strength": ["strength", "squat", "deadlift", "bench", "lifting", "hypertrophy", "gym"],
            "Mobility": ["mobility", "hip", "shoulder", "range of motion", "movement"],
            "Stretches": ["stretch", "stretching", "hamstring", "flexibility"],
            "Drills": ["drill", "drills", "technique", "form"],
            "Recovery": ["recovery", "rest day", "sore", "foam roll", "ice bath"],
        ],
        "health": [
            "Sleep": ["sleep", "insomnia", "circadian", "melatonin", "nap"],
            "Longevity": ["longevity", "lifespan", "healthspan", "aging", "ageing"],
            "Mental health": ["anxiety", "depression", "burnout", "stress", "therapy"],
            "Kids' health": ["toddler", "infant", "child health", "kids health", "paediatric", "pediatric"],
            "Bloodwork": ["blood test", "bloodwork", "biomarker", "cholesterol", "a1c"],
        ],
        "medical": [
            "Conditions": ["diabetes", "asthma", "arthritis", "thyroid", "syndrome", "disease"],
            "Medications": ["dose", "dosage", "medication", "statin", "antibiotic", "mg "],
            "Procedures": ["surgery", "procedure", "operation", "biopsy", "scan"],
            "Research": ["study", "trial", "pubmed", "meta-analysis", "peer review"],
        ],
        "nutrition": [
            "Protein": ["protein", "whey", "amino", "creatine"],
            "Supplements": ["supplement", "vitamin", "magnesium", "omega"],
            "Fasting": ["fasting", "fast", "intermittent", "omad"],
            "Gut health": ["gut", "microbiome", "probiotic", "fiber", "fibre"],
            "Hydration": ["hydration", "electrolyte", "water intake"],
        ],
        "cooking": [
            "Healthy": ["healthy recipe", "low carb", "high protein meal", "clean eating"],
            "Quick meals": ["15 minute", "20 minute", "quick meal", "weeknight", "easy dinner"],
            "Baking": ["bake", "baking", "sourdough", "bread", "cake", "pastry"],
            "Meal prep": ["meal prep", "batch cook", "prep ahead"],
            "Grill": ["grill", "bbq", "barbecue", "smoker", "brisket"],
        ],
        "wellness": [
            "Morning routines": ["morning routine", "5am", "wake up", "miracle morning"],
            "Affirmations": ["affirmation", "affirmations", "mantra"],
            "Breathwork": ["breathwork", "breathing", "wim hof", "box breathing"],
            "Meditation": ["meditation", "mindfulness", "meditate"],
            "Journaling": ["journal", "journaling", "gratitude"],
        ],
        "sport": [
            "Rugby": ["rugby", "springbok", "six nations", "scrum"],
            "Football": ["football", "soccer", "premier league", "goal"],
            "Cycling": ["cycling", "bike", "peloton", "watts", "ftp"],
            "Swimming": ["swim", "swimming", "freestyle", "pool"],
            "Highlights": ["highlight", "highlights", "best moments"],
        ],
        "parenting": [
            "Homeschooling": ["homeschool", "homeschooling", "curriculum", "unschool"],
            "Activities": ["kids activity", "craft", "play idea", "sensory"],
            "Discipline": ["discipline", "tantrum", "boundaries", "gentle parenting"],
            "Screen time": ["screen time", "screentime"],
            "Milestones": ["milestone", "crawling", "first steps", "potty"],
        ],
        "money": [
            "Investing": ["invest", "investing", "etf", "index fund", "portfolio", "stock"],
            "Saving": ["saving", "savings", "emergency fund", "budget"],
            "Side income": ["side hustle", "side income", "freelance", "passive income"],
            "Tax": ["tax", "taxes", "deduction", "irs", "sars"],
            "Property": ["property", "mortgage", "real estate", "rental"],
        ],
        "tech": [
            "AI": ["ai", "llm", "gpt", "claude", "prompt", "machine learning", "agent"],
            "Coding": ["code", "coding", "swift", "python", "javascript", "react", "programming"],
            "Tools": ["tool", "app recommendation", "workflow", "productivity app"],
            "Gadgets": ["gadget", "iphone", "review", "unboxing"],
            "Security": ["security", "password", "2fa", "privacy", "breach"],
        ],
        "business": [
            "Startups": ["startup", "founder", "yc", "seed round", "mvp"],
            "Marketing": ["marketing", "seo", "ads", "funnel", "growth"],
            "Sales": ["sales", "cold email", "outreach", "closing"],
            "Hiring": ["hiring", "recruit", "interview", "candidate"],
            "Pricing": ["pricing", "price", "saas pricing", "mrr"],
        ],
        "funny": [
            "Memes": ["meme", "memes"],
            "Standup": ["standup", "stand up", "comedian", "comedy"],
            "Fails": ["fail", "fails", "blooper"],
            "Animals": ["dog", "cat", "puppy", "kitten", "animal"],
            "Skits": ["skit", "sketch", "parody"],
        ],
        "religion": [
            "Scripture": ["bible", "scripture", "verse", "psalm", "quran", "torah"],
            "Sermons": ["sermon", "preach", "pastor"],
            "Apologetics": ["apologetics", "theology", "doctrine"],
            "Prayer": ["prayer", "praying"],
        ],
        "conspiracies": [
            "History": ["cover up", "coverup", "declassified", "hidden history"],
            "Science": ["suppressed", "they don't want you to know"],
            "Debunked": ["debunk", "debunked", "myth busted"],
        ],
        "home": [
            "DIY": ["diy", "build it", "woodworking", "how to build"],
            "Garden": ["garden", "gardening", "plant", "compost", "veg patch"],
            "Organising": ["organis", "organiz", "declutter", "storage", "tidy"],
            "Repairs": ["repair", "fix", "leak", "replace"],
            "Design": ["interior", "decor", "renovation", "styling"],
        ],
        "travel": [
            "Destinations": ["itinerary", "guide to", "things to do", "destination"],
            "Hacks": ["travel hack", "packing", "carry on", "layover"],
            "Gear": ["luggage", "backpack", "travel gear"],
            "Budget": ["cheap flight", "budget travel", "points", "miles"],
        ],
    ]

    static func suggest(url: URL, title: String) -> Suggestion {
        let haystack = normalise("\(title) \(url.path) \(url.host ?? "")")

        var best: (category: String, sub: String, score: Int)?
        var tags: [String] = []

        for (categoryID, subs) in keywords {
            for (sub, words) in subs {
                var score = 0
                for word in words where haystack.contains(word) {
                    // Longer keyword matches are more meaningful than "ai" or "s".
                    score += max(1, word.count / 3)
                    tags.append(word)
                }
                if score > 0, score > (best?.score ?? 0) {
                    best = (categoryID, sub, score)
                }
            }
        }

        // A platform is always a useful tag even when nothing else matched.
        let platformTag = Platform.detect(from: url).label.lowercased()

        let cleaned = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespaces) }))
            .filter { $0.count > 2 }
            .sorted()
            .prefix(4)

        return Suggestion(
            categoryID: best?.category,
            subcategory: best?.sub,
            tags: Array(cleaned) + [platformTag]
        )
    }

    /// Turns slugs into something matchable: "/p/five-hip-mobility-drills" ->
    /// "p five hip mobility drills".
    private static func normalise(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let separators = CharacterSet(charactersIn: "-_/.?=&+%")
        return lowered
            .components(separatedBy: separators)
            .joined(separator: " ")
    }
}
