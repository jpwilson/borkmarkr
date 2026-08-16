import SwiftUI
import SwiftData

/// Side quests — what you're working on, and the borks that serve it.
///
/// Code type is still `Mission`. The UI noun is side quest. A quest is a reason
/// (become / decide / explore), not a topic. Topics file what a thing *is*.
struct MissionsView: View {
    var account: Account? = nil

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var missions: [Mission]

    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil })
    private var bookmarks: [Bookmark]

    @State private var creating = false
    @State private var pendingSeed: Mission.Seed?
    @State private var open: Mission?
    @State private var seeds: [Mission.Seed] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if missions.isEmpty {
                empty
            } else {
                ForEach(missions) { mission in
                    MissionCard(mission: mission) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            mission.toggle()
                            try? context.save()
                        }
                        Haptics.tap()
                    } onOpen: {
                        open = mission
                    }
                }
            }

            if !seeds.isEmpty {
                Text("FROM YOUR LIBRARY")
                    .font(Typo.ui(10, .heavy)).tracking(0.6)
                    .foregroundStyle(Tokens.mutedHeading)
                    .padding(.top, missions.isEmpty ? 4 : 8)

                ForEach(seeds) { seed in
                    Button { accept(seed) } label: {
                        QuestSeedRow(seed: seed)
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            Button { creating = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                    Text(Copy.newSideQuest).font(Typo.ui(13.5, .semibold))
                }
                .foregroundStyle(Tokens.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .sheet(isPresented: $creating) {
            NewMissionSheet(seed: pendingSeed)
                .environment(\.accent, accent)
                .onDisappear { pendingSeed = nil }
        }
        .sheet(item: $open) { mission in
            MissionDetailSheet(mission: mission, account: account).environment(\.accent, accent)
        }
        .task(id: bookmarks.count + missions.count) {
            var next = Mission.suggested(from: bookmarks, existing: missions)
            seeds = next

            let stiff = missions.filter { $0.title.lowercased().hasPrefix("get into ") }
            for quest in stiff {
                let items = bookmarks.filter { quest.bookmarkIDs.contains($0.id) }
                quest.title = Mission.draftTitle(
                    topic: quest.topic?.name ?? "",
                    subcategory: items.compactMap(\.subcategory).first,
                    titles: items.prefix(6).map(\.displayTitle)
                )
                quest.updatedAt = .now
            }
            if !stiff.isEmpty { try? context.save() }

            let session = await account?.currentSession()
            let stiffSeeds: [Mission.Seed] = stiff.map { quest in
                let items = bookmarks.filter { quest.bookmarkIDs.contains($0.id) }
                return Mission.Seed(
                    title: quest.title,
                    categoryID: quest.categoryID,
                    subcategory: items.compactMap(\.subcategory).first,
                    bookmarkIDs: quest.bookmarkIDs,
                    sampleTitles: items.prefix(6).map(\.displayTitle),
                    blurb: ""
                )
            }
            let refined = await SmartNamer.refine(next + stiffSeeds, session: session)
            let suggestionIDs = Set(next.map(\.id))
            seeds = refined.filter { suggestionIDs.contains($0.id) }
            var renamed = false
            for seed in refined where !suggestionIDs.contains(seed.id) {
                if let quest = stiff.first(where: { $0.categoryID == seed.categoryID || $0.id == seed.id }) {
                    quest.title = seed.title
                    quest.updatedAt = .now
                    renamed = true
                }
            }
            if renamed { try? context.save() }
        }
    }

    private func accept(_ seed: Mission.Seed) {
        let journey = Mission(title: seed.title, categoryID: seed.categoryID)
        journey.bookmarkIDs = seed.bookmarkIDs
        context.insert(journey)
        try? context.save()
        Haptics.success()
        open = journey
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Copy.whatWorkingOn)
                    .font(Typo.display(20, .heavy))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Become a faster runner. Decide on a van. Learn pottery. A side quest is why you kept the links — not another folder.")
                    .font(Typo.ui(13.5))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { creating = true } label: {
                Text(Copy.startSideQuest)
                    .font(Typo.ui(14.5, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                    .shadow(color: accent.base.opacity(0.3), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.base.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct MissionCard: View {
    @Bindable var mission: Mission
    let onTick: () -> Void
    let onOpen: () -> Void

    @Environment(\.accent) private var accent

    private var palette: CategoryPalette {
        mission.topic?.palette ?? NeutralPalette.value
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    QuestCard(
                        title: mission.title,
                        count: mission.bookmarkIDs.count,
                        palette: palette,
                        motif: QuestMotif.resolve(title: mission.title, categoryID: mission.categoryID),
                        layout: .row,
                        quiet: false,
                        habit: mission.hasHabit,
                        topicName: mission.topic?.name
                    )
                    if mission.hasHabit {
                        TickButton(done: mission.isDone(), tint: accent.base, action: onTick)
                            .padding(12)
                    }
                }

                if mission.hasHabit {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            if mission.streak() > 0 {
                                Label("\(mission.streak()) day streak", systemImage: "flame.fill")
                                    .font(Typo.ui(11.5, .bold))
                                    .foregroundStyle(accent.deep)
                            }
                            Text("\(mission.completions(inLast: 30))/30 days")
                                .font(Typo.ui(11.5, .medium))
                                .foregroundStyle(Tokens.inkMeta)
                            Spacer()
                        }
                        WeekStrip(mission: mission, tint: accent.base)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .background(palette.tint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Big, satisfying, unmissable. The daily tick is the entire retention loop —
/// it should not be a checkbox you hunt for.
private struct TickButton: View {
    let done: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(done ? tint : Tokens.mutedControl)
                    .frame(width: 40, height: 40)
                Image(systemName: done ? "checkmark" : "circle.dashed")
                    .font(.system(size: done ? 17 : 15, weight: .bold))
                    .foregroundStyle(done ? .white : Tokens.inkFaint)
            }
            .scaleEffect(done ? 1.0 : 0.94)
            .shadow(color: done ? tint.opacity(0.4) : .clear, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Done today" : "Mark done today")
    }
}

/// Last seven days at a glance.
private struct WeekStrip: View {
    let mission: Mission
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                let done = mission.isDone(on: day)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(done ? tint : Tokens.mutedControl)
                        .frame(height: 22)
                    Text(letter(for: day))
                        .font(Typo.ui(9, .semibold))
                        .foregroundStyle(Tokens.inkFaint)
                }
            }
        }
    }

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private func letter(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.narrow))
    }
}

// MARK: - Create

struct NewMissionSheet: View {
    var seed: Mission.Seed? = nil
    var seedIDs: [String] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context

    @State private var title = ""
    @State private var habit = ""
    @State private var categoryID: String?
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field(label: "WORKING ON", placeholder: "Become a faster runner · Which minivan · Learn pottery", text: $title)
                    field(label: "DAILY HABIT — ONLY IF IT NEEDS ONE", placeholder: "Leave blank for research or exploring", text: $habit)

                    Button { showingPicker = true } label: {
                        HStack {
                            Text(Taxonomy.category(id: categoryID)?.name ?? "Link a topic")
                                .font(Typo.ui(13.5, .semibold))
                                .foregroundStyle(Taxonomy.category(id: categoryID)?.palette.deep ?? Tokens.inkSecondary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Tokens.inkFaint)
                        }
                        .padding(14)
                        .cardSurface(radius: 16)
                    }
                    .buttonStyle(.plain)

                    Text("OR PICK ONE")
                        .font(Typo.ui(10, .heavy)).tracking(0.6)
                        .foregroundStyle(Tokens.mutedHeading)

                    FlowLayout(spacing: 7) {
                        ForEach(Mission.templates, id: \.title) { template in
                            Button {
                                title = template.title
                                habit = template.habit
                                categoryID = template.categoryID
                            } label: {
                                Text(template.title)
                                    .font(Typo.ui(12.5, .semibold))
                                    .foregroundStyle(Taxonomy.category(id: template.categoryID)?.palette.deep ?? Tokens.inkSecondary)
                                    .padding(.horizontal, 11).padding(.vertical, 8)
                                    .background(
                                        Taxonomy.category(id: template.categoryID)?.palette.tint ?? Tokens.mutedControl,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle(Copy.newSideQuest)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let seed {
                    title = seed.title
                    categoryID = seed.categoryID
                }
            }
            .sheet(isPresented: $showingPicker) {
                TopicPickerSheet(categoryID: $categoryID, subcategory: .constant(nil))
                    .environment(\.accent, accent)
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            TextField(placeholder, text: text)
                .font(Typo.ui(15))
                .padding(14)
                .cardSurface(radius: 16)
        }
    }

    private func create() {
        let mission = Mission(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryID: categoryID,
            habitName: habit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        mission.bookmarkIDs = seed?.bookmarkIDs ?? seedIDs
        context.insert(mission)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

// MARK: - Detail

struct MissionDetailSheet: View {
    @Bindable var mission: Mission
    var account: Account? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil }, sort: \Bookmark.savedAt, order: .reverse)
    private var allBookmarks: [Bookmark]

    @State private var detail: Bookmark?
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @State private var draftThoughts = ""
    @State private var newTodo = ""
    @State private var reordering = false

    private var attached: [Bookmark] {
        let map = Dictionary(uniqueKeysWithValues: allBookmarks.map { ($0.id, $0) })
        return mission.bookmarkIDs.compactMap { map[$0] }
    }

    /// Brks in the mission's topic that aren't attached yet — the "these might
    /// help" list, which is the whole point of linking missions to the library.
    private var suggested: [Bookmark] {
        guard let categoryID = mission.categoryID else { return [] }
        return allBookmarks
            .filter { $0.categoryID == categoryID && !mission.bookmarkIDs.contains($0.id) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mission.hasHabit { habitBlock }

                    summaryCard
                    thoughtsCard
                    todoCard

                    HStack {
                        section("ON THIS SIDE QUEST", count: attached.count)
                        Spacer()
                        if attached.count > 1 {
                            Button(reordering ? "Done" : "Reorder") {
                                withAnimation(.easeOut(duration: 0.18)) { reordering.toggle() }
                            }
                            .font(Typo.ui(12, .semibold))
                            .foregroundStyle(accent.deep)
                        }
                    }

                    if attached.isEmpty {
                        Text("Nothing attached yet. Pull in the borks that actually help.")
                            .font(Typo.ui(13))
                            .foregroundStyle(Tokens.inkSecondary)
                    } else {
                        ForEach(Array(attached.enumerated()), id: \.element.id) { index, bookmark in
                            HStack(spacing: 8) {
                                if reordering {
                                    VStack(spacing: 4) {
                                        Button {
                                            moveBork(from: index, by: -1)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .disabled(index == 0)
                                        Button {
                                            moveBork(from: index, by: 1)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .disabled(index == attached.count - 1)
                                    }
                                    .foregroundStyle(accent.deep)
                                    .buttonStyle(.plain)
                                }
                                Button { detail = bookmark } label: {
                                    BookmarkRow(bookmark: bookmark)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    if !suggested.isEmpty {
                        section("FROM THIS TOPIC", count: suggested.count)
                        ForEach(suggested) { bookmark in
                            HStack(spacing: 10) {
                                Button { detail = bookmark } label: {
                                    BookmarkRow(bookmark: bookmark)
                                }
                                .buttonStyle(PressableStyle())

                                Button {
                                    mission.bookmarkIDs.append(bookmark.id)
                                    mission.updatedAt = .now
                                    try? context.save()
                                    Haptics.tap()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(accent.base)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(Tokens.paper)
            .navigationTitle(editingTitle ? "Rename" : mission.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        draftTitle = mission.title
                        editingTitle = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(mission.title)
                                .font(Typo.ui(16, .bold))
                                .foregroundStyle(Tokens.ink)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Tokens.inkFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .alert("Rename side quest", isPresented: $editingTitle) {
                TextField("Name", text: $draftTitle)
                Button("Save") {
                    let cleaned = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        mission.title = cleaned
                        mission.updatedAt = .now
                        try? context.save()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        ShareLink(item: mission.shareText(from: allBookmarks)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            mission.deletedAt = .now
                            try? context.save()
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .sheet(item: $detail) { DetailSheet(bookmark: $0).environment(\.accent, accent) }
            .onAppear { draftThoughts = mission.detail ?? "" }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE THREAD")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            Text(mission.summary(from: allBookmarks))
                .font(Typo.ui(14.5))
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var thoughtsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR THOUGHTS")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            TextField("What are you noticing? What do you want to try?", text: $draftThoughts, axis: .vertical)
                .font(Typo.ui(14.5))
                .lineLimit(3...8)
                .onChange(of: draftThoughts) { _, value in
                    mission.detail = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    mission.updatedAt = .now
                    try? context.save()
                }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 18)
    }

    private var todoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TO-DO")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)

            ForEach(mission.todos) { item in
                Button {
                    var next = mission.todos
                    if let i = next.firstIndex(of: item) {
                        next[i].done.toggle()
                        mission.todos = next
                        try? context.save()
                    }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(item.done ? accent.base : Tokens.inkFaint)
                        Text(item.title)
                            .font(Typo.ui(14.5))
                            .foregroundStyle(item.done ? Tokens.inkMeta : Tokens.ink)
                            .strikethrough(item.done)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Button {
                            mission.todos = mission.todos.filter { $0.id != item.id }
                            try? context.save()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Tokens.inkFaint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Add a step", text: $newTodo)
                    .font(Typo.ui(14.5))
                    .submitLabel(.done)
                    .onSubmit(addTodo)
                Button(action: addTodo) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(accent.base)
                }
                .buttonStyle(.plain)
                .disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 18)
    }

    private func addTodo() {
        let title = newTodo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        mission.todos = mission.todos + [QuestTodo(title: title)]
        newTodo = ""
        try? context.save()
        Haptics.tap()
    }

    private func moveBork(from index: Int, by delta: Int) {
        var ids = mission.bookmarkIDs
        let next = index + delta
        guard ids.indices.contains(index), ids.indices.contains(next) else { return }
        ids.swapAt(index, next)
        mission.bookmarkIDs = ids
        mission.updatedAt = .now
        try? context.save()
    }

    private var habitBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mission.habitName ?? "")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(Tokens.ink)
                    Text(mission.streak() > 0
                         ? "\(mission.streak()) day streak · \(mission.completions(inLast: 30))/30"
                         : "\(mission.completions(inLast: 30))/30 days this month")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mission.toggle()
                        try? context.save()
                    }
                    Haptics.tap()
                } label: {
                    ZStack {
                        Circle()
                            .fill(mission.isDone() ? accent.base : Tokens.mutedControl)
                            .frame(width: 46, height: 46)
                        Image(systemName: mission.isDone() ? "checkmark" : "circle.dashed")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(mission.isDone() ? .white : Tokens.inkFaint)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func section(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            Text("\(count)")
                .font(Typo.ui(10, .heavy))
                .foregroundStyle(Tokens.inkFaint)
            Spacer()
        }
        .padding(.top, 6)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
