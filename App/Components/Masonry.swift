import SwiftUI

/// Two-column masonry for the Library feed: two **lazy** columns, balanced by
/// estimated height.
///
/// Items go, in recency order, into whichever column is currently shorter by
/// estimate, so the newest borks stay at the top and the columns stay level.
/// The estimate only decides placement — each card still lays out at its real
/// height, at exactly its column's width.
///
/// Lazy is the point. The previous `Layout` measured every card in the
/// library, twice, on every layout pass, and kept every card (and every
/// cover download) alive at once — a pass ran whenever *any* card changed,
/// including each cover arriving. A few hundred borks made the whole app
/// slow. `LazyVStack` builds only what is on screen, and it is fine nested
/// here: SwiftUI resolves visibility against the enclosing `ScrollView`.
struct MasonryVStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    /// Relative height, for balancing only.
    let estimatedHeight: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let split = Self.columns(items, spacing: spacing, estimatedHeight: estimatedHeight)
        HStack(alignment: .top, spacing: spacing) {
            column(split.left)
            column(split.right)
        }
    }

    private func column(_ items: [Item]) -> some View {
        LazyVStack(spacing: spacing) {
            ForEach(items) { content($0) }
        }
        // Each column takes exactly half; nothing inside may widen it.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
    }

    static func columns(_ items: [Item], spacing: CGFloat,
                        estimatedHeight: (Item) -> CGFloat) -> (left: [Item], right: [Item]) {
        var left: [Item] = [], right: [Item] = []
        var leftHeight: CGFloat = 0, rightHeight: CGFloat = 0
        left.reserveCapacity(items.count / 2 + 1)
        right.reserveCapacity(items.count / 2 + 1)
        for item in items {
            let height = estimatedHeight(item) + spacing
            // Ties go left, so the newest bork is top-left.
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
}
