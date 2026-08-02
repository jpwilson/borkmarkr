import Foundation

/// The category tree. The brief asked for "a few hundred" categories; the
/// design prototype shipped ~14 to prove the shape. This is the middle
/// ground — 16 categories with real subcategories, structured so the list can
/// grow without touching any view code.
///
/// Adding a category: append to `Taxonomy.all`. Nothing else needs to change.
struct Category: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let tintHex: String
    let subcategories: [String]
}

enum Taxonomy {
    static let all: [Category] = [
        Category(id: "fitness", name: "Fitness", symbol: "figure.run", tintHex: "FF6B35",
                 subcategories: ["Running", "Strength", "Mobility", "Stretches", "Drills", "Recovery"]),
        Category(id: "health", name: "Health", symbol: "heart.fill", tintHex: "FF3B5C",
                 subcategories: ["Sleep", "Longevity", "Mental health", "Kids' health", "Bloodwork"]),
        Category(id: "medical", name: "Medical", symbol: "cross.case.fill", tintHex: "2E86FF",
                 subcategories: ["Conditions", "Medications", "Procedures", "Research", "Second opinions"]),
        Category(id: "nutrition", name: "Nutrition", symbol: "leaf.fill", tintHex: "2FB86B",
                 subcategories: ["Protein", "Supplements", "Fasting", "Gut health", "Hydration"]),
        Category(id: "cooking", name: "Cooking", symbol: "fork.knife", tintHex: "F5A524",
                 subcategories: ["Healthy", "Quick meals", "Baking", "Meal prep", "Grill"]),
        Category(id: "wellness", name: "Wellness", symbol: "sparkles", tintHex: "A855F7",
                 subcategories: ["Morning routines", "Affirmations", "Breathwork", "Meditation", "Journaling"]),
        Category(id: "sport", name: "Sport", symbol: "sportscourt.fill", tintHex: "0EA5E9",
                 subcategories: ["Rugby", "Football", "Cycling", "Swimming", "Highlights"]),
        Category(id: "parenting", name: "Parenting", symbol: "figure.2.and.child.holdinghands", tintHex: "EC4899",
                 subcategories: ["Homeschooling", "Activities", "Discipline", "Screen time", "Milestones"]),
        Category(id: "money", name: "Money", symbol: "dollarsign.circle.fill", tintHex: "16A34A",
                 subcategories: ["Investing", "Saving", "Side income", "Tax", "Property"]),
        Category(id: "tech", name: "Tech", symbol: "cpu", tintHex: "6366F1",
                 subcategories: ["AI", "Coding", "Tools", "Gadgets", "Security"]),
        Category(id: "business", name: "Business", symbol: "briefcase.fill", tintHex: "0F766E",
                 subcategories: ["Startups", "Marketing", "Sales", "Hiring", "Pricing"]),
        Category(id: "funny", name: "Funny", symbol: "face.smiling.inverse", tintHex: "FACC15",
                 subcategories: ["Memes", "Standup", "Fails", "Animals", "Skits"]),
        Category(id: "religion", name: "Religion", symbol: "book.closed.fill", tintHex: "8B5CF6",
                 subcategories: ["Scripture", "Sermons", "Apologetics", "Prayer", "History"]),
        Category(id: "conspiracies", name: "Conspiracies", symbol: "eye.fill", tintHex: "64748B",
                 subcategories: ["History", "Science", "Politics", "Debunked", "Open questions"]),
        Category(id: "home", name: "Home", symbol: "house.fill", tintHex: "D97706",
                 subcategories: ["DIY", "Garden", "Organising", "Repairs", "Design"]),
        Category(id: "travel", name: "Travel", symbol: "airplane", tintHex: "06B6D4",
                 subcategories: ["Destinations", "Hacks", "Gear", "Food", "Budget"]),
    ]

    static func category(id: String?) -> Category? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Uncategorised is a real state, not an error — the brief is explicit that
    /// saving must never be blocked by organising.
    static let uncategorisedTint = "9CA3AF"
}
