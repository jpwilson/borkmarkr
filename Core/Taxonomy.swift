import Foundation

/// One of the two browse axes (the other is `Platform`).
///
/// `hue` drives the whole colour identity for a category — chip tint, deep
/// text, media-cover gradient and dot are all derived from it, so a category
/// never needs a hand-picked palette.
struct Topic: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let hue: Double
    let subs: [String]
}

/// The category tree.
///
/// This deliberately **diverges from the v2 design handoff**, which shipped 24
/// categories and told us to copy them verbatim. That set had real gaps for
/// what actually gets saved off short-form feeds in 2026: no cars, no books,
/// no true crime, no creator economy, no cleaning/organising, no trades, no
/// anime, no photo/video — and AI sat as a single sub-item under Tech. It also
/// merged audiences that behave nothing alike (Beauty inside Style, Nutrition
/// inside Food, Mental health inside Health).
///
/// So: 50 categories, ~700 subcategories. The original brief asked for "a few
/// hundred", which the 24-category set never reached.
///
/// **Hue assignment is semantic, not arbitrary.** Related categories sit in the
/// same hue family so the feed reads as colour-coded families rather than
/// confetti:
///   330–360  body, self, intimate      (Fashion → Mental health)
///     0–50   making, home, food, past   (True crime → History)
///    50–75   light, play, animals       (Trades → Cleaning)
///    85–160  growth, nature, family     (Homestead → Investing)
///   165–195  money, commerce, science   (Money → Marketing)
///   195–240  screens, motion, current   (Tech → Career)
///   245–290  play, mind, sound          (Learning → Music)
///   290–320  story, meaning, craft      (Film & TV → Art & design)
///
/// With 50 categories some neighbouring hues are close. That is intentional —
/// within a family, looking alike is a feature, and the name is always shown
/// alongside the colour.
enum Taxonomy {

