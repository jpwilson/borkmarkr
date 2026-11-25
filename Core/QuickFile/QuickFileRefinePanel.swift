import SwiftUI

/// Under the dial once a topic is chosen (Add and share): where it went, that
/// topic's subtopics, and tags, on one white slab (design/SYSTEM.md, B's
/// refine panel).
///
/// "Filed to **Fitness › Running**" heads it. A subtopic chip sets that
/// subtopic and a second tap clears it (`QuickFileModel.toggleSubtopic`); the
/// chips keep the order they were first shown in, and a late answer only
/// appends. They sit in a two-row grid that scrolls sideways, so the panel is
/// the same height for three subtopics or thirty. Tag chips toggle
/// (`QuickFileTags`) in one scrolling row, and "+ Tag" becomes a field in
/// place (or, given `onAddTag`, asks the host to open one elsewhere: the Add
/// sheet docks a second panel, `startsTyping`, above the keyboard). Return or
/// the field's round + adds the tag and keeps the field for the next one;
/// return on an empty field closes it. Text grows with Dynamic Type up to
/// accessibility3.
///
/// Given `onDone`, the panel ends in the coral Done (the share sheet); the
/// Add sheet pins its own Done above the keyboard instead.
struct QuickFileRefinePanel: View {
    let model: QuickFileModel
    let tags: QuickFileTags
    let source: QuickFileRefineSource
    var style: QuickFileStyle = .system
    /// The tag field gained or lost focus: the host makes room for the keyboard.
    var onEditingTag: (Bool) -> Void = { _ in }
    /// Done's drain is running.
    var draining: Bool = false
    /// Draws Done at the foot of the slab.
    var onDone: (() -> Void)?
    /// "+ Tag" calls this instead of opening the field in place.
    var onAddTag: (() -> Void)?

    @ScaledMetric(relativeTo: .subheadline) private var chipFont: CGFloat = 14.5
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var lineFont: CGFloat = 15
    @ScaledMetric(relativeTo: .headline) private var nameFont: CGFloat = 17
    private let startsTyping: Bool
    @State private var addingTag = false
    /// The field has had focus since it opened (read from the fallback task,
    /// where `FocusState` is not reliable).
    @State private var fieldFocused = false
    @FocusState private var typing: Bool

    /// Room inside the scrolling rows for the chips' shadows.
    private static let bleed: CGFloat = 10

    /// The panel opens with the tag field open and focused. If the field
    /// never gets focus, the panel closes it and reports `onEditingTag(false)`
    /// so the host is never stuck waiting for a keyboard.
    init(model: QuickFileModel, tags: QuickFileTags, source: QuickFileRefineSource, style: QuickFileStyle = .system,
         onEditingTag: @escaping (Bool) -> Void = { _ in }, draining: Bool = false, onDone: (() -> Void)? = nil,
         onAddTag: (() -> Void)? = nil, startsTyping: Bool = false) {
        self.model = model
        self.tags = tags
        self.source = source
        self.style = style
        self.onEditingTag = onEditingTag
        self.draining = draining
        self.onDone = onDone
        self.onAddTag = onAddTag
        self.startsTyping = startsTyping
        _addingTag = State(initialValue: startsTyping)
    }

