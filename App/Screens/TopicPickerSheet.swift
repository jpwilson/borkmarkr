import SwiftUI
import SwiftData

/// Pick a topic / subtopic, and manage the ones you added.
///
/// Built-ins stay a shipped constant — you add *around* them. Custom topics
/// and custom subtopics can be created, renamed and deleted from here. That
/// is also how you add a whole new topic, not only a subtopic under Fitness.
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

    private var merged: MergedTaxonomy {
        MergedTaxonomy(topics: customTopics, subtopics: customSubtopics)
    }

    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shown: [Topic] {
        let needle = trimmedFilter.lowercased()
        let all = merged.allTopics
        guard !needle.isEmpty else { return all }
        return all.filter { topic in
            topic.name.lowercased().contains(needle)
                || merged.subs(for: topic).contains { $0.lowercased().contains(needle) }
        }
    }

    private var canAddTopicFromFilter: Bool {
        let candidate = trimmedFilter.lowercased()
        guard candidate.count >= 2 else { return false }
        return !merged.allTopics.contains { $0.name.lowercased() == candidate }
    }

    private func canAdd(_ name: String, to topic: Topic) -> Bool {
        let candidate = name.lowercased()
        guard candidate.count >= 2 else { return false }
        return !merged.subs(for: topic).contains { $0.lowercased() == candidate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    addTopicRow

                    ForEach(shown) { topic in
                        topicRow(topic)
                    }
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle("Pick a topic")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "Find a topic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New subtopic",
                   isPresented: Binding(get: { newSubtopicTopic != nil },
                                        set: { if !$0 { newSubtopicTopic = nil } })) {
                TextField("Name", text: $newSubtopicName)
                Button("Add") {
                    if let topic = newSubtopicTopic { addSubtopic(newSubtopicName, to: topic) }
                    newSubtopicTopic = nil
                    newSubtopicName = ""
                }
                Button("Cancel", role: .cancel) {
                    newSubtopicTopic = nil
                    newSubtopicName = ""
                }
            } message: {
                Text(newSubtopicTopic.map { "Added under \($0.name)." } ?? "")
            }
            .alert("New topic", isPresented: $showingNewTopic) {
                TextField("Name", text: $newTopicName)
                Button("Add") { addTopic(newTopicName) }
                Button("Cancel", role: .cancel) { newTopicName = "" }
            } message: {
                Text("A topic is the top-level file — like Fitness or Cars. You can add subtopics inside it after.")
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
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        expanded = expanded == topic.id ? nil : topic.id
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
                        Image(systemName: expanded == topic.id ? "chevron.up" : "chevron.right")
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

            if expanded == topic.id {
                FlowChips(
                    items: merged.subs(for: topic),
                    custom: Set(merged.subs(for: topic).filter { merged.isCustom($0, in: topic) }),
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

                if canAdd(trimmedFilter, to: topic), !trimmedFilter.isEmpty {
                    addButton(label: "Add \u{201C}\(trimmedFilter)\u{201D}", topic: topic) {
                        addSubtopic(trimmedFilter, to: topic)
                    }
                } else {
                    addButton(label: "Add a subtopic", topic: topic) {
                        newSubtopicTopic = topic
                        newSubtopicName = trimmedFilter
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

    private func addSubtopic(_ raw: String, to topic: Topic) {
        let formatted = TaxonomyName.formatted(raw)
        guard !formatted.isEmpty else { return }
        context.insert(CustomSubtopic(categoryID: topic.id, name: formatted))
        try? context.save()
        categoryID = topic.id
        subcategory = formatted
        Haptics.success()
        dismiss()
    }

    private func addTopic(_ raw: String) {
        let formatted = TaxonomyName.formatted(raw)
        guard formatted.count >= 2 else { return }
        if let existing = customTopics.first(where: { $0.name.caseInsensitiveCompare(formatted) == .orderedSame }) {
            categoryID = existing.id
            subcategory = nil
            expanded = existing.id
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
    let onPick: (String) -> Void
    var onRename: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    let tint: () -> CategoryPalette

    var body: some View {
        let palette = tint()
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let isCustom = custom.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
                Button { onPick(item) } label: {
                    Text(item)
                        .font(Typo.ui(12, .semibold))
                        .foregroundStyle(palette.deep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.tint, in: Capsule())
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
