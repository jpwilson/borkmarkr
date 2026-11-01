import SwiftUI
import SwiftData

/// "Sort your borks": the saves still waiting on a topic, one at a time, one
/// tap each.
///
/// Two decks. **Not filed yet** is every live bork with no valid topic, newest
/// first. **Check our guesses** is the app's own guesses (`automatic`) from the
/// last 30 days that today's ranking still isn't sure of, each shown with its
/// guess first. A legacy filing (no `filingSource`) is never asked about.
///
/// The card sits on a little stack of the next two; the dial is the same one
/// the share sheet and the Add sheet use. Filing writes `"user"` at once and
/// the card flies into its topic's tally chip while the next one rises, its
/// ranking already computed. What you file teaches the ranking as you go
/// (`FilingMemory.adding`), so the second save from a creator you just filed
/// arrives sorted. Undo walks back one step at a time: a filing, a skip or a
/// removal.
///
/// The model is asked only when signed in, only for the next two cards that
/// have no evidence at all, and at most 12 times a session: the 200-a-day
/// quota is shared with everything else that asks. Answers for cards left
/// unsorted are kept as the app's guess when the sheet closes, the way the
/// Library's own pass would. On-screen text is read carefully (`.accurate`)
/// for the card in front and the two behind it.
struct TriageSheet: View {

    enum Deck: String, CaseIterable, Identifiable, Sendable {
        case unfiled, guesses
        var id: String { rawValue }

        var title: String {
            switch self {
            case .unfiled: "Not filed yet"
            case .guesses: "Check our guesses"
            }
        }
    }