    var body: some View {
        if let filed = model.filed {
            VStack(alignment: .leading, spacing: 0) {
                filedLine(filed)
                    .padding(.horizontal, 2)
                subtopicGrid(filed)
                    .padding(.top, 12)
                Rectangle()
                    .fill(QuickFileStyle.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 12)
                tagRow(filed)
                if let onDone {
                    QuickFileDoneButton(draining: draining, style: style, action: onDone)
                        .padding(.top, 16)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: QuickFileDepth.warm.opacity(0.12), radius: 12, y: 10)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .onChange(of: typing) { _, now in
                fieldFocused = now
                if !now {
                    tags.commitDraft()
                    withAnimation(.easeOut(duration: 0.15)) { addingTag = false }
                }
                onEditingTag(now)
            }
        }
    }

    // MARK: Heading

    /// "Filed to" in secondary, then the topic and subtopic in the display face.
    private func filedLine(_ filed: FilingCandidate) -> some View {
        let name = QuickFileCopy.topicName(filed.categoryID)
        var line = Text("Filed to ").font(style.ui(lineFont, .semibold)).foregroundColor(QuickFileStyle.inkSecondary)
            + Text(name).font(style.display(nameFont)).foregroundColor(QuickFileStyle.ink)
        if let sub = filed.subcategory {
            line = line
                + Text(" › ").font(style.display(nameFont)).foregroundColor(QuickFileStyle.inkSecondary)
                + Text(sub).font(style.display(nameFont)).foregroundColor(QuickFileStyle.ink)
        }
        return line
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(QuickFileCopy.filed(filed))
            .accessibilityAddTraits(.isHeader)
            .animation(.easeOut(duration: 0.15), value: filed)
    }

    // MARK: Subtopics

    private func subtopics(_ filed: FilingCandidate) -> [String] {
        let id = filed.categoryID
        var all = source.subs(id)
        // A subtopic the topic doesn't list (an old filing) still shows, so
        // it can be seen and cleared.
        if let sub = filed.subcategory, !all.contains(where: { $0.caseInsensitiveCompare(sub) == .orderedSame }) {
            all.insert(sub, at: 0)
        }
        let fresh = QuickFileRefine.subtopicChips(all: all, suggested: model.suggestedSubs(for: id),
                                                  used: source.used(id))
        return model.subtopicRow(for: id, fresh: fresh)
    }

    /// Two rows that scroll sideways together out to the slab's edges,
    /// filled down then across (the first chip top left, the second under
    /// it, the third beside the first…), each row packed tight like B's
    /// wrap rather than squared into columns. Fixed height: a late subtopic
    /// only lengthens a row, and no chip ever moves.
    @ViewBuilder
    private func subtopicGrid(_ filed: FilingCandidate) -> some View {
        let subs = subtopics(filed)
        if !subs.isEmpty {
            let bleed = Self.bleed
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(Self.row(row, of: subs), id: \.self) { sub in
                                    subtopicChip(sub, filed: filed).id(sub)
                                }
                            }
                            .frame(height: chipHeight)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, bleed)
                }
                .frame(height: chipHeight * 2 + 8 + bleed * 2)
                .padding(.horizontal, -16)
                .padding(.vertical, -bleed)
                .onAppear { reveal(filed.subcategory, in: proxy, animated: false) }
                .onChange(of: filed.subcategory) { _, sub in reveal(sub, in: proxy, animated: true) }
            }
            .id(filed.categoryID)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(QuickFileCopy.subtopicsLabel)
        }
    }

    /// Row 0 takes the 1st, 3rd, 5th… chip and row 1 the 2nd, 4th…, so
    /// reading down then across follows the order the chips were dealt in.
    static func row(_ row: Int, of subs: [String]) -> [String] {
        subs.enumerated().filter { $0.offset % 2 == row }.map(\.element)
    }

    private func reveal(_ sub: String?, in proxy: ScrollViewProxy, animated: Bool) {
        guard let sub else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(sub, anchor: .center) }
        } else {
            proxy.scrollTo(sub, anchor: .center)
        }
    }

    /// Off: the topic's tint and deep. On: deep, white, a check. Never mid
    /// under white text.
    private func subtopicChip(_ sub: String, filed: FilingCandidate) -> some View {
        let palette = QuickFileStyle.palette(for: filed.categoryID)
        let on = filed.subcategory?.caseInsensitiveCompare(sub) == .orderedSame
        return Button { model.toggleSubtopic(sub) } label: {
            HStack(spacing: 6) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: chipFont * 0.82, weight: .semibold))
                }
                Text(sub)
                    .font(style.ui(chipFont, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Color.white : palette.deep)
            .padding(.horizontal, 15)
            .frame(height: chipHeight)
            .background(Capsule().fill(on ? palette.deep : palette.tint))
            .overlay(QuickFileTopEdge(base: Capsule(), depth: 1.5).fill(Color.white.opacity(on ? 0.28 : 0.7)))
            .shadow(color: on ? palette.deep.opacity(0.22) : QuickFileDepth.warm.opacity(0.10),
                    radius: on ? 6 : 4, y: on ? 6 : 3)
            .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
        .animation(.easeOut(duration: 0.15), value: on)
        .accessibilityLabel(sub)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? QuickFileCopy.clearSubtopic : QuickFileCopy.fileUnder(filed.categoryID, sub))
    }

    // MARK: Tags

    private func tagRow(_ filed: FilingCandidate) -> some View {
        let chips = QuickFileRefine.tagChips(chosen: tags.chosen, suggested: tags.suggested,
                                             recent: source.recentTags(filed.categoryID, filed.subcategory))
        let bleed = Self.bleed
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                addTagChip
                ForEach(chips, id: \.tag) { chip in tagChip(chip) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, bleed)
        }
        .frame(height: chipHeight + bleed * 2)
        .padding(.horizontal, -16)
        .padding(.vertical, -bleed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(QuickFileCopy.tagsLabel)
    }

    @ViewBuilder
    private var addTagChip: some View {
        if addingTag {
            HStack(spacing: 0) {
                TextField(QuickFileCopy.newTag, text: Binding(get: { tags.draft }, set: { tags.draft = $0 }))
                    .font(style.ui(chipFont, .semibold))
                    .foregroundStyle(QuickFileStyle.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.return)
                    .focused($typing)
                    .onSubmit(submitTag)
                    .accessibilityLabel(QuickFileCopy.newTag)
                if QuickFileRefine.cleanTag(tags.draft) != nil {
                    addTagButton
                        .transition(.opacity)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, QuickFileRefine.cleanTag(tags.draft) != nil ? 0 : 14)
            .frame(width: chipFont * 12, height: chipHeight)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(style.accent.opacity(0.7), lineWidth: 1.5))
            .animation(.easeOut(duration: 0.12), value: QuickFileRefine.cleanTag(tags.draft) != nil)
            .onAppear(perform: focusField)
        } else {
            Button {
                if let onAddTag {
                    onAddTag()
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { addingTag = true }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: chipFont * 0.95, weight: .medium))
                    Text("Tag")
                        .font(style.ui(chipFont * 0.97, .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(QuickFileStyle.inkSecondary)
                .padding(.leading, 11)
                .padding(.trailing, 14)
                .frame(height: chipHeight)
                .overlay(Capsule().strokeBorder(Brand.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .contentShape(Capsule())
            }
            .buttonStyle(QuickFilePressStyle())
            .accessibilityLabel(QuickFileCopy.newTag)
        }
    }

    /// The accent + inside the field's capsule: a 30 pt circle on a 44 pt
    /// target. The same as return with text in the field.
    private var addTagButton: some View {
        Button(action: submitTag) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(style.accent))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityLabel(QuickFileCopy.addTagButton)
    }

    /// Return or +: with text, add it and stay for the next; empty, close.
    private func submitTag() {
        if QuickFileRefine.cleanTag(tags.draft) == nil {
            typing = false
        } else {
            tags.commitDraft()
            typing = true
        }
    }

    /// Focus on appear, again on the next turn if that didn't take, and if
    /// the field still has no focus shortly after, close it so a host that
    /// docked the panel for typing isn't left with a field and no keyboard.
    private func focusField() {
        typing = true
        Task { @MainActor in
            await Task.yield()
            if !typing { typing = true }
            guard startsTyping else { return }
            try? await Task.sleep(for: .milliseconds(800))
            if addingTag, !fieldFocused {
                tags.commitDraft()
                addingTag = false
                onEditingTag(false)
            }
        }
    }

    /// On: ink, white, a faded "#". Off: sand, ink, a secondary "#".
    private func tagChip(_ chip: QuickFileRefine.TagChip) -> some View {
        Button { tags.toggle(chip.tag) } label: {
            (Text("#").foregroundColor(chip.isOn ? Color.white.opacity(0.6) : QuickFileStyle.inkSecondary)
             + Text(chip.tag).foregroundColor(chip.isOn ? Color.white : QuickFileStyle.ink))
                .font(style.ui(chipFont * 0.97, .semibold))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: chipHeight)
                .background(Capsule().fill(chip.isOn ? QuickFileStyle.ink : Brand.sand))
                .overlay(QuickFileTopEdge(base: Capsule(), depth: 1.5)
                    .fill(Color.white.opacity(chip.isOn ? 0.18 : 0.7)))
                .shadow(color: chip.isOn ? QuickFileStyle.ink.opacity(0.18) : QuickFileDepth.warm.opacity(0.10),
                        radius: chip.isOn ? 6 : 4, y: chip.isOn ? 6 : 3)
                .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
        .animation(.easeOut(duration: 0.15), value: chip.isOn)
        .accessibilityLabel(QuickFileCopy.tagChip(chip.tag))
        .accessibilityAddTraits(chip.isOn ? .isSelected : [])
    }
}
