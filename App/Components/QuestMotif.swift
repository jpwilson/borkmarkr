import SwiftUI
import UIKit

/// Closed illustration kit for side quests.
///
/// Titles are free-form ("Which minivan", "Get really good at sourdough"),
/// so we never commission unique art. A title/topic resolver picks one of
/// these scenes; anything we don't recognise gets the compass.
enum QuestMotif: String, CaseIterable, Sendable {
    case rabbit, business, run, market, cook, learn, create, money, compass, scroll

    var assetName: String {
        switch self {
        case .rabbit: "questRabbit"
        case .business: "questBusiness"
        case .run: "questRun"
        case .market: "questMarket"
        case .cook: "questCook"
        case .learn: "questLearn"
        case .create: "questCreate"
        case .money: "questMoney"
        case .compass: "questCompass"
        case .scroll: "questScroll"
        }
    }

    var symbol: String {
        switch self {
        case .rabbit: "hare.fill"
        case .business: "storefront.fill"
        case .run: "figure.run"
        case .market: "megaphone.fill"
        case .cook: "fork.knife"
        case .learn: "book.fill"
        case .create: "camera.fill"
        case .money: "leaf.fill"
        case .compass: "safari.fill"
        case .scroll: "bookmark.fill"
        }
    }

    static func resolve(title: String, categoryID: String? = nil, subcategory: String? = nil) -> QuestMotif {
        let blob = ([title, subcategory, categoryID].compactMap { $0 })
            .joined(separator: " ")
            .lowercased()

        func mentions(_ words: String...) -> Bool {
            words.contains { blob.contains($0) }
        }

        if mentions("rabbit", "conspirac", "cover-up", "unsolved", "truecrime", "beliefs") {
            return .rabbit
        }
        if mentions("market", "social", "audience", "hook", "megaphone", "creator") {
            return .market
        }
        if mentions("startup", "founder", "venture", "business", "shop", "storefront") {
            return .business
        }
        if mentions("run", "marathon", "5k", "10k", "mobility", "stretch", "fitness", "hip", "hamstring", "tendon") {
            return .run
        }
        if mentions("potter", "ceramic", "clay") {
            return .create
        }
        if mentions("recipe", "cook", "meal", "food", "kitchen") {
            return .cook
        }
        if mentions("draw", "paint", "camera", "photo", "video", "art") {
            return .create
        }
        if mentions("read", "book", "learn", "study", "course") {
            return .learn
        }
        if mentions("money", "invest", "crypto", "budget", "spend") {
            return .money
        }

        switch categoryID {
        case "beliefs", "truecrime": return .rabbit
        case "business": return .business
        case "fitness", "sports": return .run
        case "marketing", "creator": return .market
        case "recipes", "fooddrink", "nutrition": return .cook
        case "books", "learning": return .learn
        case "photovideo", "art", "crafts": return .create
        case "money", "investing", "crypto": return .money
        default: return .compass
        }
    }

    /// The built-in topic whose clay scene fits a body-or-mind quest the kit
    /// has no scene for. "Breathing", "Sleep properly", "Get on top of the
    /// anxiety" all used to fall through to the compass; none of the ten
    /// scenes is about any of them, but the Wellness, Health and Mental
    /// health topics each ship one that is.
    static func bodyMindTopic(in fragments: [String?]) -> String? {
        let blob = fragments.compactMap { $0 }.joined(separator: " ").lowercased()
        func mentions(_ words: String...) -> Bool {
            words.contains { blob.contains($0) }
        }
        if mentions("anxiet", "stress", "burnout", "therap", "depress", "adhd", "grief", "panic", "overthink") {
            return "mentalhealth"
        }
        if mentions("breath", "meditat", "mindful", "journal", "gratitude", "morning person", "routine", "habit", "cold plunge", "sauna", "detox", "wellness", "calm", "focus") {
            return "wellness"
        }
        if mentions("sleep", "health", "doctor", "symptom", "pain", "injur", "gut", "hormone", "longevity", "bloodwork", "immun", "allerg", "dental") {
            return "health"
        }
        return nil
    }
}