    var deck: Deck = .unfiled
    var account: Account?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(
        filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil },
        sort: \Bookmark.savedAt, order: .reverse
    )
    private var library: [Bookmark]

    @Query(filter: #Predicate<CustomTopic> { $0.deletedAt == nil })
    private var customTopics: [CustomTopic]

    @State private var shown = Deck.unfiled
    @State private var started = false
    @State private var cards: [Bookmark] = []
    @State private var position = 0
    @State private var model: QuickFileModel?
    @State private var order: [String] = []
    /// The library's memory when the sheet opened, and what this session added.
    @State private var baseMemory = FilingMemory.empty
    @State private var picks: [FilingHistoryItem] = []
    @State private var memory = FilingMemory.empty
    @State private var tallies: [Tally] = []
    @State private var history: [Step] = []
    /// Filed or removed this session, so a deck switch never deals them again.
    @State private var handled: Set<String> = []
    @State private var sortedCount = 0
    @State private var startedAt = Date.now
    @State private var finishedAt: Date?
    @State private var unfiledCount = 0
    @State private var guessCount = 0
    @State private var answers: [String: Categorizer.Suggestion] = [:]
    /// `updatedAt` when the model was asked, so a late answer never lands on a
    /// bork that changed meanwhile.
    @State private var asked: [String: Date] = [:]
    @State private var landing: Landing?
    @State private var bumped: String?
    @State private var showingPicker = false
    @State private var pickedTopic: String?
    @State private var pickedSub: String?
    @Namespace private var flight

    private static let modelBudget = 12
    private static let modelLookahead = 2
    private static let readLookahead = 3

    private struct Tally: Identifiable, Equatable {
        let id: String
        var count: Int
    }

    private struct Filing {
        let categoryID: String?
        let subcategory: String?
        let source: String?
    }

    private enum Step {
        case filed(Bookmark, before: Filing, topic: String)
        case skipped(Bookmark)
        case removed(Bookmark)
    }

    /// A filed card on its way into its tally chip.
    private struct Landing {
        let card: Bookmark
        let topic: String
    }

    private var style: QuickFileStyle { .app(accent) }

    private var current: Bookmark? {
        cards.indices.contains(position) ? cards[position] : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Layout(size: geometry.size)
            VStack(spacing: 0) {
                topBar
                progressBar
                tallyRow
                    .zIndex(2)
                if let card = current, let model {
                    stack(layout)
                        .padding(.top, 6)
                    Spacer(minLength: 4)
                    QuickFileHeader(model: model, style: style)
                        .padding(.bottom, 8)
                    QuickFileDial(model: model, style: style, diameter: layout.dial)
                        .id(ObjectIdentifier(model))
                    QuickFileDialFooter(model: model, style: style)
                        .padding(.top, 10)
                        .padding(.horizontal, 18)
                    actions(card)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else if started {
                    endScreen
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Tokens.paper.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .onAppear(perform: start)
        .onDisappear(perform: finish)
        .sheet(isPresented: $showingPicker, onDismiss: filePick) {
            TopicPickerSheet(categoryID: $pickedTopic, subcategory: $pickedSub)
                .environment(\.accent, accent)
        }
    }

    // MARK: Layout

    /// The card takes whatever the dial leaves, between 120 and 260 pt; on a
    /// short phone the dial gives up a little first, never below 220 pt.
    private struct Layout {
        let dial: CGFloat
        let card: CGFloat
        let width: CGFloat

        init(size: CGSize) {
            // Top bar, progress, tallies, header, footer, actions and gaps.
            let fixed: CGFloat = 268
            let peeks: CGFloat = 20
            var dial = min(280, size.width - 64)
            var card = size.height - fixed - peeks - dial
            if card < 150 {
                dial = max(220, dial - (150 - card))
                card = size.height - fixed - peeks - dial
            }
            self.dial = dial
            self.card = min(260, max(120, card))
            self.width = min(self.card * 7 / 8, size.width - 72)
        }
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .center) {
            Button("Done") { dismiss() }
                .font(Typo.ui(15, .semibold))
                .foregroundStyle(accent.deep)
                .frame(minWidth: 64, minHeight: 44, alignment: .leading)

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Text("Sort your borks")
                    .font(Typo.display(17, .heavy))
                    .foregroundStyle(Tokens.ink)
                deckMenu
            }

            Spacer(minLength: 4)

            Button { undo() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                    Text("Undo")
                        .font(Typo.ui(15, .semibold))
                }
                .foregroundStyle(history.isEmpty ? Tokens.inkFaint : accent.deep)
                .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(history.isEmpty)
            .accessibilityHint("Takes back the last filing, skip or removal")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var counterLine: String {
        guard !cards.isEmpty else { return shown.title }
        let shownPosition = min(position + 1, cards.count)
        return current == nil ? "\(cards.count) of \(cards.count) · \(shown.title)"
                              : "\(shownPosition) of \(cards.count) · \(shown.title)"
    }

    private var deckMenu: some View {
        Menu {
            ForEach(Deck.allCases) { option in
                Button {
                    if option != shown { load(option) }
                } label: {
                    let count = option == .unfiled ? unfiledCount : guessCount
                    if option == shown {
                        Label("\(option.title) · \(count)", systemImage: "checkmark")
                    } else {
                        Text("\(option.title) · \(count)")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(counterLine)
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(Typo.ui(12.5, .semibold))
            .foregroundStyle(Tokens.inkMeta)
            .animation(.easeOut(duration: 0.2), value: position)
        }
        .accessibilityLabel("\(counterLine). Switch deck")
    }

    private var progressBar: some View {
        let fraction: CGFloat = cards.isEmpty ? 1 : CGFloat(min(position, cards.count)) / CGFloat(cards.count)
        return GeometryReader { bar in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.hairline)
                Capsule()
                    .fill(accent.base)
                    .frame(width: max(0, bar.size.width * fraction))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.25), value: fraction)
        .accessibilityHidden(true)
    }

    /// This session's filings by topic, the most recent four. A filed card
    /// flies into its chip, so the row is drawn above the stack.
    private var tallyRow: some View {
        HStack(spacing: 6) {
            if tallies.isEmpty {
                Text("Filed borks gather here")
                    .font(Typo.ui(12, .medium))
                    .foregroundStyle(Tokens.inkFaint)
            } else {
                if tallies.count > 4 {
                    Text("+\(tallies.count - 4)")
                        .font(Typo.ui(12.5, .bold))
                        .foregroundStyle(Tokens.inkMeta)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Tokens.mutedControl, in: Capsule())
                }
                ForEach(tallies.suffix(4)) { tally in
                    tallyChip(tally)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.horizontal, 18)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.8), value: tallies)
    }

    private func tallyChip(_ tally: Tally) -> some View {
        let palette = QuickFileStyle.palette(for: tally.id)
        return HStack(spacing: 6) {
            QuickFileArtDisc(topicID: tally.id, size: 22, style: style)
                .overlay {
                    if let landing, landing.topic == tally.id {
                        CoverImage(url: landing.card.imageURL, palette: landing.card.category?.palette ?? palette)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .matchedGeometryEffect(id: landing.card.id, in: flight)
                    }
                }
            Text(QuickFileCopy.topicName(tally.id))
                .font(Typo.ui(12.5, .semibold))
                .lineLimit(1)
            Text("\(tally.count)")
                .font(Typo.ui(12.5, .heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(palette.deep)
        .padding(.leading, 4)
        .padding(.trailing, 11)
        .frame(height: 30)
        .background(palette.tint.opacity(0.6), in: Capsule())
        .scaleEffect(bumped == tally.id && !reduceMotion ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: bumped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(QuickFileCopy.topicName(tally.id)), \(tally.count) filed")
    }

    // MARK: The stack

    private func stack(_ layout: Layout) -> some View {
        let upcoming = Array(cards[position..<min(position + 3, cards.count)].enumerated())
        return ZStack(alignment: .top) {
            ForEach(upcoming.reversed(), id: \.element.id) { depth, card in
                // Matched before it is moved into place, so a filed card
                // flies from exactly where it was drawn.
                TriageCard(bookmark: card, width: layout.width, height: layout.card)
                    // The cards behind recede into the paper.
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Tokens.paper.opacity(depth == 0 ? 0 : (depth == 1 ? 0.45 : 0.7)))
                    }
                    .matchedGeometryEffect(id: card.id, in: flight)
                    .padding(.top, CGFloat(2 - depth) * 10)
                    .scaleEffect(depth == 0 ? 1 : (depth == 1 ? 0.95 : 0.9), anchor: .top)
                    .zIndex(Double(-depth))
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .opacity.combined(with: .scale(scale: 0.94))))
                    .accessibilityHidden(depth > 0)
            }
        }
        .frame(height: layout.card + 20, alignment: .top)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.86), value: position)
    }

    private func actions(_ card: Bookmark) -> some View {
        HStack(spacing: 10) {
            Button { remove(card) } label: {
                Label("Remove", systemImage: "trash")
                    .font(Typo.ui(15, .semibold))
                    .foregroundStyle(Tokens.destructive)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Tokens.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.hairline, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .accessibilityHint("Deletes this bork. Undo brings it back.")

            Button { skip(card) } label: {
                HStack(spacing: 6) {
                    Text("Skip")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(Typo.ui(15, .semibold))
                .foregroundStyle(Tokens.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Tokens.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Tokens.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .accessibilityHint("Leaves it as it is for now")
        }
        .padding(.horizontal, 18)
    }

    // MARK: The end

    private var sortedLine: String {
        let seconds = max(1, Int(((finishedAt ?? .now).timeIntervalSince(startedAt)).rounded()))
        let time = seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
        return "\(sortedCount) sorted in \(time)"
    }

    private var skippedAny: Bool {
        history.contains { step in
            if case .skipped = step { return true }
            return false
        }
    }

    private var endScreen: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 12)
            QuestArt(motif: .compass)
                .frame(width: 228, height: 228)
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: Tokens.ink.opacity(0.12), radius: 22, y: 14)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .accessibilityHidden(true)
                .padding(.bottom, 10)

            Text(cards.isEmpty ? (shown == .unfiled ? "Every bork has a topic." : "Nothing to check.")
                 : (skippedAny ? "All caught up." : "Everything has a home."))
                .font(Typo.display(28, .heavy))
                .tracking(-0.6)
                .foregroundStyle(Tokens.ink)
                .multilineTextAlignment(.center)

            Group {
                if sortedCount > 0 {
                    Text(sortedLine)
                } else if cards.isEmpty {
                    Text(shown == .unfiled ? "Everything you save gets a home here." : "Our guesses all look right.")
                } else {
                    Text("Skipped ones wait here for next time.")
                }
            }
            .font(Typo.ui(15, .medium))
            .foregroundStyle(Tokens.inkSecondary)
            .multilineTextAlignment(.center)

            Spacer(minLength: 12)

            if shown == .unfiled, guessCount > 0 {
                endButton("Check \(guessCount) \(guessCount == 1 ? "guess" : "guesses")") { load(.guesses) }
            } else if shown == .guesses, unfiledCount > 0 {
                endButton("Sort \(unfiledCount) not filed yet") { load(.unfiled) }
            }

            Button("Done") { dismiss() }
                .font(Typo.ui(15, .semibold))
                .foregroundStyle(accent.deep)
                .frame(minHeight: 44)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private func endButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.ui(16, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.base, in: Capsule())
                .shadow(color: accent.base.opacity(0.3), radius: 14, y: 7)
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    // MARK: Session

    private func start() {
        guard !started else { return }
        // Your own topics must be known to `Taxonomy`, or their borks would
        // read as unfiled and their names as ids.
        _ = MergedTaxonomy(topics: customTopics)
        order = QuickFileBridge.taxonomyOrder(customIDs: customTopics.map(\.id))
        baseMemory = QuickFileBridge.memory(library)
        memory = baseMemory
        startedAt = .now
        load(deck)
        started = true
    }

    /// Deals a deck: everything in it this session hasn't already handled.
    private func load(_ next: Deck) {
        let unfiled = Self.unfiled(library).filter { !handled.contains($0.id) }
        let guesses = Self.guesses(library, memory: memory, order: order).filter { !handled.contains($0.id) }
        unfiledCount = unfiled.count
        guessCount = guesses.count
        shown = next
        cards = next == .unfiled ? unfiled : guesses
        position = 0
        history = []
        present()
    }

    /// The dial for the card in front, or the end.
    private func present() {
        guard let card = current else {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.82)) {
                model = nil
            }
            if finishedAt == nil { finishedAt = .now }
            guessCount = Self.guesses(library, memory: memory, order: order).filter { !handled.contains($0.id) }.count
            unfiledCount = Self.unfiled(library).filter { !handled.contains($0.id) }.count
            return
        }
        finishedAt = nil
        model = makeModel(for: card)
        prefetch()
    }

    private func makeModel(for card: Bookmark) -> QuickFileModel {
        let input = QuickFileBridge.input(for: card, ocr: ThumbnailText.cached(card.id))
        let model = QuickFileModel(ranking: ranking(for: card, input: input), input: input)
        model.onConfirm = { candidate in file(card, as: candidate) }
        model.onMore = {
            pickedTopic = nil
            pickedSub = nil
            showingPicker = true
        }
        QuickFileAppArt.preload(model.candidates.map(\.categoryID))
        return model
    }

    private func ranking(for card: Bookmark, input: FilingInput) -> FilingRanking {
        let pin = shown == .guesses ? QuickFileBridge.pin(for: card) : nil
        return FilingSuggest.rank(input, memory: memory, ai: answers[card.id], pinned: pin, taxonomyOrder: order)
    }

    // MARK: Acting

    private func file(_ card: Bookmark, as candidate: FilingCandidate) {
        let before = Filing(categoryID: card.categoryID, subcategory: card.subcategory, source: card.filingSource)
        card.categoryID = candidate.categoryID
        card.subcategory = candidate.subcategory
        card.filingSource = "user"
        card.touch()
        try? context.save()

        picks.append(FilingHistoryItem(categoryID: candidate.categoryID, subcategory: candidate.subcategory,
                                       author: card.author, url: card.url, at: .now))
        memory = baseMemory.adding(picks, now: .now)
        history.append(.filed(card, before: before, topic: candidate.categoryID))
        handled.insert(card.id)
        sortedCount += 1

        let flies = !reduceMotion
        withAnimation(flies ? .spring(response: 0.42, dampingFraction: 0.84) : .easeOut(duration: 0.15)) {
            tally(candidate.categoryID, by: 1)
            if flies { landing = Landing(card: card, topic: candidate.categoryID) }
            position += 1
        }
        bumped = candidate.categoryID

        // Let the dial's press and check register before the next card's
        // dial deals in; the card in front has already moved on.
        let expected = position
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard position == expected else { return }
            present()
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.15)) {
                if landing?.card.id == card.id { landing = nil }
            }
            if bumped == candidate.categoryID { bumped = nil }
        }
    }

    private func skip(_ card: Bookmark) {
        history.append(.skipped(card))
        withAnimation(.easeOut(duration: 0.18)) { position += 1 }
        present()
    }

    private func remove(_ card: Bookmark) {
        card.deletedAt = .now
        card.touch()
        try? context.save()
        handled.insert(card.id)
        history.append(.removed(card))
        withAnimation(.easeOut(duration: 0.18)) { position += 1 }
        present()
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        switch last {
        case let .filed(card, before, topic):
            card.categoryID = before.categoryID
            card.subcategory = before.subcategory
            card.filingSource = before.source
            card.touch()
            try? context.save()
            if !picks.isEmpty { picks.removeLast() }
            memory = baseMemory.adding(picks, now: .now)
            handled.remove(card.id)
            sortedCount = max(0, sortedCount - 1)
            withAnimation(.easeOut(duration: 0.2)) {
                tally(topic, by: -1)
                landing = nil
                position = max(0, position - 1)
            }
        case .skipped:
            withAnimation(.easeOut(duration: 0.2)) { position = max(0, position - 1) }
        case let .removed(card):
            card.deletedAt = nil
            card.touch()
            try? context.save()
            handled.remove(card.id)
            withAnimation(.easeOut(duration: 0.2)) { position = max(0, position - 1) }
        }
        present()
    }

    /// Moves a topic's chip to the end (so it is one of the four on show)
    /// and changes its count; a chip at zero goes.
    private func tally(_ topic: String, by delta: Int) {
        var entry = Tally(id: topic, count: 0)
        if let index = tallies.firstIndex(where: { $0.id == topic }) {
            entry = tallies.remove(at: index)
        }
        entry.count += delta
        if entry.count > 0 { tallies.append(entry) }
    }

    /// A pick from the full topic list counts as filing.
    private func filePick() {
        guard let topic = pickedTopic, let model, model.filed == nil else { return }
        model.file(model.candidate(topicID: topic, subcategory: pickedSub))
    }

    // MARK: Late answers

    private func prefetch() {
        let read = cards[position..<min(position + Self.readLookahead, cards.count)]
        for card in read { readThumbnail(card) }
        let ask = cards[position..<min(position + Self.modelLookahead, cards.count)]
        askModel(Array(ask))
    }

    private func readThumbnail(_ card: Bookmark) {
        guard let url = card.imageURL, !ThumbnailText.hasRead(card.id, accurate: true) else { return }
        let id = card.id
        Task { @MainActor in
            guard await ThumbnailText.read(id, imageURL: url, accurate: true) != nil else { return }
            reoffer(id)
        }
    }

    private func askModel(_ window: [Bookmark]) {
        guard let account, account.isSignedIn else { return }
        for card in window where asked[card.id] == nil {
            guard asked.count < Self.modelBudget else { return }
            let input = QuickFileBridge.input(for: card, ocr: ThumbnailText.cached(card.id))
            guard ranking(for: card, input: input).evidence == .none, let url = card.url else { continue }
            let id = card.id
            asked[id] = card.updatedAt
            let request = SmartCategorizer.Context(url: url, title: card.title, author: card.author, text: card.text)
            Task { @MainActor in
                guard let session = await account.currentSession(),
                      let answer = await SmartCategorizer.suggest(request, session: session) else { return }
                answers[id] = answer
                reoffer(id)
            }
        }
    }

    /// A late answer for the card in front reaches its dial through `offer`:
    /// an untouched dial re-deals, a touched one only gains a ✨ or a chip.
    private func reoffer(_ id: String) {
        guard let card = current, card.id == id, let model else { return }
        let input = QuickFileBridge.input(for: card, ocr: ThumbnailText.cached(id))
        model.offer(ranking(for: card, input: input), input: input)
    }

    /// On the way out: the model's answers for cards left unsorted become the
    /// app's guess, if the bork is still the machine's to file and hasn't
    /// changed since it was asked. Then the Share Extension's snapshot learns
    /// this session.
    private func finish() {
        for (id, answer) in answers where !handled.contains(id) {
            guard let card = cards.first(where: { $0.id == id }), card.deletedAt == nil,
                  EnrichmentPolicy.mayFile(source: card.filingSource), card.updatedAt == asked[id],
                  let topic = answer.categoryID else { continue }
            card.categoryID = topic
            card.subcategory = answer.subcategory
            card.touch()
        }
        try? context.save()
        QuickFileBridge.scheduleSnapshot(context: context)
    }
}

