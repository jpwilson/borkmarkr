import SwiftUI
import SwiftData

/// The Library's side-quest rail, after the first two rows of saves: a
/// section header, then the quest cards (clay art on top, the topic's clay
/// tint underneath), suggested quests, and a dashed "New side quest" slot of
/// the same size.
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
            SectionHeader(
                Copy.sideQuestsHeading,
                action: journeys.isEmpty ? Copy.startSideQuest : "See all",
                perform: journeys.isEmpty ? onStart : onSeeAll
            )
            .padding(.horizontal, Tokens.gutter)

            if let quiet {
                Text(quietCaption(quiet))
                    .textRole(.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.top, -6)
            }

            if journeys.isEmpty && seeds.isEmpty {
                emptyCard
                    .padding(.horizontal, Tokens.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Tokens.gridGap) {
                        ForEach(journeys) { quest in
                            Button { onOpen(quest) } label: {
                                QuestCard(
                                    title: quest.title,
                                    count: quest.bookmarkIDs.count,
                                    palette: quest.topic?.palette ?? NeutralPalette.value,
                                    cover: QuestCover.resolve(
                                        title: quest.title,
                                        categoryID: quest.categoryID,
                                        subcategory: Mission.dominantSubcategory(
                                            among: quest.attached(from: bookmarks)
                                        )
                                    ),
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
                                    cover: QuestCover.resolve(title: seed.title, categoryID: seed.categoryID, subcategory: seed.subcategory),
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
                                palette: NeutralPalette.value,
                                motif: .compass,
                                layout: .rail,
                                dashed: true
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, Tokens.gutter)
                    .padding(.vertical, 1)
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

    /// The coach card: what a quest is, how it differs from a topic, and the
    /// way in — beside the running scene, the example every line of copy
    /// uses. A flat white card with a hairline, like every other card.
    private var emptyCard: some View {
        Button(action: onStart) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.whatWorkingOn)
                        .textRole(.cardTitle, color: Tokens.ink)
                    Text(Copy.sideQuestOneLiner)
                        .textRole(.meta)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 2) {
                        Text(Copy.startSideQuest)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                    .foregroundStyle(accent.deep)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                QuestArt(motif: .run)
                    .frame(width: 76, height: 76)
                    .background(Tokens.clayGround)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
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
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])))
                            Text(Copy.newSideQuest)
                                .textRole(.cardTitle)
                            Spacer()
                        }
                        .foregroundStyle(accent.deep)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Tokens.slimRowHeight)
                        .cardSurface()
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
                                TopicDot(palette: quest.topic?.palette ?? NeutralPalette.value)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(quest.title)
                                        .textRole(.cardTitle, color: Tokens.ink)
                                    Text(Copy.countedBorks(quest.bookmarkIDs.count))
                                        .textRole(.meta)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(on ? accent.base : Tokens.inkFaint)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: Tokens.slimRowHeight)
                            .cardSurface()
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(Tokens.gutter)
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
        .claySheet()
    }
}
