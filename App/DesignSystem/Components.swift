import SwiftUI

// The shared "Quiet clay" components (design/SYSTEM.md, "Components").
//
// Screen builders compose these rather than drawing their own chips, buttons
// and rows. Every component here:
//   - sizes its text with `TextRole`, so it scales with Dynamic Type;
//   - keeps a hit area of at least 44 × 44 pt, whatever its visual size;
//   - carries its own VoiceOver label and traits (selected chips say so).
// The save card, the row and `ClayCover` are in App/Components/Cards.swift.

// MARK: - Headers

/// A screen's title row: Bricolage 30/34, an optional meta line under it, and
/// an optional trailing view (the Library's avatar, a share button).
///
/// Use it for the top of every tab and full-screen page. Not for sheets — they
/// take `ClaySheetHeader`.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .textRole(.screenTitle, color: Tokens.ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).textRole(.meta)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// A section's title (Bricolage 19/24) with an optional quiet action at the
/// right ("See all", a sort `Menu` goes beside it via `trailing`).
///
/// Use it above every list or rail inside a screen.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var action: String? = nil
    var perform: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, action: String? = nil, perform: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.action = action
        self.perform = perform
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .textRole(.sectionTitle, color: Tokens.ink)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
            if let action, let perform {
                Button(action, action: perform)
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, action: String? = nil, perform: (() -> Void)? = nil) {
        self.init(title, action: action, perform: perform) { EmptyView() }
    }
}

/// A sheet's top (A's Quick File): an 18 pt band where the system grabber sits
/// (`.claySheet()` turns it on), then a 36 pt row with the title 17/22
/// semibold and an optional close button.
///
/// Use it as the first thing inside every sheet that has a title.
struct ClaySheetHeader: View {
    let title: String
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 18)
            HStack(spacing: 8) {
                Text(title)
                    .font(.custom("Instrument Sans", size: 17, relativeTo: .headline).weight(.semibold))
                    .foregroundStyle(Tokens.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Tokens.inkSecondary)
                            .frame(width: 30, height: 30)
                            .background(Tokens.mutedControl, in: Circle())
                            .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -7)
                    .accessibilityLabel("Close")
                }
            }
            .frame(minHeight: 36)
        }
    }
}

extension View {
    /// Presents this view as a clay sheet: paper, radius 28, the grabber on.
    /// Apply it to a sheet's root view.
    func claySheet() -> some View {
        self
            .presentationBackground(Tokens.paper)
            .presentationCornerRadius(Tokens.sheetRadius)
            .presentationDragIndicator(.visible)
    }
}

// MARK: - Chips

/// Visual heights of the three chip families. The hit area is always ≥ 44.
enum ChipSize: Sendable {
    /// Source and filter chips (Main.dc: 34).
    case filter
    /// Topic and subtopic chips in lists (SYSTEM.md: 36).
    case topic
    /// The refine panel's pills (B: 44).
    case refine

    var height: CGFloat {
        switch self {
        case .filter: 34
        case .topic: 36
        case .refine: 44
        }
    }

    var horizontalPadding: CGFloat { self == .refine ? 15 : 12 }
}

/// The shared chip body: a capsule at least `size.height` tall (it grows with
/// Dynamic Type), inside a ≥ 44 pt tappable frame.
private struct ChipBody<Label: View>: View {
    let size: ChipSize
    let fill: Color
    let stroke: Color?
    var dashed = false
    @ViewBuilder var label: () -> Label

    var body: some View {
        label()
            .lineLimit(1)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.height)
            .background(fill, in: Capsule())
            .overlay {
                if let stroke {
                    Capsule().strokeBorder(stroke, style: StrokeStyle(lineWidth: dashed ? 1.5 : 1, dash: dashed ? [4, 3] : []))
                }
            }
            .frame(minHeight: Tokens.minTapTarget)
            .contentShape(Rectangle())
    }
}

/// A filter chip: white with a hairline; on = ink fill, white text.
///
/// Use it for source filters, search scopes, sort and refine filters — any
/// chip that narrows what is shown. Not for topics (`TopicChip`) or tags
/// (`TagChip`).
struct FilterChip: View {
    let title: String
    let isOn: Bool
    var symbol: String? = nil
    var size: ChipSize = .filter
    let action: () -> Void

