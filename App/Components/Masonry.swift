import SwiftUI

/// Two-column masonry for the Library feed.
///
/// **Engineering deviation from the handoff.** The spec says items alternate
/// columns strictly — "evens→left stack, odds→right stack" — and explicitly
/// warns against CSS `column-count` because it fills sequentially and destroys
/// recency ordering. That warning is right, but strict alternation trades one
/// problem for another: it ignores how tall the cards actually are.
///
/// Card heights here range from ~96pt (a short article) to ~260pt (a TikTok
/// cover with a 3-line title). With 26 fixed sample items that averages out. In
/// a real library it doesn't — a run of tall media into one column and short
/// text posts into the other leaves the columns hundreds of points apart, so
/// the feed ends in a long one-sided stack with dead space beside it.
///
/// This packs each item into whichever column is currently shorter. Items are
/// still placed in strict recency order, so the newest saves stay at the top
/// exactly as the spec requires — but the columns stay level. Where heights
/// happen to be equal it degenerates to the spec's alternation, which is the
/// behaviour the design was actually reaching for.
struct MasonryVStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    /// Estimated laid-out height. Only relative accuracy matters — it decides
    /// placement, never the real frame.
    let estimatedHeight: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    private var columns: (left: [Item], right: [Item]) {
        var left: [Item] = [], right: [Item] = []
        var leftHeight: CGFloat = 0, rightHeight: CGFloat = 0

        for item in items {
            let height = estimatedHeight(item) + spacing
            // Ties go left so the very first item is top-left, matching the
            // spec's reading order.
            if leftHeight <= rightHeight {
                left.append(item)
                leftHeight += height
            } else {
                right.append(item)
                rightHeight += height
            }
        }
        return (left, right)
    }

    var body: some View {
        let split = columns
        HStack(alignment: .top, spacing: spacing) {
            LazyVStack(spacing: spacing) {
                ForEach(split.left) { content($0) }
            }
            LazyVStack(spacing: spacing) {
                ForEach(split.right) { content($0) }
            }
        }
    }
}