// MARK: - Decks

extension TriageSheet {
    /// No valid topic: never filed, or filed under a topic that no longer
    /// exists. In the order given (the library's, newest first).
    @MainActor
    static func unfiled(_ library: [Bookmark]) -> [Bookmark] {
        library.filter { $0.deletedAt == nil && !$0.isWaiting && Taxonomy.category(id: $0.categoryID) == nil }
    }

    /// The app's guesses from the last 30 days that today's ranking, guess
    /// pinned first, still calls less than sure.
    @MainActor
    static func guesses(_ library: [Bookmark], memory: FilingMemory, order: [String], now: Date = .now) -> [Bookmark] {
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        return library.filter { bookmark in
            guard bookmark.deletedAt == nil, !bookmark.isWaiting, bookmark.filingSource == "automatic",
                  bookmark.savedAt >= cutoff, let pin = QuickFileBridge.pin(for: bookmark) else { return false }
            let input = QuickFileBridge.input(for: bookmark, ocr: ThumbnailText.cached(bookmark.id))
            return FilingSuggest.rank(input, memory: memory, pinned: pin, taxonomyOrder: order, now: now).evidence != .strong
        }
    }

    /// The deck worth opening for a nudge (the inbox toast's "Sort"), if any.
    @MainActor
    static func deckWorthSorting(_ library: [Bookmark], customIDs: [String]) -> Deck? {
        if !unfiled(library).isEmpty { return .unfiled }
        let order = QuickFileBridge.taxonomyOrder(customIDs: customIDs)
        return guesses(library, memory: QuickFileBridge.memory(library), order: order).isEmpty ? nil : .guesses
    }
}

