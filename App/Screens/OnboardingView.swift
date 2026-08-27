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
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(Tokens.inkMeta)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)

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
        VStack(spacing: 22) {
            Spacer()
            ClayArt(name: "brandMark")
                .frame(width: 148, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            VStack(spacing: 10) {
                Text("Everything you save,\nfinally in one place.")
                    .font(Typo.display(29, .heavy))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.ink)
                Text("Reels, threads, clips, articles — one library you can actually search.")
                    .font(Typo.ui(14.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.horizontal, 34)
            }

            FlowLayout(spacing: 8) {
                ForEach(Platform.ordered, id: \.self) { platform in
                    PlatformBadge(platform: platform, size: 34)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var shareDemo: some View {
        VStack(spacing: 20) {
            Spacer()
            ClayArt(name: "welcomeHero")
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(spacing: 10) {
                Text("Save it without\nleaving the app.")
                    .font(Typo.display(29, .heavy))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.ink)
                Text("Tap Share in Instagram, X, TikTok or anywhere else — then pick bookmarker.")
                    .font(Typo.ui(14.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.horizontal, 34)
            }

            HStack(spacing: 16) {
                ForEach(0..<3) { index in
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(index == 1 ? accent.base : Tokens.mutedControl)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Group {
                                if index == 1 {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 20, weight: .black))
                                        .foregroundStyle(.white)
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(accent.base, lineWidth: index == 1 ? 3 : 0)
                                .padding(-5)
                        )
                }
            }
            Spacer()
        }
    }

    private var sortsItself: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 10) {
                Text("It sorts itself.")
                    .font(Typo.display(31, .heavy))
                    .tracking(-0.6)
                    .foregroundStyle(Tokens.ink)
                Text("Every save gets a topic and the app it came from — so you can find it by either.")
                    .font(Typo.ui(14.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.inkSecondary)
                    .padding(.horizontal, 34)
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                    Text("Sorted for you").font(Typo.ui(13, .bold))
                    Spacer()
                }
                .foregroundStyle(accent.deep)

                Text("Fitness › Mobility")
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(Color(hue: 152/360, saturation: 0.46, brightness: 0.42))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hue: 152/360, saturation: 0.55, brightness: 0.97), in: Capsule())

                HStack(spacing: 6) {
                    ForEach(["stretching", "back"], id: \.self) { tag in
                        Text("#\(tag)")
                            .font(Typo.ui(11.5, .semibold))
                            .foregroundStyle(accent.deep)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(accent.tint, in: Capsule())
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.tint.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 30)

            Spacer()
        }
    }

    private var makeItYours: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("Make it yours.")
                        .font(Typo.display(29, .heavy))
                        .tracking(-0.6)
                        .foregroundStyle(Tokens.ink)
                    Text("Pick a colour, then what you're into.")
                        .font(Typo.ui(14))
                        .foregroundStyle(Tokens.inkSecondary)
                }
                .padding(.top, 18)

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

                FlowLayout(spacing: 8) {
                    ForEach(Taxonomy.onboardingInterests, id: \.self) { id in
                        if let topic = Taxonomy.category(id: id) {
                            let active = interests.contains(id)
                            Button {
                                if active { interests.remove(id) } else { interests.insert(id) }
                            } label: {
                                Text(topic.name)
                                    .font(Typo.ui(13, .semibold))
                                    .foregroundStyle(active ? .white : topic.palette.deep)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(active ? topic.palette.deep : topic.palette.tint, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 24)
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
                .font(Typo.ui(15.5, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.base, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .shadow(color: accent.base.opacity(0.34), radius: 18, y: 9)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
    }
}