/// What a quest card wears.
///
/// Ten fixed scenes cannot cover every sentence someone types. Seb's
/// breathing quest — Health, a title the kit has no scene for — fell through
/// `QuestMotif.resolve` to the compass and read as a map on a quest about
/// breathing. So a cover is resolved in three passes: a title, subtopic or
/// topic the kit draws (rabbit hole, marketing, running, cooking…) wins;
/// then the linked topic's own bundled clay scene, so a Health quest wears
/// the Health art; then, for a quest with no topic, the body-or-mind scene
/// its words point at. The compass is what is left — a quest about nothing
/// the app has a picture of, or a custom topic whose scene lives on the
/// server and is not bundled (paper would be worse than a map).
///
/// `docs/index.html`'s `questArt` walks the same passes minus the title one.
enum QuestCover: Equatable {
    case motif(QuestMotif)
    case topic(String)

    static func resolve(title: String, categoryID: String? = nil, subcategory: String? = nil) -> QuestCover {
        let motif = QuestMotif.resolve(title: title, categoryID: categoryID, subcategory: subcategory)
        if motif != .compass { return .motif(motif) }
        if let categoryID, TopicMotif.isBundled(categoryID) { return .topic(categoryID) }
        if let family = QuestMotif.bodyMindTopic(in: [title, subcategory]), TopicMotif.isBundled(family) {
            return .topic(family)
        }
        return .motif(.compass)
    }
}

struct QuestCoverArt: View {
    let cover: QuestCover
    var contentMode: ContentMode = .fill

    var body: some View {
        switch cover {
        case .motif(let motif): QuestArt(motif: motif, contentMode: contentMode)
        case .topic(let id): TopicClayArt(categoryID: id, contentMode: contentMode)
        }
    }
}

/// Bundled clay scene, or paper if the imageset is missing.
struct ClayArt: View {
    let name: String
    var contentMode: ContentMode = .fill

    var body: some View {
        if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Tokens.paper
        }
    }
}

struct QuestArt: View {
    let motif: QuestMotif
    var contentMode: ContentMode = .fill

    var body: some View {
        ClayArt(name: motif.assetName, contentMode: contentMode)
    }
}

/// One clay scene per topic. Never a quest asset, never shared across topics.
enum TopicMotif {
    static func asset(for categoryID: String) -> String {
        guard !categoryID.isEmpty else { return "topicFallback" }
        return "topic" + categoryID.prefix(1).uppercased() + categoryID.dropFirst()
    }

    /// Whether the scene ships in the binary. True for the 50 built-ins;
    /// false for a custom topic, whose scene is drawn on the server.
    static func isBundled(_ categoryID: String) -> Bool {
        !categoryID.isEmpty && UIImage(named: asset(for: categoryID)) != nil
    }
}

/// A topic's clay scene, from wherever that topic's scene comes from.
///
/// Built-ins are bundled and resolve instantly. A topic you made yourself has
/// its scene drawn by the `topic-art` function and fetched over the network,
/// so it cross-fades in the way a bookmark cover does — and until it arrives
/// (or if it never does) the tile is paper, which is what it has always been.
struct TopicClayArt: View {
    let categoryID: String
    var remote: URL?
    var contentMode: ContentMode = .fill
    /// What sits behind a scene that hasn't arrived. Browse's tiles keep the
    /// paper default; the topic page's hero band passes the topic's own tint,
    /// so a band with no art still reads as that topic rather than as a blank
    /// strip across the top of the screen.
    var fallbackTint: Color? = nil

    var body: some View {
        let asset = TopicMotif.asset(for: categoryID)
        if UIImage(named: asset) != nil {
            ClayArt(name: asset, contentMode: contentMode)
        } else {
            ZStack {
                if let fallbackTint {
                    LinearGradient(colors: [fallbackTint, fallbackTint.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    Tokens.paper
                }
                if let remote {
                    AsyncImage(url: remote, transaction: Transaction(animation: .easeOut(duration: 0.22))) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .transition(.opacity)
                        }
                    }
                }
            }
            // Same reason as CoverImage: a `.fill` bitmap on a loose
            // proposal adopts its own pixel size and blows the tile out of
            // the grid column.
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }
}
