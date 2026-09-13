import SwiftUI

/// Bounded masonry shared by all feeds. Each child is measured at its actual
/// column width. Bitmap loading and long text cannot resize another column.
struct MasonryVStack<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    // Retained for source compatibility; placement now uses measured heights.
    let estimatedHeight: (Item) -> CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        MasonryLayout(spacing: spacing) {
            ForEach(items) { content($0) }
        }
    }
}

private struct MasonryLayout: Layout {
    let spacing: CGFloat

    private func arrangement(_ proposal: ProposedViewSize, _ subviews: Subviews)
        -> (width: CGFloat, height: CGFloat, frames: [CGRect]) {
        let width = max(0, proposal.width ?? 320)
        let gap = min(spacing, width)
        let columnWidth = max(0, (width - gap) / 2)
        var heights: [CGFloat] = [0, 0]
        var frames: [CGRect] = []
        for child in subviews {
            let column = heights[0] <= heights[1] ? 0 : 1
            let size = child.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let height = max(0, size.height.isFinite ? size.height : 0)
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + gap),
                                 y: heights[column], width: columnWidth, height: height))
            heights[column] += height + spacing
        }
        return (width, max(0, (heights.max() ?? 0) - spacing), frames)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangement(proposal, subviews)
        return CGSize(width: result.width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(ProposedViewSize(width: bounds.width, height: nil), subviews)
        for (child, frame) in zip(subviews, result.frames) {
            child.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}
