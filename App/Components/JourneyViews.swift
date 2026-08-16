import SwiftUI
import SwiftData

/// Horizontal rail of side quests for Library.
struct JourneyRail: View {
    let journeys: [Mission]
    let bookmarks: [Bookmark]
    let onOpen: (Mission) -> Void
    let onSeeAll: () -> Void
    let onStart: () -> Void
    var onAcceptSeed: ((Mission.Seed) -> Void)?
    var account: Account?

    @Environment(\.accent) private var accent
    @State private var seeds: [Mission.Seed] = []

    private var quiet: Mission? {
        journeys.first { $0.isQuiet(among: bookmarks) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.sideQuestsHeading)
                    .font(Typo.display(18, .bold))
                    .foregroundStyle(Tokens.ink)
                Spacer()
                Button(journeys.isEmpty ? Copy.startSideQuest : "See all", action: journeys.isEmpty ? onStart : onSeeAll)
                    .font(Typo.ui(12.5, .semibold))
                    .foregroundStyle(accent.deep)
            }
            .padding(.horizontal, 18)

            if let quiet {
                Text(quietCaption(quiet))
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.horizontal, 18)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if journeys.isEmpty && seeds.isEmpty {
                emptyCard
                    .padding(.horizontal, 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(journeys) { quest in
                            Button { onOpen(quest) } label: {
                                QuestCard(
                                    title: quest.title,
                                    count: quest.bookmarkIDs.count,
                                    palette: quest.topic?.palette ?? NeutralPalette.value,
                                    motif: QuestMotif.resolve(title: quest.title, categoryID: quest.categoryID),
                                    layout: .rail,
                                    quiet: quest.isQuiet(among: bookmarks),
                                    habit: quest.hasHabit,
                                    topicName: quest.topic?.name
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                        ForEach(seeds) { seed in
                            Button { onAcceptSeed?(seed) } label: {
                                QuestCard(
                                    title: seed.title,
                                    count: seed.bookmarkIDs.count,
                                    palette: Taxonomy.category(id: seed.categoryID)?.palette ?? NeutralPalette.value,
                                    motif: QuestMotif.resolve(title: seed.title, categoryID: seed.categoryID, subcategory: seed.subcategory),
                                    layout: .rail,
                                    suggested: true,
                                    topicName: Taxonomy.category(id: seed.categoryID)?.name,
                                    blurb: seed.blurb
                                )
                            }
                            .buttonStyle(PressableStyle())
                        }
                        Button(action: onStart) {
                            QuestCard(
                                title: Copy.newSideQuest,
                                count: 0,
                                palette: CategoryPalette(hue: 18),
                                motif: .compass,
                                layout: .rail,
                                dashed: true
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 2)
                }
            }
        }
        .task(id: bookmarks.count + journeys.count) {
            var next = Mission.suggested(from: bookmarks, existing: journeys)
            seeds = next
            let session = await account?.currentSession()
            next = await SmartNamer.refine(next, session: session)
            seeds = next
        }
    }

    private func quietCaption(_ quest: Mission) -> String {
        let n = quest.bookmarkIDs.count
        return "You saved \(Copy.countedBorks(n)) for \(quest.title) and have not looked lately."
    }

    private var emptyCard: some View {
        Button(action: onStart) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Copy.whatWorkingOn)
                    .font(Typo.display(17, .bold))
                    .foregroundStyle(Tokens.ink)
                Text("A side quest is why you kept something — get better at running, pick a van, learn pottery. Not another topic.")
                    .font(Typo.ui(13))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Copy.startSideQuest)
                    .font(Typo.ui(13.5, .bold))
                    .foregroundStyle(accent.deep)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accent.base.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}



/// Pick existing side quests, or start a new one, for a single bork.
struct JourneyPickerSheet: View {
    let bookmarkID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    Button { creating = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text(Copy.newSideQuest)
                                .font(Typo.ui(14, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(accent.deep)
                        .padding(14)
                        .cardSurface(radius: 16)
                    }
                    .buttonStyle(.plain)

                    ForEach(journeys) { quest in
                        let on = quest.contains(bookmarkID)
                        Button {
                            if on { quest.detach(bookmarkID) } else { quest.attach(bookmarkID) }
                            try? context.save()
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill((quest.topic?.palette ?? NeutralPalette.value).dot)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(quest.title)
                                        .font(Typo.ui(14.5, .semibold))
                                        .foregroundStyle(Tokens.ink)
                                    Text(Copy.countedBorks(quest.bookmarkIDs.count))
                                        .font(Typo.ui(11.5))
                                        .foregroundStyle(Tokens.inkMeta)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(on ? accent.base : Tokens.inkFaint)
                            }
                            .padding(14)
                            .cardSurface(radius: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle("Add to a side quest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $creating) {
                NewMissionSheet(seedIDs: [bookmarkID])
                    .environment(\.accent, accent)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }
}
