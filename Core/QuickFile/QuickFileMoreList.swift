import SwiftUI

/// "More…" where the full topic picker can't go: the Share Extension.
///
/// `TopicPickerSheet` reads SwiftData through `@Query`, which the extension
/// must never open, so this is the light version: every topic, searched and
/// ordered exactly as the picker orders them (`TopicPickerQuery.shown`), each
/// opening into its subtopics as one-tap chips. No adding, renaming or
/// deleting here; that stays in the app. A pick here counts as filing.
struct QuickFileMoreList: View {
    let topics: [Topic]
    let subs: (Topic) -> [String]
    var style: QuickFileStyle
    let onPick: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var filter = ""
    @State private var expanded: String?

    init(topics: [Topic], subs: @escaping (Topic) -> [String], style: QuickFileStyle = .system,
         onPick: @escaping (String, String?) -> Void, onCancel: @escaping () -> Void) {
        self.topics = topics
        self.subs = subs
        self.style = style
        self.onPick = onPick
        self.onCancel = onCancel
    }

    private static let builtIn = Set(Taxonomy.all.map(\.id))

    private var needle: String { filter.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var shown: [Topic] {
        TopicPickerQuery.shown(topics: topics, subs: { subs($0) }, filter: filter)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            ScrollView {
                let list = shown
                LazyVStack(spacing: 8) {
                    ForEach(list) { topic in
                        row(topic, open: expanded == topic.id || list.count == 1)
                    }
                    if list.isEmpty { empty }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(QuickFileStyle.paper.ignoresSafeArea())
        .onChange(of: filter) { _, _ in
            // Searching opens the best match, so "yoga" is one tap from Fitness › Yoga.
            expanded = needle.isEmpty ? nil : shown.first?.id
        }
    }

    private var header: some View {
        ZStack {
            Text(QuickFileCopy.allTopics)
                .font(style.display(18))
                .foregroundStyle(QuickFileStyle.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                        Text("Back")
                            .font(style.ui(15, .semibold))
                    }
                    .foregroundStyle(style.accentDeep)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to the dial")
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(QuickFileStyle.inkSecondary)
            TextField(QuickFileCopy.searchPrompt, text: $filter)
                .font(style.ui(15, .regular))
                .foregroundStyle(QuickFileStyle.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(QuickFileStyle.inkFaint)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
    }

    private func row(_ topic: Topic, open: Bool) -> some View {
        let palette = topic.palette
        let list = subs(topic)
        let hits = TopicPickerQuery.matchingSubs(list, needle: needle)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expanded = expanded == topic.id ? nil : topic.id
                }
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(palette.dot)
                        .frame(width: 10, height: 10)
                    Text(topic.name)
                        .font(style.ui(15, .semibold))
                        .foregroundStyle(QuickFileStyle.ink)
                    if !Self.builtIn.contains(topic.id) {
                        Text("yours")
                            .font(style.ui(10, .bold))
                            .foregroundStyle(palette.deep)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.tint, in: Capsule())
                    }
                    Spacer(minLength: 8)
                    Text("\(list.count)")
                        .font(style.ui(12, .medium))
                        .foregroundStyle(QuickFileStyle.inkSecondary)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(QuickFileStyle.inkFaint)
                }
                .frame(minHeight: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides its subtopics" : "Shows its subtopics")

            if open {
                QuickFileFlow(spacing: 7) {
                    pickChip(QuickFileCopy.just(topic.id), palette: palette, muted: true, hit: false) {
                        onPick(topic.id, nil)
                    }
                    ForEach(list, id: \.self) { sub in
                        pickChip(sub, palette: palette, muted: false, hit: hits.contains(sub)) {
                            onPick(topic.id, sub)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
    }

    private func pickChip(_ title: String, palette: CategoryPalette, muted: Bool, hit: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(style.ui(13, hit ? .bold : .semibold))
                .lineLimit(1)
                .foregroundStyle(muted ? QuickFileStyle.inkSecondary : palette.deep)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(muted ? QuickFileStyle.mutedControl : palette.tint.opacity(hit ? 1 : 0.5), in: Capsule())
                .overlay(Capsule().strokeBorder(hit ? palette.deep.opacity(0.55) : Color.clear, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No topic matches “\(needle)”")
                .font(style.ui(15, .semibold))
                .foregroundStyle(QuickFileStyle.ink)
            Text("New topics are made in the bookmarker app.")
                .font(style.ui(13, .regular))
                .foregroundStyle(QuickFileStyle.inkSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 40)
    }
}

/// Chips that wrap onto as many lines as they need, left-aligned.
struct QuickFileFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = fitted(view, maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = fitted(view, bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func fitted(_ view: LayoutSubview, _ maxWidth: CGFloat) -> CGSize {
        let size = view.sizeThatFits(.unspecified)
        guard size.width > maxWidth, maxWidth.isFinite else { return size }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