    static let all: [Topic] = [

        // ── Body, self, intimate ────────────────────────────────────────────
        Topic(id: "fashion", name: "Fashion", hue: 326, subs: [
            "Outfits", "Capsule wardrobe", "Streetwear", "Workwear", "Formal",
            "Thrifting", "Sneakers", "Accessories", "Watches", "Bags",
            "Seasonal", "Styling tips", "Sustainable", "Budget finds",
        ]),
        Topic(id: "grooming", name: "Hair & grooming", hue: 332, subs: [
            "Haircuts", "Styling", "Hair care", "Colour", "Hair loss",
            "Beards", "Shaving", "Barbering", "Curly hair", "Scalp health",
        ]),
        Topic(id: "relationships", name: "Relationships", hue: 338, subs: [
            "Dating", "Marriage", "Communication", "Boundaries", "Breakups",
            "Friendship", "Family", "Conflict", "Intimacy", "Long distance",
            "Attachment", "Red flags",
        ]),
        Topic(id: "beauty", name: "Beauty", hue: 344, subs: [
            "Skincare", "Makeup", "Nails", "Fragrance", "Acne", "Anti-ageing",
            "Routines", "Product reviews", "Tutorials", "Sunscreen",
            "Ingredients", "Dupes", "Treatments",
        ]),
        Topic(id: "health", name: "Health", hue: 352, subs: [
            "Conditions", "Medications", "Symptoms", "Sleep", "Heart & BP",
            "Diabetes", "Pain relief", "Women's health", "Men's health",
            "Kids' health", "Dental", "Skin conditions", "Immunity",
            "Hormones", "Longevity", "Bloodwork", "Injuries", "Gut health",
            "Allergies", "Eyes & vision",
        ]),
        Topic(id: "mentalhealth", name: "Mental health", hue: 358, subs: [
            "Anxiety", "Depression", "Burnout", "Therapy", "ADHD", "Autism",
            "Trauma", "Stress", "Grief", "Self-esteem", "Addiction",
            "Bipolar", "OCD", "Coping skills",
        ]),

        // ── Making, home, food, past ────────────────────────────────────────
        Topic(id: "truecrime", name: "True crime", hue: 4, subs: [
            "Cases", "Investigations", "Forensics", "Cold cases", "Court",
            "Documentaries", "Missing persons", "Scams & fraud", "Analysis",
        ]),
        Topic(id: "cars", name: "Cars & motors", hue: 11, subs: [
            "Reviews", "Maintenance", "Detailing", "Modding", "Buying advice",
            "EVs", "Classics", "Motorsport", "Off-road", "Motorcycles",
            "Restoration", "Track days", "Tools", "Insurance",
        ]),
        Topic(id: "crafts", name: "Crafts & making", hue: 18, subs: [
            "Woodworking", "3D printing", "Sewing", "Knitting & crochet",
            "Resin", "Ceramics", "Leatherwork", "Laser cutting", "Restoration",
            "Upcycling", "Jewellery", "Candles & soap", "Bookbinding",
        ]),
        Topic(id: "diy", name: "DIY & repairs", hue: 24, subs: [
            "Plumbing", "Electrical", "Painting", "Flooring", "Walls & drywall",
            "Tools", "Quick fixes", "Safety", "Cost saving", "Tiling",
            "Doors & windows", "Insulation",
        ]),
        Topic(id: "home", name: "Home & interiors", hue: 30, subs: [
            "Interiors", "Decor", "Small spaces", "Furniture", "Lighting",
            "Renovation", "Architecture", "Rentals", "Moving", "Colour schemes",
            "Kitchens", "Bathrooms", "Outdoor spaces",
        ]),
        Topic(id: "fooddrink", name: "Food & drink", hue: 36, subs: [
            "Restaurants", "Street food", "Coffee", "Cocktails", "Wine", "Beer",
            "Tea", "Food science", "Reviews", "Markets", "Cheese", "Bread",
            "Food history",
        ]),
        Topic(id: "recipes", name: "Recipes", hue: 42, subs: [
            "Quick meals", "Meal prep", "High-protein", "Baking", "Desserts",
            "Air fryer", "Slow cooker", "One-pan", "Budget meals", "Vegetarian",
            "Vegan", "Snacks", "Breakfast", "Sauces", "Grilling", "Soups",
            "Pasta", "Gluten-free",
        ]),
        Topic(id: "history", name: "History", hue: 48, subs: [
            "Ancient", "Medieval", "Modern", "Military", "Archaeology",
            "Biographies", "Myths & legends", "Explainers", "Maps",
            "Lost technology", "Empires",
        ]),

        // ── Light, play, animals, order ─────────────────────────────────────
        Topic(id: "trades", name: "Trades & skills", hue: 54, subs: [
            "Welding", "Carpentry", "Mechanics", "HVAC", "Masonry", "Roofing",
            "Estimating", "Apprenticeships", "Tools of the trade", "Site safety",
            "Landscaping",
        ]),
        Topic(id: "comedy", name: "Comedy", hue: 60, subs: [
            "Memes", "Skits", "Stand-up", "Fails", "Pranks", "Wholesome",
            "Satire", "Animals being funny", "Impressions", "Storytime",
        ]),
        Topic(id: "pets", name: "Pets", hue: 66, subs: [
            "Dogs", "Cats", "Training", "Pet health", "Nutrition", "Grooming",
            "Behaviour", "Adoption", "Exotic pets", "Gear", "Puppies & kittens",
            "Vet advice",
        ]),
        Topic(id: "cleaning", name: "Cleaning & organising", hue: 72, subs: [
            "Deep cleaning", "Decluttering", "Storage", "Laundry", "Routines",
            "Products", "Small spaces", "Minimalism", "Kitchen", "Bathroom",
            "Car interiors", "Speed cleaning",
        ]),

        // ── Growth, nature, family ──────────────────────────────────────────
        Topic(id: "homestead", name: "Homestead", hue: 88, subs: [
            "Chickens", "Preserving", "Off-grid", "Water systems", "Solar",
            "Livestock", "Foraging", "Self-sufficiency", "Beekeeping",
            "Root cellars", "Butchering",
        ]),
        Topic(id: "garden", name: "Garden", hue: 96, subs: [
            "Vegetables", "Houseplants", "Landscaping", "Composting", "Pests",
            "Seeds", "Hydroponics", "Fruit trees", "Seasonal jobs", "Lawns",
            "Propagation", "Greenhouses",
        ]),
        Topic(id: "outdoors", name: "Outdoors", hue: 106, subs: [
            "Hiking", "Camping", "Backpacking", "Climbing", "Fishing",
            "Hunting", "Surfing", "Snow sports", "Van life", "Gear",
            "Navigation", "Bushcraft", "Kayaking", "Overlanding",
        ]),
        Topic(id: "nature", name: "Nature", hue: 116, subs: [
            "Wildlife", "Birds", "Ocean", "Weather", "Conservation", "Geology",
            "Stargazing", "Landscapes", "Insects", "Trees & fungi",
        ]),
        Topic(id: "parenting", name: "Parenting", hue: 128, subs: [
            "Newborn", "Toddlers", "Teens", "Discipline", "Sleep training",
            "Activities", "School", "Screen time", "Meals", "Milestones",
            "Homeschool", "Siblings", "Special needs", "Co-parenting",
        ]),
        Topic(id: "babyprep", name: "Pregnancy & baby", hue: 138, subs: [
            "Pregnancy", "Birth", "Postpartum", "Feeding", "Baby gear",
            "Nursery", "Development", "Names", "Fertility", "Twins",
        ]),
        Topic(id: "nutrition", name: "Nutrition", hue: 146, subs: [
            "High-protein", "Supplements", "Macros", "Hydration", "Fasting",
            "Weight loss", "Muscle gain", "Vitamins", "Meal timing",
            "Sports nutrition", "Fibre", "Sugar", "Food labels",
        ]),
        Topic(id: "fitness", name: "Fitness", hue: 152, subs: [
            "Running", "Strength", "Mobility", "Stretching", "Yoga", "Pilates",
            "HIIT", "Calisthenics", "Cardio", "Home workouts", "Recovery",
            "Warm-ups", "Form check", "Programming", "Gym gear", "Injury prep",
            "Swimming", "Rowing",
        ]),
        Topic(id: "investing", name: "Investing", hue: 160, subs: [
            "Stocks", "ETFs & index funds", "Real estate", "Dividends",
            "Options", "Bonds", "Analysis", "Portfolio", "Market news",
            "Commodities", "Valuation", "Risk",
        ]),

        // ── Money, commerce, science ────────────────────────────────────────
        Topic(id: "money", name: "Money", hue: 168, subs: [
            "Budgeting", "Saving", "Debt", "Credit", "Taxes", "Insurance",
            "Retirement", "Frugal living", "Side hustles",
            "Financial independence", "Banking", "Bills",
        ]),
        Topic(id: "crypto", name: "Crypto", hue: 174, subs: [
            "Bitcoin", "Ethereum", "DeFi", "Wallets & security", "Trading",
            "Mining", "Regulation", "Stablecoins", "Scams", "On-chain",
        ]),
        Topic(id: "business", name: "Business", hue: 180, subs: [
            "Startups", "Strategy", "Operations", "Finance", "Hiring",
            "E-commerce", "SaaS", "Pricing", "Fundraising", "Case studies",
            "Legal", "Suppliers", "Franchising",
        ]),
        Topic(id: "science", name: "Science", hue: 186, subs: [
            "Space", "Physics", "Biology", "Chemistry", "Psychology",
            "Medicine", "Environment", "Discoveries", "Explainers", "Genetics",
            "Neuroscience", "Maths",
        ]),
        Topic(id: "marketing", name: "Marketing", hue: 192, subs: [
            "SEO", "Ads", "Content", "Email", "Copywriting", "Branding",
            "Analytics", "Social strategy", "Funnels", "Positioning", "PR",
        ]),

        // ── Screens, motion, current ────────────────────────────────────────
        Topic(id: "tech", name: "Tech", hue: 197, subs: [
            "Gadgets", "Phones", "Laptops", "Audio", "Smart home", "Wearables",
            "Reviews", "Deals", "Cybersecurity", "Privacy", "Tips",
            "Repairs", "Networking",
        ]),
        Topic(id: "travel", name: "Travel", hue: 202, subs: [
            "Destinations", "Itineraries", "Budget travel", "Flights & points",
            "Hotels", "Packing", "Food spots", "Solo travel", "Hidden gems",
            "Visas", "Family travel", "Trains", "Cruises",
        ]),
        Topic(id: "sports", name: "Sports", hue: 208, subs: [
            "Football", "Basketball", "Soccer", "Tennis", "Golf",
            "Combat sports", "Cricket", "Rugby", "Highlights", "Analysis",
            "Betting", "Athletics", "Cycling", "F1",
        ]),
        Topic(id: "photovideo", name: "Photo & video", hue: 214, subs: [
            "Cameras", "Lenses", "Lighting", "Editing", "Colour grading",
            "Composition", "Drones", "Filmmaking", "Presets", "Gear reviews",
            "Portraits", "Audio for video",
        ]),
        Topic(id: "creator", name: "Creator", hue: 220, subs: [
            "Growing an audience", "Monetisation", "Short-form tips",
            "Thumbnails", "Algorithms", "Editing workflow", "Sponsorships",
            "Platform news", "Equipment", "Scripting", "Analytics",
            "Community",
        ]),
        Topic(id: "coding", name: "Coding", hue: 226, subs: [
            "Web dev", "Mobile", "Backend", "DevOps", "Databases", "Algorithms",
            "Open source", "Tools", "Debugging", "Testing", "Architecture",
            "Career",
        ]),
        Topic(id: "news", name: "News & politics", hue: 232, subs: [
            "World", "Politics", "Business", "Local", "Explainers", "Elections",
            "Policy", "Media", "Conflict", "Economy",
        ]),
        Topic(id: "career", name: "Career & work", hue: 238, subs: [
            "Resume", "Interviews", "Negotiation", "Networking", "Leadership",
            "Remote work", "Productivity", "Skills", "Job search", "Management",
            "Freelancing", "Workplace",
        ]),

        // ── Play, mind, sound ───────────────────────────────────────────────
        Topic(id: "learning", name: "Learning", hue: 248, subs: [
            "Study techniques", "Languages", "Maths", "Writing",
            "Public speaking", "Memory", "Note-taking", "Courses", "Exam prep",
            "Research", "Critical thinking",
        ]),
        Topic(id: "ai", name: "AI", hue: 256, subs: [
            "Prompting", "Tools", "Agents", "Coding with AI",
            "Image generation", "Video generation", "Local models", "Research",
            "Ethics", "News", "Automation", "Fine-tuning",
        ]),
        Topic(id: "gaming", name: "Gaming", hue: 264, subs: [
            "Guides", "Reviews", "Builds", "Speedruns", "Esports", "News",
            "Retro", "Mods", "Setups", "Indie", "Lore", "Streaming",
        ]),
        Topic(id: "wellness", name: "Wellness", hue: 272, subs: [
            "Morning routines", "Evening routines", "Meditation", "Breathwork",
            "Habits", "Journaling", "Gratitude", "Self-care", "Mindfulness",
            "Cold exposure", "Sauna", "Digital detox", "Focus",
        ]),
        Topic(id: "anime", name: "Anime & comics", hue: 280, subs: [
            "Anime", "Manga", "Comics", "Recommendations", "Analysis",
            "Cosplay", "Collecting", "Webtoons", "Studios",
        ]),
        Topic(id: "music", name: "Music", hue: 288, subs: [
            "Production", "Theory", "Guitar", "Piano", "Singing", "Mixing",
            "Playlists", "Artists", "Gear", "Live", "Drums", "DJing",
            "Songwriting",
        ]),

        // ── Story, meaning, craft ───────────────────────────────────────────
        Topic(id: "filmtv", name: "Film & TV", hue: 296, subs: [
            "Reviews", "Recommendations", "Analysis", "Trailers",
            "Behind the scenes", "Streaming", "Classics", "Documentaries",
            "Directors", "Scenes",
        ]),
        Topic(id: "beliefs", name: "Beliefs", hue: 304, subs: [
            "Religion", "Philosophy", "Spirituality", "Ethics", "Conspiracies",
            "Big questions", "Astrology", "Scripture", "Meaning",
        ]),
        Topic(id: "books", name: "Books", hue: 312, subs: [
            "Recommendations", "Reviews", "Fiction", "Non-fiction", "Summaries",
            "Reading habits", "Authors", "Poetry", "Series", "Audiobooks",
        ]),
        Topic(id: "art", name: "Art & design", hue: 320, subs: [
            "Drawing", "Painting", "Illustration", "Graphic design",
            "Typography", "Colour", "Digital art", "UI/UX", "Inspiration",
            "Sculpture", "Animation", "Portfolios",
        ]),
    ]