// MARK: - The card

/// One save, at hero size: its cover with the title over a scrim, or, with no
/// picture, a poster in its topic's tint (paper when it has no topic yet).
private struct TriageCard: View {
    let bookmark: Bookmark
    let width: CGFloat
    let height: CGFloat

    private var palette: CategoryPalette? { bookmark.category?.palette }
    private var hasPicture: Bool { bookmark.imageURL != nil }
    private var radius: CGFloat { 22 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if hasPicture { picture } else { poster }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            PlatformBadge(platform: bookmark.platform, size: 24, pageURL: bookmark.url)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                .padding(11)
        }
        .overlay(alignment: .topTrailing) { playChip }
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Tokens.surface)
                .shadow(color: Tokens.ink.opacity(0.04), radius: 2, y: 1)
                .shadow(color: Tokens.ink.opacity(0.12), radius: 18, y: 12)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var picture: some View {
        CoverImage(url: bookmark.imageURL, palette: palette ?? NeutralPalette.value)
            .overlay {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.38),
                    .init(color: Tokens.ink.opacity(0.82), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                caption
                    .foregroundStyle(.white)
                    .padding(13)
            }
    }

    private var poster: some View {
        let ink = palette?.deep ?? Tokens.ink
        return ZStack(alignment: .topLeading) {
            if let palette {
                LinearGradient(colors: [palette.tint, palette.tint.opacity(0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                LinearGradient(colors: [Tokens.surface, Tokens.paper],
                               startPoint: .top, endPoint: .bottom)
            }
            RadialGradient(colors: [.white.opacity(0.55), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: height)
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 40)
                if bookmark.isTextPost, let body = bookmark.text, !body.isEmpty {
                    Text(body)
                        .font(Typo.ui(14.5, .medium))
                        .foregroundStyle(Tokens.bodyOnWhite)
                        .lineLimit(7)
                } else {
                    Text(bookmark.displayTitle)
                        .font(Typo.display(19, .bold))
                        .foregroundStyle(ink)
                        .lineLimit(5)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    if let creator = bookmark.displayAuthor {
                        Text(creator)
                            .font(Typo.ui(12, .semibold))
                            .foregroundStyle(Tokens.inkSecondary)
                            .lineLimit(1)
                    }
                    Text(RelativeDate.cardLine(saved: bookmark.savedAt, posted: bookmark.postedAt))
                        .font(Typo.ui(11, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
            }
            .padding(14)
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let creator = bookmark.displayAuthor {
                Text(creator)
                    .font(Typo.ui(12, .semibold))
                    .opacity(0.88)
                    .lineLimit(1)
            }
            Text(bookmark.displayTitle)
                .font(Typo.display(16, .bold))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Text(RelativeDate.cardLine(saved: bookmark.savedAt, posted: bookmark.postedAt))
                .font(Typo.ui(11, .medium))
                .opacity(0.75)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
    }

    @ViewBuilder
    private var playChip: some View {
        if bookmark.isPlayable || bookmark.durationLabel != nil {
            HStack(spacing: 3) {
                Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                if let duration = bookmark.durationLabel {
                    Text(duration).font(Typo.ui(10.5, .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .padding(12)
        }
    }

    private var accessibilityText: String {
        var parts = [bookmark.displayTitle]
        if let creator = bookmark.displayAuthor { parts.append("by \(creator)") }
        parts.append(bookmark.platform.name)
        parts.append(RelativeDate.label(for: bookmark.savedAt))
        return parts.joined(separator: ", ")
    }
}