    init(_ title: String, isOn: Bool, symbol: String? = nil, size: ChipSize = .filter, action: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.symbol = symbol
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ChipBody(size: size, fill: isOn ? Tokens.ink : Tokens.surface, stroke: isOn ? Tokens.ink : Tokens.hairline) {
                HStack(spacing: 5) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    }
                    Text(title).textRole(.chip)
                }
                .foregroundStyle(isOn ? .white : Tokens.ink)
            }
        }
        .buttonStyle(ChipStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A topic or subtopic chip: the topic's tint with deep text; on = deep fill,
/// white text and a small check.
///
/// Use it wherever a chip names a topic or subtopic (topic page, picker,
/// refine panel, triage tallies). `palette` is the topic's
/// (`Taxonomy.category(id:)?.palette ?? NeutralPalette.value`).
struct TopicChip: View {
    let title: String
    let palette: CategoryPalette
    let isOn: Bool
    var size: ChipSize = .topic
    let action: () -> Void

    init(_ title: String, palette: CategoryPalette, isOn: Bool, size: ChipSize = .topic, action: @escaping () -> Void) {
        self.title = title
        self.palette = palette
        self.isOn = isOn
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ChipBody(size: size, fill: isOn ? palette.deep : palette.tint, stroke: nil) {
                HStack(spacing: 4) {
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    }
                    Text(title).textRole(.chip)
                }
                .foregroundStyle(isOn ? .white : palette.deep)
            }
        }
        .buttonStyle(ChipStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A tag pill, "#tag": on = ink fill, white text; off = sand with ink text.
/// `isAdd` draws B's dashed "+ Tag" instead.
///
/// Use it for tags only — in the refine panel, the detail sheet and search.
struct TagChip: View {
    let tag: String
    let isOn: Bool
    var isAdd = false
    var size: ChipSize = .refine
    let action: () -> Void

    init(_ tag: String, isOn: Bool, isAdd: Bool = false, size: ChipSize = .refine, action: @escaping () -> Void) {
        self.tag = tag
        self.isOn = isOn
        self.isAdd = isAdd
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if isAdd {
                ChipBody(size: size, fill: .clear, stroke: Tokens.dashed, dashed: true) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                        Text(tag).textRole(.chip)
                    }
                    .foregroundStyle(Tokens.inkSecondary)
                }
            } else {
                ChipBody(size: size, fill: isOn ? Tokens.ink : Tokens.sand, stroke: nil) {
                    (Text("#").foregroundStyle(isOn ? .white.opacity(0.7) : Tokens.inkSecondary)
                     + Text(tag).foregroundStyle(isOn ? .white : Tokens.ink))
                        .textRole(.chip)
                }
            }
        }
        .buttonStyle(ChipStyle())
        .accessibilityLabel(isAdd ? tag : "Tag \(tag)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Buttons

/// Primary: a coral pill, white 16/600. 54 pt in sheets (58 for the wheel's
/// Done). Fills the width it is given. The coral follows the person's accent.
///
/// Use it for the one main action on a screen or sheet.
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = Tokens.primaryButtonHeight
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.button, color: .white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(accent.base.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary: white with a hairline, ink 16/600. Same shape as primary.
///
/// Use it for the alternative beside or under a primary ("Not now", "Sign in").
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = Tokens.primaryButtonHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.button, color: Tokens.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(Tokens.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Tokens.hairline, lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Quiet: coral-deep text 15/600, no fill, 44 pt tall. Takes the accent's deep.
///
/// Use it for small in-line actions ("Sort ›", "See all", "Undo").
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.accent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
            .foregroundStyle(accent.deep)
            .frame(minWidth: Tokens.minTapTarget, minHeight: Tokens.minTapTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var clayPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func clayPrimary(height: CGFloat) -> PrimaryButtonStyle { PrimaryButtonStyle(height: height) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var claySecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var clayQuiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - Clay art

/// Where a piece of clay art comes from.
enum ClayArtSource: Equatable {
    /// A topic's scene (bundled for built-ins; the App Group thumbnail for a
    /// custom topic), Sand + the compass if there is none.
    case topic(String)
    /// A side-quest scene.
    case quest(QuestMotif)
    /// Any bundled imageset by name ("brandMark", "welcomeHero").
    case asset(String)
}

/// Clay art at any size, never empty: what it can't find it draws as the
/// compass on the clay ground. Decorative — hidden from VoiceOver.
///
/// Use it for art thumbs (slim rows, chips, sheet rows). Covers use `ClayCover`.
struct ClayArtImage: View {
    let source: ClayArtSource
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let image = resolved {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                compass
            }
        }
        .accessibilityHidden(true)
    }

    private var compass: some View {
        Tokens.clayGround.overlay {
            if let image = UIImage(named: QuestMotif.compass.assetName) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            }
        }
    }

    private var resolved: UIImage? {
        switch source {
        case .quest(let motif): UIImage(named: motif.assetName)
        case .asset(let name): UIImage(named: name)
        case .topic(let id):
            UIImage(named: TopicMotif.asset(for: id)) ?? QuickFileArt.image(for: id)
        }
    }
}

// MARK: - Rows

/// The slim action row (Main.dc): one white hairline row, ≥ 56 pt, a 36 pt art
/// thumb at radius 10, a title 15/600 over a meta line, and a quiet coral
/// action at the right. Optional dismiss (×).
///
/// Use it for "Sort your borks", the dial hint, backup and sign-in nudges.
/// **Never more than one on screen** — pick with `LibraryPrompt`.
struct SlimActionRow: View {
    let art: ClayArtSource
    let title: String
    let subtitle: String
    let action: String
    let perform: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: perform) {
                HStack(spacing: 12) {
                    ClayArtImage(source: art)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).textRole(.cardTitle, color: Tokens.ink)
                        Text(subtitle).textRole(.meta)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 2) {
                        Text(action)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    }
                    .modifier(QuietLabel())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.99))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title). \(subtitle)")
            .accessibilityHint(action)
            .accessibilityAddTraits(.isButton)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(width: Tokens.minTapTarget, height: Tokens.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, -12)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, onDismiss == nil ? 6 : 0)
        .padding(.vertical, 8)
        .frame(minHeight: Tokens.slimRowHeight)
        .cardSurface()
    }
}

