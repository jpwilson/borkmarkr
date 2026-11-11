import SwiftUI
import UIKit

/// Quick File in the app's own clothes: Bricolage for the hub's topic name,
/// Instrument Sans for everything else, the bundled clay scenes, and the
/// accent the person picked in onboarding.
///
/// The Share Extension can reach none of these (it compiles Core and nothing
/// else, under a ~120 MB cap), so it keeps `QuickFileStyle.system`: SF
/// Rounded and the 240 px thumbnails `QuickFileBridge` copies into the App
/// Group. The dial itself is the same code in both places.
///
/// The faces are fixed-size, like the extension's `.system(size:)`: Quick
/// File scales its own text where it should (`@ScaledMetric` in the refine
/// panel and the ranked list) and holds the ring's still. `Typo.ui` scales
/// with body by itself, so through it that text grew twice at large sizes.
extension QuickFileStyle {
    static func app(_ accent: AccentRamp) -> QuickFileStyle {
        QuickFileStyle(
            display: { size in .custom("Bricolage Grotesque", fixedSize: size).weight(.bold) },
            ui: { size, weight in
                .custom("Instrument Sans", fixedSize: size).weight(weight == .heavy || weight == .black ? .bold : weight)
            },
            art: { topicID in QuickFileAppArt.image(for: topicID) },
            accent: accent.base,
            accentDeep: accent.deep
        )
    }
}

/// A topic's clay scene at the size the dial draws it.
///
/// The built-ins ship their scenes in the asset catalogue at 640 px, which is
/// far more than the 84 pt hub needs (252 px at @3x); each is decoded once at 256 px and kept,
/// so turning the dial never decodes anything. A topic you made has no
/// bundled scene, so it falls through to the thumbnail the app installed in
/// the App Group from its `topic-art` image, and then to the colour disc.
@MainActor
enum QuickFileAppArt {
    private static let pixels: CGFloat = 256
    private static var scenes: [String: UIImage] = [:]
    /// Ids with no bundled scene, so the asset catalogue is asked only once.
    private static var unbundled: Set<String> = []

    static func image(for topicID: String) -> UIImage? {
        if let scene = scenes[topicID] { return scene }
        if !unbundled.contains(topicID) {
            if let full = UIImage(named: TopicMotif.asset(for: topicID)) {
                let scene = full.preparingThumbnail(of: CGSize(width: pixels, height: pixels)) ?? full
                scenes[topicID] = scene
                return scene
            }
            unbundled.insert(topicID)
        }
        return QuickFileArt.image(for: topicID)
    }

    /// Decodes the ring's scenes before the dial draws them.
    static func preload(_ topicIDs: [String]) {
        for id in topicIDs { _ = image(for: id) }
    }
}
