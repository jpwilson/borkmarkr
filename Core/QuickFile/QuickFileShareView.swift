import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// What the Share Extension shows once the save is written: "Saved to
/// bookmarker ✓", the post, and the dial asking where it goes.
///
/// The save has already happened (tap 1), so nothing here can lose it. The
/// dial's centre sits a little below the middle, where a thumb rests; one more
/// tap chooses. The sheet then stays: the refine panel takes the footer's
/// place (subtopics, tags), the ring stays live for another topic, and Done
/// closes. Done drains over six seconds of no touching after the first
/// choice; any touch after it stops that for good, and the minute's cap
/// still closes an idle sheet. There is no Undo here any more: the choice is
/// the person's own, and the dial changes it. Before a choice, "Not now" keeps the guess. It drains over six seconds of no
/// touching, then closes, unless the model is still answering about a guess
/// that isn't sure yet, which it waits for until nine seconds after it
/// appeared (a sure guess is asked about too, but not waited for), or the
/// centre has just changed by itself, which then stays up for a second and
/// a half. Any touch anywhere
/// stops the drain for good; a minute without a touch closes the sheet
/// anyway. Under VoiceOver or Switch Control nothing is timed at all,
/// including after a choice, which then waits for Done.
///
/// More… swaps the dial for `QuickFileMoreList` in place. The view takes over
/// `model.onMore` for that; the host keeps `onConfirm`.
struct QuickFileShareView: View {
    let title: String
    let platformName: String
    let model: QuickFileModel
    let tags: QuickFileTags
    var refineSource: QuickFileRefineSource
    var style: QuickFileStyle
    var idleSeconds: Double
    var topics: [Topic]
    var subs: (Topic) -> [String]
    let onNotNow: () -> Void
    var onDone: (FilingCandidate) -> Void

    /// The height under the dial, the same before and after a choice, so
    /// the dial never moves or resizes as the refine panel arrives.
    static let belowDial: CGFloat = 128
    /// No touch for this long and the sheet closes, keeping the guess.
    static let hardCap: TimeInterval = 60
    /// Past the drain, an untouched sheet whose guess isn't sure yet waits
    /// for the model until this long after it appeared: the page's 2.5 s and
    /// the model's 6.5 s (`QuickFileShareSession.enrich`).
    static let answerWait: TimeInterval = 9
    /// A centre that changed by itself is up at least this long before the
    /// drain closes the sheet.
    static let redealHold: TimeInterval = 1.5

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingMore = false
    @State private var draining = false
    @State private var drainLeft: CGFloat = 1
    @State private var started = false
    @State private var closed = false
    @State private var clock = QuickFileIdleClock()
    @State private var drain = QuickFileDrain()
    @State private var editingTag = false

    init(title: String, platformName: String, model: QuickFileModel, tags: QuickFileTags,
         refineSource: QuickFileRefineSource = .none, style: QuickFileStyle = .system,
         idleSeconds: Double = 6, topics: [Topic] = Taxonomy.all, subs: @escaping (Topic) -> [String] = { $0.subs },
         onNotNow: @escaping () -> Void, onDone: @escaping (FilingCandidate) -> Void = { _ in }) {
        self.title = title
        self.platformName = platformName
        self.model = model
        self.tags = tags
        self.refineSource = refineSource
        self.style = style
        self.idleSeconds = idleSeconds
        self.topics = topics
        self.subs = subs
        self.onNotNow = onNotNow
        self.onDone = onDone
    }

