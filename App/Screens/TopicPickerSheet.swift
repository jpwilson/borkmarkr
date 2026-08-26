import SwiftUI
import SwiftData

/// Pick a topic / subtopic, and manage the ones you added.
///
/// Built-ins stay a shipped constant — you add *around* them. Custom topics
/// and custom subtopics can be created, renamed and deleted from here. That
/// is also how you add a whole new topic, not only a subtopic under Fitness.
///
/// Search lives at the top of the sheet (not `.searchable`, which parks the
/// field under the keyboard). The list is A–Z. Expanding a topic never
/// replaces "Add a subtopic" with "create whatever is in the search box".
struct TopicPickerSheet: View {
    @Binding var categoryID: String?
    @Binding var subcategory: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]

    @Query(filter: #Predicate<CustomSubtopic> { $0.deletedAt == nil })
    private var customSubtopics: [CustomSubtopic]

    @State private var expanded: String?
    @State private var filter = ""
    @State private var newSubtopicTopic: Topic?
    @State private var newSubtopicName = ""
    @State private var showingNewTopic = false
    @State private var newTopicName = ""
    @State private var renamingTopic: CustomTopic?
    @State private var renamingSub: CustomSubtopic?
    @State private var renameDraft = ""
    @State private var confirmingDeleteTopic: CustomTopic?
    @State private var confirmingDeleteSub: CustomSubtopic?
    @State private var snapshotCategory: String?
    @State private var snapshotSub: String?
    @State private var didSnapshot = false
    @FocusState private var searchFocused: Bool

    private var merged: MergedTaxonomy {
        MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
    }

    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shown: [Topic] {
        TopicPickerQuery.shown(
            topics: merged.allTopics,
            subs: { merged.subs(for: $0) },
            filter: trimmedFilter
        )
    }

    private var canAddTopicFromFilter: Bool {
        TopicPickerQuery.canAddName(trimmedFilter, to: merged.allTopics.map(\.name))
    }

    private func canAdd(_ name: String, to topic: Topic) -> Bool {
        TopicPickerQuery.canAddName(name, to: merged.subs(for: topic))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            addTopicRow

                            ForEach(shown) { topic in
                                topicRow(topic)
                                    .id(topic.id)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear { scrollToExpanded(proxy) }
                    .onChange(of: expanded) { _, _ in scrollToExpanded(proxy) }
                    .onChange(of: trimmedFilter) { _, needle in
                        reconcileExpansion(needle: needle)
                        scrollToExpanded(proxy)
                    }
                }
            }
            .background(Tokens.paper)
            .navigationTitle("Pick a topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .alert("New subtopic",
                   isPresented: Binding(get: { newSubtopicTopic != nil },
                                        set: { if !$0 { newSubtopicTopic = nil } })) {
                TextField("Name", text: $newSubtopicName)
                Button("Add") {
                    if let topic = newSubtopicTopic {
                        addSubtopic(newSubtopicName, to: topic, dismissAfter: false)
                    }
                    newSubtopicTopic = nil
                    newSubtopicName = ""
                }
                Button("Cancel", role: .cancel) {
                    newSubtopicTopic = nil
                    newSubtopicName = ""
                }
            } message: {
                Text(newSubtopicTopic.map { "Added under \($0.name). You can add another, or tap Done." } ?? "")
            }
            .alert("New topic", isPresented: $showingNewTopic) {
                TextField("Name", text: $newTopicName)
                Button("Add") { addTopic(newTopicName) }
                Button("Cancel", role: .cancel) { newTopicName = "" }
            } message: {
                Text("A topic is the top-level file — like Fitness or Cars. After you add it you can give it subtopics, or just use the topic.")
            }
            .alert("Rename topic",
                   isPresented: Binding(get: { renamingTopic != nil },
                                        set: { if !$0 { renamingTopic = nil } })) {
                TextField("Name", text: $renameDraft)
                Button("Save") {
                    if let topic = renamingTopic { Store.renameTopic(topic, to: renameDraft, in: context) }
                    renamingTopic = nil
                }
                Button("Cancel", role: .cancel) { renamingTopic = nil }
            }
            .alert("Rename subtopic",
                   isPresented: Binding(get: { renamingSub != nil },
                                        set: { if !$0 { renamingSub = nil } })) {
                TextField("Name", text: $renameDraft)
                Button("Save") {
                    if let entry = renamingSub { Store.renameSubtopic(entry, to: renameDraft, in: context) }
                    renamingSub = nil
                }
                Button("Cancel", role: .cancel) { renamingSub = nil }
            }
            .confirmationDialog(
                "Delete \(confirmingDeleteTopic?.name ?? "this topic")?",
                isPresented: Binding(get: { confirmingDeleteTopic != nil },
                                     set: { if !$0 { confirmingDeleteTopic = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete topic", role: .destructive) {
                    if let topic = confirmingDeleteTopic {
                        Store.deleteTopic(topic, in: context)
                        if categoryID == topic.id {
                            categoryID = nil
                            subcategory = nil
                        }
                        if expanded == topic.id { expanded = nil }
                    }
                    confirmingDeleteTopic = nil
                }
                Button("Cancel", role: .cancel) { confirmingDeleteTopic = nil }
            } message: {
                Text("Borks filed here go back to Not filed yet. Built-in topics are not affected.")
            }
            .confirmationDialog(
                "Delete \(confirmingDeleteSub?.name ?? "this subtopic")?",
                isPresented: Binding(get: { confirmingDeleteSub != nil },
                                     set: { if !$0 { confirmingDeleteSub = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete subtopic", role: .destructive) {
                    if let entry = confirmingDeleteSub {
                        Store.deleteSubtopic(entry, in: context)
                        if subcategory == entry.name { subcategory = nil }
                    }
                    confirmingDeleteSub = nil
                }
                Button("Cancel", role: .cancel) { confirmingDeleteSub = nil }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .onAppear {
            if !didSnapshot {
                snapshotCategory = categoryID
                snapshotSub = subcategory
                didSnapshot = true
            }
            if expanded == nil {
                expanded = categoryID
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.base)
            TextField("Find a topic or subtopic", text: $filter)
                .font(Typo.ui(14.5))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searchFocused)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Tokens.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(searchFocused ? accent.base.opacity(0.55) : Tokens.hairline, lineWidth: searchFocused ? 1.5 : 1)
        )
    }

    private var addTopicRow: some View {
        Button {
            newTopicName = trimmedFilter
            showingNewTopic = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(canAddTopicFromFilter
                     ? "Add topic \u{201C}\(trimmedFilter)\u{201D}"
                     : "Add a topic")
                    .font(Typo.ui(14, .semibold))
                Spacer()
            }
            .foregroundStyle(accent.deep)
            .padding(13)
            .cardSurface(radius: 16)
        }
        .buttonStyle(.plain)
    }

    private func topicRow(_ topic: Topic) -> some View {
        let custom = merged.isCustomTopic(topic.id)
        let isOpen = expanded == topic.id
        let highlighted = TopicPickerQuery.matchingSubs(merged.subs(for: topic), needle: trimmedFilter)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        expanded = isOpen ? nil : topic.id
                    }
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(topic.palette.dot).frame(width: 10, height: 10)
                        Text(topic.name)
                            .font(Typo.ui(14.5, .semibold))
                            .foregroundStyle(Tokens.ink)
                        if custom {
                            Text("yours")
                                .font(Typo.ui(10, .bold))
                                .foregroundStyle(topic.palette.deep)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(topic.palette.tint, in: Capsule())
                        }
                        Spacer()
                        Text("\(merged.subs(for: topic).count)")
                            .font(Typo.ui(11.5, .medium))
                            .foregroundStyle(Tokens.inkMeta)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Tokens.inkFaint)
                    }
                }
                .buttonStyle(.plain)

                if custom, let entry = customTopics.first(where: { $0.id == topic.id }) {
                    Menu {
                        Button("Rename") {
                            renameDraft = entry.name
                            renamingTopic = entry
                        }
                        Button("Delete", role: .destructive) {
                            confirmingDeleteTopic = entry
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Tokens.inkMeta)
                    }
                }
            }

            if isOpen {
                FlowChips(
                    items: merged.subs(for: topic),
                    custom: Set(merged.subs(for: topic).filter { merged.isCustom($0, in: topic) }),
                    highlighted: highlighted,
                    onPick: { sub in
                        categoryID = topic.id
                        subcategory = sub
                        dismiss()
                    },
                    onRename: { name in
                        guard let entry = customSub(named: name, in: topic.id) else { return }
                        renameDraft = entry.name
                        renamingSub = entry
                    },
                    onDelete: { name in
                        confirmingDeleteSub = customSub(named: name, in: topic.id)
                    },
                    tint: { topic.palette }
                )

                Button {
                    categoryID = topic.id
                    subcategory = nil
                    dismiss()
                } label: {
                    Text("Just \(topic.name) — no subtopic")
                        .font(Typo.ui(12, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                }
                .buttonStyle(.plain)

                addButton(label: "Add a subtopic", topic: topic) {
                    newSubtopicTopic = topic
                    newSubtopicName = trimmedFilter
                }

                if canAdd(trimmedFilter, to: topic), !trimmedFilter.isEmpty {
                    addButton(label: "Use \u{201C}\(trimmedFilter)\u{201D} as a subtopic", topic: topic) {
                        addSubtopic(trimmedFilter, to: topic, dismissAfter: true)
                    }
                }
            }
        }
        .padding(13)
        .cardSurface(radius: 16)
    }

    private func addButton(label: String, topic: Topic, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(Typo.ui(12.5, .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(topic.palette.deep)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    private func customSub(named name: String, in topicID: String) -> CustomSubtopic? {
        customSubtopics.first {
            $0.categoryID == topicID && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Clearing search must not collapse the open topic. Auto-expand only
    /// when nothing is open (or the open row filtered out) and a sub matched.
    private func reconcileExpansion(needle: String) {
        if let expanded, shown.contains(where: { $0.id == expanded }) {
            return
        }
        guard !needle.isEmpty else { return }
        let subHit = shown.first { topic in
            TopicPickerQuery.matchRank(
                topicName: topic.name,
                subs: merged.subs(for: topic),
                needle: needle
            ) == 2
        }
        if let subHit {
            expanded = subHit.id
        }
    }

    private func scrollToExpanded(_ proxy: ScrollViewProxy) {
        let target = expanded
        guard let target, shown.contains(where: { $0.id == target }) else { return }
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
    }

    private func cancel() {
        categoryID = snapshotCategory
        subcategory = snapshotSub
        dismiss()
    }

    private func addSubtopic(_ raw: String, to topic: Topic, dismissAfter: Bool) {
        let formatted = TaxonomyName.formatted(raw)
        guard !formatted.isEmpty else { return }
        if canAdd(formatted, to: topic) {
            context.insert(CustomSubtopic(categoryID: topic.id, name: formatted))
            try? context.save()
            Haptics.success()
        } else {
            Haptics.tap()
        }
        let existingName = merged.subs(for: topic).first {
            $0.caseInsensitiveCompare(formatted) == .orderedSame
        }
        categoryID = topic.id
        subcategory = existingName ?? formatted
        expanded = topic.id
        if dismissAfter { dismiss() }
    }

    private func addTopic(_ raw: String) {
        let formatted = TaxonomyName.formatted(raw)
        guard formatted.count >= 2 else { return }
        filter = ""

        if let existing = customTopics.first(where: { $0.name.caseInsensitiveCompare(formatted) == .orderedSame }) {
            categoryID = existing.id
            subcategory = nil
            expanded = existing.id
            newTopicName = ""
            Haptics.tap()
            return
        }

        if let builtin = Taxonomy.all.first(where: { $0.name.caseInsensitiveCompare(formatted) == .orderedSame }) {
            categoryID = builtin.id
            subcategory = nil
            expanded = builtin.id
            newTopicName = ""
            Haptics.tap()
            return
        }

        let wantedID = CustomTopic.makeID(from: formatted)
        var lookup = FetchDescriptor<CustomTopic>(predicate: #Predicate { $0.id == wantedID })
        lookup.fetchLimit = 1
        if let existing = try? context.fetch(lookup).first {
            existing.deletedAt = nil
            existing.name = formatted
            existing.updatedAt = .now
            try? context.save()
            categoryID = existing.id
            subcategory = nil
            expanded = existing.id
            newTopicName = ""
            Haptics.success()
            return
        }

        let topic = CustomTopic(name: formatted, hue: CustomTopic.nextHue(existing: customTopics))
        context.insert(topic)
        try? context.save()
        categoryID = topic.id
        subcategory = nil
        expanded = topic.id
        newTopicName = ""
        Haptics.success()
    }
}

/// Wrapping chip row — subcategory lists run long and a horizontal scroller
/// hides most of them. Custom chips carry a menu to rename or delete.
struct FlowChips: View {
    let items: [String]
    var custom: Set<String> = []
    var highlighted: Set<String> = []
    let onPick: (String) -> Void
    var onRename: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    let tint: () -> CategoryPalette

    var body: some View {
        let palette = tint()
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let isCustom = custom.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
                let isHit = highlighted.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
                Button { onPick(item) } label: {
                    Text(item)
                        .font(Typo.ui(12, .semibold))
                        .foregroundStyle(palette.deep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.tint, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(palette.deep.opacity(isHit ? 0.85 : 0), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if isCustom {
                        Button("Rename") { onRename?(item) }
                        Button("Delete", role: .destructive) { onDelete?(item) }
                    }
                }
            }
        }
    }
}

/// Minimal flow layout — SwiftUI has no built-in wrapping stack.
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
