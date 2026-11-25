import SwiftUI

/// Four steps: value prop → share-sheet demo → "it sorts itself" → make it
/// yours. Skippable throughout; the accent and interests picked here persist.
struct OnboardingView: View {
    @Binding var accentKey: String
    let onFinish: ([String]) -> Void

    @State private var step = 0
    @State private var interests: Set<String> = []

    private var accent: AccentRamp { AccentRamp.named(accentKey) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                progressDots
                Spacer()
                if step < 3 {
                    Button("Skip") { onFinish(Array(interests)) }
                        .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(minWidth: Tokens.minTapTarget, minHeight: Tokens.minTapTarget)
                        .contentShape(Rectangle())
                }
            }
            .frame(minHeight: Tokens.minTapTarget)
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 8)

            TabView(selection: $step) {
                valueProp.tag(0)
                shareDemo.tag(1)
                sortsItself.tag(2)
                makeItYours.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(Tokens.paper.ignoresSafeArea())
        // The shared buttons and chips read the accent from the environment;
        // the tour is shown before RootView sets it, and changes it on page 4.
        .environment(\.accent, accent)
        .onAppear {
            #if DEBUG
            // `-onboardingPage 2` opens on the second page (pages count from 1).
            if let page = ScreenshotDefaults.onboardingPage { step = min(max(page - 1, 0), 3) }
            #endif
        }
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index == step ? accent.base : Tokens.grabber)
                    .frame(width: index == step ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: step)
            }
        }
    }

    // MARK: Steps

    private var valueProp: some View {
        VStack(spacing: 24) {
            Spacer()
            ClayArtImage(source: .asset("brandMark"))
                .frame(width: 148, height: 148)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            headline("Everything you save,\nfinally in one place.",
                     "Reels, threads, clips, articles — one library you can actually search.")

            // One row, always: the marks shrink to fit rather than wrap
            // (1.3 left two of them alone on a second line).
            ViewThatFits(in: .horizontal) {
                platformRow(size: 34, spacing: 8)
                platformRow(size: 30, spacing: 6)
                platformRow(size: 26, spacing: 5)
            }
            .padding(.horizontal, Tokens.gutter)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Works with " + Platform.ordered.map(\.name).joined(separator: ", "))

            Spacer()
        }
    }

    private func platformRow(size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Platform.ordered, id: \.self) { platform in
                PlatformBadge(platform: platform, size: size)
            }
        }
        .fixedSize()
    }

    /// Every page's title (Bricolage, the screen size) and its one sentence.
    private func headline(_ title: String, _ body: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .textRole(.screenTitle, color: Tokens.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .textRole(.body, color: Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
        }
        .padding(.horizontal, Tokens.gutter)
    }

    private var shareDemo: some View {
        VStack(spacing: 20) {
            Spacer()
            ClayArtImage(source: .asset("welcomeHero"))
                .frame(width: 168, height: 168)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            headline("Save it without\nleaving the app.",
                     "Tap Share in Instagram, X, TikTok or anywhere else — then pick bookmarker.")

            // The share sheet as it looks once bookmarker is pinned first,
            // and the way to get it there — the same guide as the You tab.
            ShareSheetMock(accent: accent)
                .padding(.horizontal, 28)
            ShareGuideLink(accent: accent)
            Spacer()
        }
    }

    private var sortsItself: some View {
        VStack(spacing: 24) {
            Spacer()
            headline("It sorts itself.",
                     "Every save gets a topic and the app it came from — so you can find it by either.")

            // A save as the Library shows it, filed: the topic's clay art as
            // the cover, its chip, its tags. Real palette, not a stand-in.
            sortedExample
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var sortedExample: some View {
        let fitness = Taxonomy.category(id: "fitness")?.palette ?? NeutralPalette.value
        return VStack(alignment: .leading, spacing: 0) {
            ClayCover(topicID: "fitness")
                .frame(height: 150)
                .overlay(alignment: .topLeading) {
                    PlatformBadge(platform: .tiktok, size: 26).padding(10)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text("5-minute hip mobility flow")
                    .textRole(.cardTitle, color: Tokens.ink)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                    Text("Sorted for you")
                }
                .textRole(.meta, color: accent.deep)
                FlowLayout(spacing: 6) {
                    TopicChip("Fitness › Mobility", palette: fitness, isOn: false, size: .filter) {}
                    TagChip("hips", isOn: false, size: .filter) {}
                    TagChip("back", isOn: false, size: .filter) {}
                }
                .allowsHitTesting(false)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: a TikTok save, sorted into Fitness, Mobility, tagged hips and back")
    }

    private var makeItYours: some View {
        ScrollView {
            VStack(spacing: 18) {
                headline("Make it yours.", "Pick a colour, then what you're into.")
                    .padding(.top, 28)

                HStack(spacing: 18) {
                    ForEach(AccentRamp.all, id: \.key) { ramp in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                accentKey = ramp.key
                            }
                        } label: {
                            Circle()
                                .fill(ramp.base)
                                .frame(width: 40, height: 40)
                                .scaleEffect(accentKey == ramp.key ? 1.08 : 1)
                                .overlay(
                                    Circle()
                                        .stroke(Tokens.paper, lineWidth: 3)
                                        .overlay(Circle().stroke(ramp.base, lineWidth: 3).padding(-3))
                                        .opacity(accentKey == ramp.key ? 1 : 0)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ramp.name)
                    }
                }

                FlowLayout(spacing: Tokens.chipGap) {
                    ForEach(Taxonomy.onboardingInterests, id: \.self) { id in
                        if let topic = Taxonomy.category(id: id) {
                            let active = interests.contains(id)
                            TopicChip(topic.name, palette: topic.palette, isOn: active) {
                                if active { interests.remove(id) } else { interests.insert(id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
    }

    private var footer: some View {
        Button {
            if step < 3 {
                withAnimation(.easeOut(duration: 0.22)) { step += 1 }
            } else {
                onFinish(Array(interests))
            }
        } label: {
            Text(step < 3 ? "Continue" : "Get started")
        }
        .buttonStyle(.clayPrimary)
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, 16)
    }
}
