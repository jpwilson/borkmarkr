import SwiftUI

/// Under the dial once a topic is chosen (Add and share): where it went, one
/// sideways row of that topic's subtopics, one of tags.
///
/// "Filed to Fitness › Running" heads it. A subtopic chip sets that subtopic
/// and a second tap clears it (`QuickFileModel.toggleSubtopic`); the chips
/// keep the order they were first shown in, and a late answer only appends.
/// Tag chips toggle (`QuickFileTags`), and "+ Tag" becomes a field in place.
/// Both rows scroll rather than wrap, so the panel's height never changes
/// under a thumb; text grows with Dynamic Type up to accessibility3.
struct QuickFileRefinePanel: View {
    let model: QuickFileModel
    let tags: QuickFileTags
    let source: QuickFileRefineSource
    var style: QuickFileStyle = .system
    /// The tag field gained or lost focus: the host makes room for the keyboard.
    var onEditingTag: (Bool) -> Void = { _ in }

    @ScaledMetric(relativeTo: .subheadline) private var chipFont: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var chipHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .headline) private var lineFont: CGFloat = 17
    @State private var addingTag = false
    @FocusState private var typing: Bool

    init(model: QuickFileModel, tags: QuickFileTags, source: QuickFileRefineSource, style: QuickFileStyle = .system,
         onEditingTag: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.tags = tags
        self.source = source
        self.style = style
        self.onEditingTag = onEditingTag
    }

    var body: some View {
        if let filed = model.filed {
            VStack(spacing: 12) {
                Text(QuickFileCopy.filed(filed))
                    .font(style.ui(lineFont, .semibold))
                    .foregroundStyle(QuickFileStyle.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .animation(.easeOut(duration: 0.15), value: filed)
                subtopicRow(filed)
                tagRow(filed)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .onChange(of: typing) { _, now in
                if !now {
                    tags.commitDraft()
                    withAnimation(.easeOut(duration: 0.15)) { addingTag = false }
                }
                onEditingTag(now)
            }
        }
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

    @ViewBuilder
    private func subtopicRow(_ filed: FilingCandidate) -> some View {
        let subs = subtopics(filed)
        if !subs.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(subs, id: \.self) { sub in
                            subtopicChip(sub, filed: filed).id(sub)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: chipHeight)
                .onAppear { reveal(filed.subcategory, in: proxy, animated: false) }
                .onChange(of: filed.subcategory) { _, sub in reveal(sub, in: proxy, animated: true) }
            }
            .id(filed.categoryID)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(QuickFileCopy.subtopicsLabel)
        }
    }

    private func reveal(_ sub: String?, in proxy: ScrollViewProxy, animated: Bool) {
        guard let sub else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(sub, anchor: .center) }
        } else {
            proxy.scrollTo(sub, anchor: .center)
        }
    }

    private func subtopicChip(_ sub: String, filed: FilingCandidate) -> some View {
        let palette = QuickFileStyle.palette(for: filed.categoryID)
        let on = filed.subcategory?.caseInsensitiveCompare(sub) == .orderedSame
        return Button { model.toggleSubtopic(sub) } label: {
            HStack(spacing: 5) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: chipFont * 0.8, weight: .bold))
                }
                Text(sub)
                    .font(style.ui(chipFont, .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(on ? Color.white : palette.deep)
            .padding(.horizontal, 13)
            .frame(height: chipHeight)
            .background(on ? palette.dot : palette.tint.opacity(0.55), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityLabel(sub)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on ? QuickFileCopy.clearSubtopic : QuickFileCopy.fileUnder(filed.categoryID, sub))
    }

    // MARK: Tags

    private func tagRow(_ filed: FilingCandidate) -> some View {
        let chips = QuickFileRefine.tagChips(chosen: tags.chosen, suggested: tags.suggested,
                                             recent: source.recentTags(filed.categoryID, filed.subcategory))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                addTagChip
                ForEach(chips, id: \.tag) { chip in tagChip(chip) }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: chipHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(QuickFileCopy.tagsLabel)
    }

    @ViewBuilder
    private var addTagChip: some View {
        if addingTag {
            TextField(QuickFileCopy.newTag, text: Binding(get: { tags.draft }, set: { tags.draft = $0 }))
                .font(style.ui(chipFont, .semibold))
                .foregroundStyle(QuickFileStyle.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($typing)
                .onSubmit {
                    if QuickFileRefine.cleanTag(tags.draft) == nil {
                        typing = false
                    } else {
                        tags.commitDraft()
                        // Stay in the field for the next one.
                        typing = true
                    }
                }
                .padding(.horizontal, 13)
                .frame(width: chipFont * 11, height: chipHeight)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(style.accent.opacity(0.6), lineWidth: 1.5))
                .accessibilityLabel(QuickFileCopy.newTag)
                .onAppear { typing = true }
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { addingTag = true }
            } label: {
                Text(QuickFileCopy.addTag)
                    .font(style.ui(chipFont, .semibold))
                    .foregroundStyle(style.accentDeep)
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .frame(height: chipHeight)
                    .overlay(Capsule().strokeBorder(QuickFileStyle.inkFaint,
                                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Capsule())
            }
            .buttonStyle(QuickFilePressStyle())
            .accessibilityLabel(QuickFileCopy.newTag)
        }
    }

    private func tagChip(_ chip: QuickFileRefine.TagChip) -> some View {
        Button { tags.toggle(chip.tag) } label: {
            Text("#\(chip.tag)")
                .font(style.ui(chipFont, .semibold))
                .lineLimit(1)
                .foregroundStyle(chip.isOn ? Color.white : QuickFileStyle.inkSecondary)
                .padding(.horizontal, 12)
                .frame(height: chipHeight)
                .background(chip.isOn ? QuickFileStyle.ink : QuickFileStyle.mutedControl, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(QuickFilePressStyle())
        .accessibilityLabel(QuickFileCopy.tagChip(chip.tag))
        .accessibilityAddTraits(chip.isOn ? .isSelected : [])
    }
}
