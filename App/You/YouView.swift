import SwiftUI
import SwiftData

/// Stats plus the tweak knobs the prototype exposed — accent colour, feed
/// density, starting tab — and the share-sheet explainer, which is the single
/// most important thing a new user needs to be told.
struct YouView: View {
    @Environment(\.brandAccent) private var accent

    @AppStorage("accentHex") private var accentHex = Theme.defaultAccentHex
    @AppStorage("compactFeed") private var compact = false
    @AppStorage("startingTab") private var startingTab = RootView.Tab.feed.rawValue

    @Query private var all: [Bookmark]

    private var active: [Bookmark] { all.filter { !$0.isArchived } }

    private var topCategories: [(Category, Int)] {
        let counts = Dictionary(grouping: active.compactMap(\.categoryID)) { $0 }
            .mapValues(\.count)
        return Taxonomy.all
            .compactMap { category in
                counts[category.id].map { (category, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stats
                    shareSheetExplainer
                    if !topCategories.isEmpty { topCategoriesCard }
                    appearance
                }
                .padding(16)
                .padding(.bottom, 120)
            }
            .background(Theme.background)
            .navigationTitle("You")
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            statTile(value: "\(active.count)", label: "saved")
            statTile(value: "\(Set(active.compactMap(\.categoryID)).count)", label: "categories")
            statTile(value: "\(Set(active.map(\.platform)).count)", label: "sources")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card(radius: 18)
    }

    /// The app is only as good as how easily things get INTO it. Most people
    /// won't discover the share sheet on their own, so we spell it out.
    private var shareSheetExplainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Save from anywhere", systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text("In Instagram, X, TikTok, YouTube or Safari — tap **Share**, then pick **borkmarkr**. The link lands in your feed straight away, and you can categorise it later.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)

            Text("First time: tap **More** in the share sheet and turn borkmarkr on.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }

    private var topCategoriesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your saves live")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            ForEach(topCategories, id: \.0.id) { category, count in
                HStack(spacing: 10) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color(hex: category.tintHex), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(category.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18)
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                ForEach(Theme.accents, id: \.hex) { option in
                    Button {
                        accentHex = option.hex
                    } label: {
                        Circle()
                            .fill(Color(hex: option.hex))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().stroke(Theme.ink.opacity(accentHex == option.hex ? 0.85 : 0), lineWidth: 2)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                }
                Spacer()
            }

            Toggle("Compact feed", isOn: $compact)
                .font(.system(size: 14, weight: .medium, design: .rounded))

            Picker("Open on", selection: $startingTab) {
                ForEach(RootView.Tab.allCases, id: \.rawValue) { tab in
                    Text(tab.title).tag(tab.rawValue)
                }
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18)
    }
}