/// The quiet button's look on a plain label (inside a larger button).
private struct QuietLabel: ViewModifier {
    @Environment(\.accent) private var accent
    func body(content: Content) -> some View {
        content
            .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
            .foregroundStyle(accent.deep)
            .padding(.horizontal, 8)
            .frame(minHeight: Tokens.minTapTarget)
    }
}

/// "New topic", "New quest": a dashed-hairline tile on paper with a symbol and
/// a title. Give it the size of its neighbours (`.frame` / grid cell).
///
/// Use it for the create-one tile at the end of a grid.
struct DashedTile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
                    .frame(width: 40, height: 40)
                    .background(Tokens.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Tokens.hairline, lineWidth: 1))
                Text(title).textRole(.cardTitle, color: Tokens.ink)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: Tokens.minTapTarget)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - Controls

/// One segmented control (Browse's Topics / Sources / Side quests): a muted
/// capsule track; the selected segment is white with a hairline and ink text.
/// 44 pt tall, segments share the width.
///
/// Use it for switching between views of the same screen. Not for filters.
struct ClaySegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    init(selection: Binding<T>, options: [(T, String)]) {
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let (value, title) = options[index]
                let on = value == selection
                Button {
                    guard !on else { return }
                    Haptics.tap()
                    withAnimation(Motion.snap) { selection = value }
                } label: {
                    Text(title)
                        .textRole(.chip, color: on ? Tokens.ink : Tokens.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if on {
                                Capsule().fill(Tokens.surface)
                                    .overlay(Capsule().strokeBorder(Tokens.hairline, lineWidth: 1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(minHeight: Tokens.minTapTarget)
        .background(Tokens.segmentTrack, in: Capsule())
    }
}

/// A search field's surface (Main.dc): ≥ 48 pt, white, hairline, radius 14,
/// 14 pt inner padding. Put the magnifier, the `TextField` and any clear
/// button in an `HStack` and apply `.searchFieldSurface()`.
struct SearchFieldSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.searchRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.searchRadius, style: .continuous)
                .strokeBorder(Tokens.hairline, lineWidth: 1))
    }
}

extension View {
    /// See `SearchFieldSurface`.
    func searchFieldSurface() -> some View { modifier(SearchFieldSurface()) }
}

/// The topic dot: 8 pt in the topic's mid. Decorative.
struct TopicDot: View {
    let palette: CategoryPalette
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(palette.mid).frame(width: size, height: size).accessibilityHidden(true)
    }
}
