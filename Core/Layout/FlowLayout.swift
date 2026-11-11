import SwiftUI

/// A wrapping row: lays its children left to right and starts a new line when
/// the next one won't fit. SwiftUI has no built-in wrapping stack.
///
/// Moved out of App/Screens/TopicPickerSheet.swift into Core so the Share
/// Extension's views (which compile Core, not App) can wrap too. Use it for
/// chip lists that should show every item (picker subtopics, onboarding
/// interests, Revisit's topic chips). For a fixed-height chip area that can
/// grow without limit, use a two-row `LazyHGrid` in a horizontal `ScrollView`
/// instead (the refine panel's subtopics).
///
/// Children are measured at their ideal size, so give each a `.fixedSize()` or
/// a natural width; a child wider than the row gets a row of its own.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
