import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// What the Share Extension shows once the save is written: "Saved to
/// bookmarker ✓", the post, and the dial asking where it goes.
///
/// The save has already happened (tap 1), so nothing here can lose it. The
/// dial's centre sits a little below the middle, where a thumb rests; one more
/// tap files it. "Not now" keeps the guess. It drains over six seconds of no
/// touching; any touch anywhere stops the drain for good; a minute without a
/// touch closes the sheet anyway. Under VoiceOver or Switch Control nothing is
/// timed at all, including the moment after filing, which then waits for
/// Undo or Done.
///
/// More… swaps the dial for `QuickFileMoreList` in place. The view takes over
/// `model.onMore` for that; the host keeps `onConfirm` and `onUndo`.
struct QuickFileShareView: View {
    let title: String
    let platformName: String
    let model: QuickFileModel
    var style: QuickFileStyle
    var idleSeconds: Double
    var topics: [Topic]
    var subs: (Topic) -> [String]
    let onNotNow: () -> Void
    var onDone: (FilingCandidate) -> Void

    /// How long "Filed to …" and its Undo stay before the sheet closes.
    static let filedHold: Duration = .milliseconds(900)
    /// No touch for this long and the sheet closes, keeping the guess.
    static let hardCap: TimeInterval = 60

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var showingMore = false
    @State private var draining = false
    @State private var drainLeft: CGFloat = 1
    @State private var started = false
    @State private var closed = false
    @State private var clock = QuickFileIdleClock()

    init(title: String, platformName: String, model: QuickFileModel, style: QuickFileStyle = .system,
         idleSeconds: Double = 6, topics: [Topic] = Taxonomy.all, subs: @escaping (Topic) -> [String] = { $0.subs },
         onNotNow: @escaping () -> Void, onDone: @escaping (FilingCandidate) -> Void = { _ in }) {
        self.title = title
        self.platformName = platformName
        self.model = model
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
        .onChange(of: model.filed) { _, filed in landed(filed) }
        .task { await runClock() }
    }

    // MARK: Layout

    /// As big as the sheet allows: 320 pt on most phones, smaller only when
    /// the sheet is short, never so small a key is hard to hit.
    static func diameter(for size: CGSize) -> CGFloat {
        max(232, min(320, size.width - 64, size.height - 344))
    }

    private func main(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            savedPill
                .padding(.top, 14)
            Spacer(minLength: 8)
                .frame(maxHeight: 26)
            titleBlock
            Spacer(minLength: 10)
            QuickFileHeader(model: model, style: style)
                .padding(.bottom, 12)
            QuickFileDial(model: model, style: style, diameter: Self.diameter(for: size), onLater: { notNow() })
            Group {
                if let filed = model.filed {
                    filedLine(filed)
                } else {
                    QuickFileDialFooter(model: model, style: style)
                }
            }
            .frame(minHeight: 66, alignment: .top)
            .padding(.top, 14)
            .animation(.easeOut(duration: 0.18), value: model.filed)
            Spacer(minLength: 10)
                .frame(maxHeight: 36)
            bottomBar
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .frame(width: size.width, height: size.height)
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

    private func filedLine(_ filed: FilingCandidate) -> some View {
        Text(QuickFileCopy.filed(filed))
            .font(style.ui(17, .semibold))
            .foregroundStyle(QuickFileStyle.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .transition(.opacity)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let filed = model.filed {
            HStack(spacing: 10) {
                Button { model.undo() } label: {
                    capsule(fill: Color.white, stroke: QuickFileStyle.hairline) {
                        Label(QuickFileCopy.undo, systemImage: "arrow.uturn.backward")
                            .font(style.ui(16, .semibold))
                            .foregroundStyle(style.accentDeep)
                    }
                }
                .buttonStyle(QuickFilePressStyle())
                if voiceOver || switchControl {
                    Button { finishFiled(filed) } label: {
                        capsule(fill: QuickFileStyle.ink, stroke: QuickFileStyle.ink) {
                            Text(QuickFileCopy.done)
                                .font(style.ui(16, .semibold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .buttonStyle(QuickFilePressStyle())
                }
            }
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

    private func capsule<Content: View>(fill: Color, stroke: Color, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
            .contentShape(Capsule())
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

    /// Any touch, anywhere: the drain stops for good and the idle clock restarts.
    private func interacted() {
        clock.last = .now
        guard draining else { return }
        withAnimation(.easeOut(duration: 0.2)) { draining = false }
    }

    private func runClock() async {
        try? await Task.sleep(for: .seconds(idleSeconds))
        guard !Task.isCancelled else { return }
        if draining, !Self.assistiveTechRunning, !showingMore, model.filed == nil { return notNow() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            // Busy in the list, already filed, or using assistive tech: not idle.
            if Self.assistiveTechRunning || showingMore || model.filed != nil {
                clock.last = .now
                continue
            }
            if Date().timeIntervalSince(clock.last) >= Self.hardCap { return notNow() }
        }
    }

    private func notNow() {
        guard !closed else { return }
        closed = true
        onNotNow()
    }

    private func landed(_ filed: FilingCandidate?) {
        guard let filed else { return }
        if draining { draining = false }
        UIAccessibility.post(notification: .announcement, argument: QuickFileCopy.filed(filed))
        guard !Self.assistiveTechRunning else { return }
        Task {
            try? await Task.sleep(for: Self.filedHold)
            guard model.filed == filed else { return }
            finishFiled(filed)
        }
    }

    private func finishFiled(_ filed: FilingCandidate) {
        guard !closed else { return }
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
        self.init(title: session.title, platformName: session.platformName, model: session.model, style: style,
                  topics: session.topics, subs: { session.subs(for: $0) }, onNotNow: onNotNow, onDone: onDone)
    }
}

/// When someone last touched the screen. A reference, so noting a touch
/// doesn't redraw anything.
@MainActor
final class QuickFileIdleClock {
    var last = Date()
}

/// Notices every touch on screen without taking part in any of them: a
/// recogniser on the window that reports touch-down and fails at once, so it
/// never delays, cancels or competes with the dial, the buttons or the list.
private struct QuickFileTouchWatcher: UIViewRepresentable {
    let onTouch: () -> Void

    func makeUIView(context: Context) -> Watcher { Watcher(onTouch: onTouch) }

    func updateUIView(_ view: Watcher, context: Context) { view.onTouch = onTouch }

    final class Watcher: UIView {
        var onTouch: () -> Void
        private var recognizer: QuickFileTouchDown?

        init(onTouch: @escaping () -> Void) {
            self.onTouch = onTouch
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
                self.recognizer = nil
            }
            guard let window else { return }
            let recognizer = QuickFileTouchDown { [weak self] in self?.onTouch() }
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
        }
    }
}

private final class QuickFileTouchDown: UIGestureRecognizer {
    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }
}
