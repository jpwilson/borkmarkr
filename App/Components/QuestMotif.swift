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

    var body: some View {
        let asset = TopicMotif.asset(for: categoryID)
        if UIImage(named: asset) != nil {
            ClayArt(name: asset, contentMode: contentMode)
        } else {
            ZStack {
                Tokens.paper
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
