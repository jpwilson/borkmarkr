import SwiftUI
import SwiftData

/// Near-fullscreen item sheet. Text posts render as the post; media and
/// articles get a cover.
struct DetailSheet: View {
    @Bindable var bookmark: Bookmark

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var editingNote = false
    @State private var draftNote = ""
    @State private var draftDate = Date.now
    @State private var confirmingDelete = false
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @State private var showingPicker = false
    @State private var showingJourneys = false
    @State private var tagDraft = ""
    @StateObject private var previews = PreviewFetcher()
    @State private var refreshingPreview = false
    @State private var showingSingleShare = false
    /// Another bork opened from "More from …", stacked over this one.
    @State private var nested: Bookmark?

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var allJourneys: [Mission]

    // Waiting borks are saved and visible in the Library, but held out of
    // every count, tile and result until admitted. See `SaveLimit`.
    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil && $0.waitingSince == nil })
    private var allBookmarks: [Bookmark]

    private var palette: CategoryPalette {
        bookmark.category?.palette ?? NeutralPalette.value
    }

    var body: some View {
        VStack(spacing: 0) {
            ClaySheetHeader(title: "Saved from \(bookmark.platform.name)") { dismiss() }
                .padding(.horizontal, Tokens.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(alignment: .leading, spacing: 12) {
                        titleBlock
                        breadcrumb
                    }
                    journeyRow
                    tagEditor
                    noteBlock
                    moreFromCreator
                    VStack(alignment: .leading, spacing: 4) {
                        savedLine
                        Button {
                            Task {
                                refreshingPreview = true
                                bookmark.enrichmentVersion = nil; bookmark.enrichmentAttempts = 0; bookmark.previewFetchedAt = nil
                                await previews.fetchMissing(for: [bookmark], in: context)
                                refreshingPreview = false
                            }
                        } label: {
                            Label(refreshingPreview ? "Refreshing the preview…" : "Refresh the preview",
                                  systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.clayQuiet)
                        .disabled(refreshingPreview)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { footerBar }
        }
        .background(Tokens.paper)
        .presentationDetents([.large])
        .claySheet()
        .sheet(item: $nested) { other in
            DetailSheet(bookmark: other).environment(\.accent, accent)
        }
        .sheet(isPresented: $showingSingleShare) {
            SingleShareSheet(bookmark:bookmark).environment(\.accent,accent)
        }
        .confirmationDialog("Delete this bork?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: softDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from bookmarker. The original post isn't touched.")
        }
        .sheet(isPresented: $showingPicker) {
            TopicPickerSheet(
                categoryID: Binding(
                    get: { bookmark.categoryID },
                    set: { bookmark.categoryID = $0; bookmark.filingSource = "user"; bookmark.touch() }
                ),
                subcategory: Binding(
                    get: { bookmark.subcategory },
                    set: { bookmark.subcategory = $0; bookmark.filingSource = "user"; bookmark.touch() }
                )
            )
            .environment(\.accent, accent)
            .onDisappear {
                bookmark.touch()
                try? context.save()
            }
        }
        .sheet(isPresented: $showingJourneys) {
            JourneyPickerSheet(bookmarkID: bookmark.id)
                .environment(\.accent, accent)
        }
    }

    @ViewBuilder
    private var hero: some View {
        if bookmark.isTextPost {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    PlatformBadge(platform: bookmark.platform, size: 26, pageURL: bookmark.url)
                    Text(bookmark.displayAuthor ?? bookmark.platform.name)
                        .textRole(.meta)
                }
                Text(bookmark.text ?? bookmark.title)
                    .textRole(.body, color: Tokens.bodyOnWhite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        } else {
            // The card's cover, larger: picture over the topic's clay art,
            // the platform mark top-left, the duration bottom-right.
            CoverImage(url: bookmark.imageURL, topicID: bookmark.categoryID)
                .frame(height: 220)
                .overlay(alignment: .topLeading) {
                    PlatformBadge(platform: bookmark.platform, size: 26)
                        .padding(12)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let duration = bookmark.durationLabel {
                        DurationChip(text: duration).padding(12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                        .strokeBorder(Tokens.hairline, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if editingTitle {
                TextField("Title", text: $draftTitle, axis: .vertical)
                    .textRole(.sectionTitle, color: Tokens.ink)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous)
                        .strokeBorder(Tokens.hairline, lineWidth: 1))
                HStack {
                    Button("Cancel") { editingTitle = false }
                        .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(minHeight: Tokens.minTapTarget)
                    Spacer()
                    Button("Save", action: commitTitle)
                        .buttonStyle(.clayQuiet)
                }
            } else {
                // Tap the title to fix it. A fetched title is usually right but
                // not always, and a brk you can't correct is a brk you distrust.
                Button {
                    draftTitle = bookmark.displayTitle
                    withAnimation(.easeOut(duration: 0.15)) { editingTitle = true }
                } label: {
                    HStack(alignment: .top, spacing: 7) {
                        // The same title the card shows. The raw one is often
                        // `Name on Instagram: "caption"` or a title made from
                        // the URL; editing still writes the stored title.
                        Text(bookmark.displayTitle)
                            .textRole(.sectionTitle, color: Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.inkFaint)
                            .padding(.top, 5)
                            .accessibilityLabel("Edit title")
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text([bookmark.displayAuthor, bookmark.platform.name].compactMap { $0 }.joined(separator: " · "))
                    .textRole(.meta)
                if bookmark.openCount > 0 {
                    Text("· opened \(bookmark.openCount)×")
                        .textRole(.meta, color: accent.deep)
                }
            }
            .padding(.top, 2)
        }
    }

    private func commitTitle() {
        let cleaned = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Saving what was already shown is not an edit — and marking it one
        // would stop the real title ever arriving.
        guard !cleaned.isEmpty, cleaned != bookmark.displayTitle else { editingTitle = false; return }
        bookmark.title = cleaned
        bookmark.titleEdited = true
        bookmark.touch()
        try? context.save()
        editingTitle = false
    }

    @ViewBuilder
    private var breadcrumb: some View {
        // The topic chip in its own clay colours; tap to refile.
        HStack(spacing: 8) {
            if let category = bookmark.category {
                TopicChip(
                    [category.name, bookmark.subcategory].compactMap { $0 }.joined(separator: " › "),
                    palette: palette, isOn: false
                ) { showingPicker = true }
                .accessibilityHint("Change the topic")
            } else {
                FilterChip("File under a topic", isOn: false, symbol: "folder.badge.plus", size: .topic) {
                    showingPicker = true
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var onJourneys: [Mission] {
        allJourneys.filter { $0.contains(bookmark.id) }
    }

    private var journeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showingJourneys = true } label: {
                HStack(spacing: 12) {
                    ClayArtImage(source: .quest(.compass))
                        .frame(width: 36, height: 36)
                        .background(Tokens.clayGround)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.thumbRadius, style: .continuous))
                    Text(onJourneys.isEmpty ? "Add to a side quest" : "On \(Copy.countedSideQuests(onJourneys.count))")
                        .textRole(.cardTitle, color: Tokens.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: onJourneys.isEmpty ? "plus" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.deep)
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(minHeight: Tokens.slimRowHeight)
                .cardSurface()
            }
            .buttonStyle(PressableStyle(scale: 0.99))

            if !onJourneys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.chipGap) {
                        ForEach(onJourneys) { journey in
                            TopicChip(journey.title, palette: journey.topic?.palette ?? NeutralPalette.value,
                                      isOn: false, size: .filter) { showingJourneys = true }
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var tagEditor: some View {
        // The refine panel's tag language: a tag on the bork is an ink pill
        // (tap to take it off), a suggestion is a sand pill (tap to add).
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .textRole(.label, color: Tokens.inkSecondary)
                .padding(.leading, 4)

            if !bookmark.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.chipGap) {
                        ForEach(bookmark.tags, id: \.self) { tag in
                            TagChip(tag, isOn: true, size: .filter) {
                                bookmark.tags = bookmark.tags.filter { $0 != tag }
                                bookmark.tagsEdited = true
                                bookmark.touch()
                                try? context.save()
                            }
                            .accessibilityHint("Removes the tag")
                        }
                    }
                }
                .scrollClipDisabled()
            }

            HStack(spacing: 8) {
                Text("#").textRole(.body, color: Tokens.inkFaint)
                TextField("Add a tag", text: $tagDraft)
                    .textRole(.body, color: Tokens.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitTag)
                Button("Add", action: commitTag)
                    .buttonStyle(.clayQuiet)
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: 48)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Tokens.fieldRadius, style: .continuous)
                .strokeBorder(Tokens.hairline, lineWidth: 1))

            if !tagSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Tokens.chipGap) {
                        ForEach(tagSuggestions, id: \.self) { suggestion in
                            TagChip(suggestion, isOn: false, size: .filter) {
                                tagDraft = suggestion
                                commitTag()
                            }
                            .accessibilityHint("Adds the tag")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var tagSuggestions: [String] {
        TagRecency.suggestions(
            in: allBookmarks.map {
                .init(categoryID: $0.categoryID, subcategory: $0.subcategory, tags: $0.tags, at: $0.updatedAt)
            },
            categoryID: bookmark.categoryID,
            subcategory: bookmark.subcategory,
            excluding: Set(bookmark.tags),
            prefix: tagDraft
        )
    }

    private func commitTag() {
        let cleaned = tagDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !cleaned.isEmpty, !bookmark.tags.contains(cleaned) else { tagDraft = ""; return }
        bookmark.tags = bookmark.tags + [cleaned]
        bookmark.tagsEdited = true
        bookmark.touch()
        try? context.save()
        tagDraft = ""
    }

    @ViewBuilder
    private var noteBlock: some View {
        if editingNote {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Why does this matter?", text: $draftNote, axis: .vertical)
                    .textRole(.body, color: Tokens.noteInk)
                    .lineLimit(3...8)
                DatePicker("Date", selection: $draftDate, displayedComponents: .date)
                    .textRole(.meta)
                HStack {
                    Button("Cancel") { editingNote = false }
                        .font(.custom("Instrument Sans", size: 15, relativeTo: .subheadline).weight(.semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .frame(minHeight: Tokens.minTapTarget)
                    Spacer()
                    Button("Save note", action: commitNote)
                        .buttonStyle(.clayQuiet)
                }
            }
            .padding(16)
            .background(Tokens.noteTop, in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                    .strokeBorder(Tokens.noteBorder, lineWidth: 1)
            )
        } else if bookmark.hasNote {
            Button { beginEditing() } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Tokens.noteMeta)
                        .frame(width: 26, height: 26)
                        .background(Tokens.noteIconBG, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bookmark.noteText ?? "")
                            .textRole(.body, color: Tokens.noteInk)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let date = bookmark.noteDate {
                            Text(RelativeDate.full(date))
                                .textRole(.meta, color: Tokens.noteInk.opacity(0.8))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Tokens.noteTop, in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                        .strokeBorder(Tokens.noteBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            Button { beginEditing() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add a note")
                        .textRole(.chip, color: Tokens.inkSecondary)
                    Spacer()
                }
                .foregroundStyle(Tokens.inkSecondary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: Tokens.slimRowHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                        .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Other borks from the same creator — the way people actually look for
    /// things ("that physio on TikTok"). Hidden when there are none.
    @ViewBuilder
    private var moreFromCreator: some View {
        if let creator = bookmark.displayAuthor {
            let others = Array(allBookmarks.lazy
                .filter { $0.id != bookmark.id && $0.displayAuthor == creator }
                .prefix(10))
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("More from \(creator)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Tokens.gridGap) {
                            ForEach(others) { other in
                                Button { nested = other } label: { CreatorTile(bookmark: other) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                .padding(.top, 4)
            }
        }
    }

    private var savedLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Liked \(RelativeDate.full(bookmark.savedAt)) · from \(bookmark.platform.name)")
                .textRole(.meta)
            if let posted = bookmark.postedAt {
                Text("Posted \(RelativeDate.full(posted))")
                    .textRole(.meta)
            } else if bookmark.platform == .instagram || bookmark.platform == .tiktok {
                Text("Posted date isn’t published by \(bookmark.platform.name)")
                    .textRole(.meta)
            }
        }
        .padding(.top, 4)
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                footerIcon("trash", color: Tokens.destructive)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Delete")

            Button { showingSingleShare = true } label: {
                footerIcon("square.and.arrow.up", color: Tokens.ink)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Share this bork")

            Button {
                BorkOpener.open(bookmark, in: context, using: openURL)
            } label: {
                HStack(spacing: 7) {
                    Text(bookmark.platform.openLabel)
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(.clayPrimary)
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Tokens.paper)
        .overlay(alignment: .top) { Tokens.hairline.frame(height: 1) }
    }

    /// A 54 pt white circle with a hairline, beside the primary pill.
    private func footerIcon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(color)
            .frame(width: Tokens.primaryButtonHeight, height: Tokens.primaryButtonHeight)
            .background(Tokens.surface, in: Circle())
            .overlay(Circle().strokeBorder(Tokens.hairline, lineWidth: 1))
            .contentShape(Circle())
    }

    private func beginEditing() {
        draftNote = bookmark.noteText ?? ""
        draftDate = bookmark.noteDate ?? .now
        editingNote = true
    }

    private func commitNote() {
        let cleaned = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmark.noteText = cleaned.isEmpty ? nil : cleaned
        bookmark.noteDate = cleaned.isEmpty ? nil : draftDate
        bookmark.touch()
        try? context.save()
        editingNote = false
    }

    /// Soft delete — sets a tombstone rather than removing the row, so the sync
    /// fast-follow can propagate the deletion instead of the other device
    /// helpfully re-adding it.
    private func softDelete() {
        bookmark.deletedAt = .now
        bookmark.touch()
        try? context.save()
        dismiss()
    }
}

/// A small cover-and-title tile for "More from …".
private struct CreatorTile: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A text post wears its topic's clay art, as on the card.
            CoverImage(url: bookmark.imageURL, topicID: bookmark.categoryID)
                .frame(width: 118, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Tokens.hairline, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    PlatformBadge(platform: bookmark.platform, size: 18, pageURL: bookmark.url).padding(7)
                }

            Text(bookmark.displayTitle)
                .font(.custom("Instrument Sans", size: 13, relativeTo: .footnote).weight(.semibold))
                .foregroundStyle(Tokens.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 118, alignment: .leading)
        }
    }
}
