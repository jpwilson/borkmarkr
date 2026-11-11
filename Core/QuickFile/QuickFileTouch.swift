import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// MARK: - Touches

/// When someone last touched the screen. A reference, so noting a touch
/// doesn't redraw anything.
@MainActor
final class QuickFileIdleClock {
    var last = Date()
}

/// Notices every touch on screen without taking part in any of them: a
/// recogniser on the window that reports touch-down and fails at once, so it
/// never delays, cancels or competes with the dial, the buttons or the list.
struct QuickFileTouchWatcher: UIViewRepresentable {
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

final class QuickFileTouchDown: UIGestureRecognizer {
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

// MARK: - The Done drain

/// When the refine panel's Done closes the sheet by itself.
///
/// The first choice starts a six-second drain. Any touch after it stops the
/// drain for good, a re-choice included: the window's watcher reports a
/// touch on its way down, before the tap that makes the first choice lands,
/// so that tap never counts against itself. Under VoiceOver or Switch
/// Control it never starts. Pure, so the rules are tested without a screen.
struct QuickFileDrain: Equatable {
    static let seconds: TimeInterval = 6

    private(set) var startedAt: Date?
    private(set) var stoppedForGood = false
    /// A topic has been chosen, so a touch now stops the drain for good.
    private(set) var hasChoice = false

    /// `alreadyChosen`: a save you had filed opens chosen, and never drains.
    init(alreadyChosen: Bool = false) {
        if alreadyChosen {
            hasChoice = true
            stoppedForGood = true
        }
    }

    var isDraining: Bool { startedAt != nil }

    /// A topic was chosen. Starts the drain the first time only.
    mutating func chose(at now: Date, assistive: Bool) {
        hasChoice = true
        guard !stoppedForGood, !assistive, startedAt == nil else { return }
        startedAt = now
    }

    /// A finger went down anywhere, or a key was typed.
    mutating func touched() {
        guard hasChoice, !stoppedForGood else { return }
        stoppedForGood = true
        startedAt = nil
    }

    func isDue(at now: Date) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) >= Self.seconds - 0.05
    }
}

/// The refine panel's Done: the one coral pill, full width, 58 pt, white
/// 17/600. While it drains, a lighter band shrinks across it, the "Not now"
/// drain in Done's colours.
struct QuickFileDoneButton: View {
    let draining: Bool
    var seconds: Double = QuickFileDrain.seconds
    var style: QuickFileStyle = .system
    let action: () -> Void

    @State private var left: CGFloat = 1
    @ScaledMetric(relativeTo: .body) private var font: CGFloat = 17

    /// B's coral shadow, rgba(200,80,40,.28).
    private static let glow = Color(.sRGB, red: 200 / 255, green: 80 / 255, blue: 40 / 255, opacity: 0.28)

    var body: some View {
        Button(action: action) {
            ZStack {
                style.accent
                GeometryReader { bar in
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: bar.size.width * left)
                }
                .opacity(draining ? 1 : 0)
                Text(QuickFileCopy.done)
                    .font(style.ui(min(font, 34), .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(height: max(58, min(font, 34) + 24))
            .clipShape(Capsule())
            .overlay(QuickFileTopEdge(base: Capsule(), depth: 1.5).fill(Color.white.opacity(0.4)))
            .shadow(color: Self.glow, radius: 10, y: 10)
            .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityHint(QuickFileCopy.doneHint)
        .onAppear { drain(draining) }
        .onChange(of: draining) { _, now in drain(now) }
    }

    private func drain(_ on: Bool) {
        guard on else {
            withAnimation(.easeOut(duration: 0.2)) { left = 1 }
            return
        }
        left = 1
        withAnimation(.linear(duration: seconds)) { left = 0 }
    }
}