    /// Live, for the timers; the environment values drive what is drawn.
    private static var assistiveTechRunning: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                QuickFileStyle.paper.ignoresSafeArea()
                if showingMore {
                    QuickFileMoreList(topics: topics, subs: subs, style: style,
                                      onPick: { pick($0, $1) }, onCancel: { hideMore() })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    main(geometry.size)
                        .transition(.opacity)
                }
            }
        }
        .background(QuickFileTouchWatcher { interacted() })
        .environment(\.colorScheme, .light)
        .onAppear { start() }
        .onChange(of: model.confirmations) { _, _ in chose() }
        // Typing doesn't reach the window's watcher.
        .onChange(of: tags.draft) { _, _ in interacted() }
        .task { await runClock() }
        .task(id: drain.startedAt) { await runDrain() }
    }

    // MARK: Layout

    /// As big as the sheet allows: 320 pt on most phones, smaller only when
    /// the sheet is short, never so small a key is hard to hit.
    /// The same in every state, so the dial never resizes under a thumb.
    static func diameter(for size: CGSize) -> CGFloat {
        max(232, min(320, size.width - 64, size.height - 404))
    }

    @ViewBuilder
    private func main(_ size: CGSize) -> some View {
        if typeSize.isAccessibilitySize {
            // The ranked list has no drag, so the whole sheet can scroll.
            ScrollView {
                layout(size, fixed: false)
            }
        } else {
            layout(size, fixed: true)
                .frame(width: size.width, height: size.height)
        }
    }

    private func layout(_ size: CGSize, fixed: Bool) -> some View {
        VStack(spacing: 0) {
            savedPill
                .padding(.top, 14)
            if editingTag {
                // The keyboard is up: the dial gives way to one line saying
                // where it went, and the panel rides above the keys.
                chosenSummary
                    .padding(.top, 14)
                Spacer(minLength: 10)
            } else {
                Spacer(minLength: 8)
                    .frame(maxHeight: 26)
                titleBlock
                Spacer(minLength: 10)
                QuickFileHeader(model: model, style: style)
                    .padding(.bottom, 12)
                QuickFileDial(model: model, style: style, diameter: Self.diameter(for: size),
                              onLater: { notNow() }, onDone: { finishChosen() })
            }
            Group {
                if model.isChosen {
                    QuickFileRefinePanel(model: model, tags: tags, source: refineSource, style: style,
                                         onEditingTag: { editing in
                                             withAnimation(.easeOut(duration: 0.2)) { editingTag = editing }
                                         })
                        .transition(.opacity)
                } else {
                    QuickFileDialFooter(model: model, style: style)
                }
            }
            .frame(height: fixed ? Self.belowDial : nil, alignment: .top)
            .padding(.top, 14)
            .animation(.easeOut(duration: 0.18), value: model.isChosen)
            if fixed {
                Spacer(minLength: 10)
                    .frame(maxHeight: 36)
            }
            bottomBar
                .padding(.top, fixed ? 0 : 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    /// While typing a tag: the topic's picture and where it went.
    @ViewBuilder
    private var chosenSummary: some View {
        if let filed = model.filed {
            HStack(spacing: 10) {
                QuickFileArtDisc(topicID: filed.categoryID, size: 32, style: style)
                Text(title)
                    .font(style.ui(15, .semibold))
                    .foregroundStyle(QuickFileStyle.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var savedPill: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(QuickFileStyle.toastCheck)
            Text(QuickFileCopy.saved)
                .font(style.ui(14, .semibold))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(QuickFileStyle.ink, in: Capsule())
        .shadow(color: QuickFileStyle.ink.opacity(0.18), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(style.ui(17, .semibold))
                .foregroundStyle(QuickFileStyle.ink)
                .lineLimit(2)
            Text(platformName)
                .font(style.ui(13, .medium))
                .foregroundStyle(QuickFileStyle.inkSecondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if model.isChosen {
            QuickFileDoneButton(draining: drain.isDraining, style: style) { finishChosen() }
                .transition(.opacity)
        } else {
            Button { notNow() } label: {
                ZStack {
                    Color.white
                    GeometryReader { bar in
                        Rectangle()
                            .fill(style.accent.opacity(0.18))
                            .frame(width: bar.size.width * drainLeft)
                    }
                    .opacity(draining ? 1 : 0)
                    Text(QuickFileCopy.notNow)
                        .font(style.ui(16, .semibold))
                        .foregroundStyle(QuickFileStyle.ink)
                }
                .frame(height: 54)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(QuickFileStyle.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(QuickFilePressStyle())
            .accessibilityHint(QuickFileCopy.notNowHint)
            .transition(.opacity)
        }
    }

    // MARK: Flow

    private func start() {
        guard !started else { return }
        started = true
        model.onMore = { showMore() }
        clock.last = .now
        guard !Self.assistiveTechRunning, model.filed == nil else { return }
        draining = true
        withAnimation(.linear(duration: idleSeconds)) { drainLeft = 0 }
    }

    /// Any touch, anywhere: the drain stops for good and the idle clock
    /// restarts. After a choice, Done's drain stops for good too.
    private func interacted() {
        clock.last = .now
        drain.touched()
        guard draining else { return }
        withAnimation(.easeOut(duration: 0.2)) { draining = false }
    }

    private func runClock() async {
        let appeared = Date()
        try? await Task.sleep(for: .seconds(idleSeconds))
        guard !Task.isCancelled else { return }
        while draining, holdsOpen(since: appeared), !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }
        if draining, !Self.assistiveTechRunning, !showingMore, model.filed == nil { return notNow() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            // Busy in the list, or using assistive tech: not idle.
            if Self.assistiveTechRunning || showingMore {
                clock.last = .now
                continue
            }
            if Date().timeIntervalSince(clock.last) >= Self.hardCap { return notNow() }
        }
    }

    /// Past the drain, the sheet stays while it `waitsForAnswer` (until
    /// `answerWait` after it appeared) and while a centre that changed by
    /// itself is newer than `redealHold`.
    private func holdsOpen(since appeared: Date) -> Bool {
        let now = Date()
        if Self.waitsForAnswer(model), now.timeIntervalSince(appeared) < Self.answerWait { return true }
        if let moved = model.movedAt, now.timeIntervalSince(moved) < Self.redealHold { return true }
        return false
    }

    /// The model is still answering about a guess that isn't sure yet. A
    /// sure guess is asked about too, but the sheet closes at its usual time:
    /// an answer that lands before then is kept, and one that doesn't is left
    /// for `PreviewFetcher`. Only an untouched sheet waits, and its dial
    /// always shows the latest ranking.
    static func waitsForAnswer(_ model: QuickFileModel) -> Bool {
        model.isAsking && model.ranking.evidence != .strong
    }

    private func notNow() {
        guard !closed else { return }
        closed = true
        onNotNow()
    }

    /// A topic was chosen: "Not now" has had its say, and Done drains from
    /// the first choice (`QuickFileDrain`).
    private func chose() {
        guard model.isChosen else { return }
        if draining { draining = false }
        drain.chose(at: .now, assistive: Self.assistiveTechRunning)
    }

    private func runDrain() async {
        guard drain.isDraining else { return }
        try? await Task.sleep(for: .seconds(QuickFileDrain.seconds))
        guard !Task.isCancelled, drain.isDue(at: .now) else { return }
        finishChosen()
    }

    /// Done, its drain, or VoiceOver's Done.
    private func finishChosen() {
        guard !closed, let filed = model.filed else { return }
        closed = true
        onDone(filed)
    }

    private func showMore() {
        interacted()
        withAnimation(.easeOut(duration: 0.22)) { showingMore = true }
    }

    private func hideMore() {
        clock.last = .now
        withAnimation(.easeOut(duration: 0.2)) { showingMore = false }
    }

    private func pick(_ topicID: String, _ subcategory: String?) {
        let candidate = model.candidate(topicID: topicID, subcategory: subcategory)
        withAnimation(.easeOut(duration: 0.2)) { showingMore = false }
        model.file(candidate)
    }
}

extension QuickFileShareView {
    /// The extension's screen for a share session.
    init(session: QuickFileShareSession, style: QuickFileStyle = .system,
         onNotNow: @escaping () -> Void, onDone: @escaping (FilingCandidate) -> Void = { _ in }) {
        self.init(title: session.title, platformName: session.platformName, model: session.model,
                  tags: session.tags, refineSource: session.refineSource, style: style,
                  topics: session.topics, subs: { session.subs(for: $0) }, onNotNow: onNotNow, onDone: onDone)
    }
}