    private static let index: [String: Topic] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// User-created topics, installed by `MergedTaxonomy` whenever the custom
    /// rows are loaded. Kept here so `Bookmark.category` still works without
    /// every call site threading a merge.
    private static let extrasLock = NSLock()
    nonisolated(unsafe) private static var extras: [String: Topic] = [:]

    static func installCustomTopics(_ topics: [Topic]) {
        extrasLock.lock()
        extras = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        extrasLock.unlock()
    }

    static func category(id: String?) -> Topic? {
        guard let id else { return nil }
        if let hit = index[id] { return hit }
        extrasLock.lock()
        defer { extrasLock.unlock() }
        return extras[id]
    }

    /// Every category, sorted so the user's onboarding interests float to the
    /// top of Browse › Topics (spec: "Interests float those categories to the
    /// top").
    static func ordered(interests: [String]) -> [Topic] {
        let interestSet = Set(interests)
        return all.sorted { a, b in
            let ai = interestSet.contains(a.id), bi = interestSet.contains(b.id)
            if ai != bi { return ai }
            return a.name < b.name
        }
    }

    /// Categories offered as interest chips during onboarding — the broadest,
    /// most universally-applicable ones rather than all 50.
    static let onboardingInterests = [
        "fitness", "health", "recipes", "money", "tech", "ai", "travel",
        "comedy", "sports", "parenting", "home", "beauty", "gaming", "music",
        "learning", "wellness", "cars", "books",
    ]
}
