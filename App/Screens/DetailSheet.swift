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

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var allJourneys: [Mission]

    private var palette: CategoryPalette {
        bookmark.category?.palette ?? NeutralPalette.value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    titleBlock
                    breadcrumb
                    journeyRow
                    tagEditor
                    noteBlock
                    savedLine
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Tokens.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: bookmark.url ?? URL(string: "https://borkmarkr.app")!) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { footerBar }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .confirmationDialog("Delete this save?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: softDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from borkmarkr. The original post isn't touched.")
        }
        .sheet(isPresented: $showingPicker) {
            TopicPickerSheet(
                categoryID: Binding(
                    get: { bookmark.categoryID },
                    set: { bookmark.categoryID = $0 }
                ),
                subcategory: Binding(
                    get: { bookmark.subcategory },
                    set: { bookmark.subcategory = $0 }
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
                HStack(spacing: 7) {
                    PlatformBadge(platform: bookmark.platform, size: 26, pageURL: bookmark.url)
                    Text(bookmark.author ?? bookmark.platform.name)
                        .font(Typo.ui(13, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                }
                Text(bookmark.text ?? bookmark.title)
                    .font(Typo.ui(15))
                    .foregroundStyle(Tokens.bodyOnWhite)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        } else {
            ZStack(alignment: .topLeading) {
                CoverImage(url: bookmark.imageURL, palette: palette)
                    .frame(height: 200)
                    .clipped()

                PlatformBadge(platform: bookmark.platform, size: 26)
                    .padding(12)

                if let duration = bookmark.durationLabel {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: 9, weight: .black))
                                Text(duration).font(Typo.ui(12, .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                        }
                    }
                    .padding(12)
                    .frame(height: 200)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            if editingTitle {
                TextField("Title", text: $draftTitle, axis: .vertical)
                    .font(Typo.display(20, .bold))
                    .foregroundStyle(Tokens.ink)
                    .textFieldStyle(.plain)
                HStack {
                    Button("Cancel") { editingTitle = false }
                        .font(Typo.ui(13, .semibold))
                    Spacer()
                    Button("Save", action: commitTitle)
                        .font(Typo.ui(13, .bold))
                }
            } else {
                // Tap the title to fix it. A fetched title is usually right but
                // not always, and a brk you can't correct is a brk you distrust.
                Button {
                    draftTitle = bookmark.title
                    withAnimation(.easeOut(duration: 0.15)) { editingTitle = true }
                } label: {
                    HStack(alignment: .top, spacing: 7) {
                        Text(bookmark.title)
                            .font(Typo.display(20, .bold))
                            .foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Tokens.inkFaint)
                            .padding(.top, 6)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text([bookmark.author, bookmark.platform.name].compactMap { $0 }.joined(separator: " · "))
                    .font(Typo.ui(12.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                if bookmark.openCount > 0 {
                    Text("· opened \(bookmark.openCount)×")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(accent.deep)
                }
            }
        }
    }

    private func commitTitle() {
        let cleaned = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { editingTitle = false; return }
        bookmark.title = cleaned
        bookmark.touch()
        try? context.save()
        editingTitle = false
    }

    @ViewBuilder
    private var breadcrumb: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 6) {
                if let category = bookmark.category {
                    Text(category.name)
                        .font(Typo.ui(12.5, .semibold))
                        .foregroundStyle(palette.deep)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(palette.tint, in: Capsule())
                    if let sub = bookmark.subcategory {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Tokens.inkFaint)
                        Text(sub)
                            .font(Typo.ui(12.5, .semibold))
                            .foregroundStyle(Tokens.inkSecondary)
                    }
                } else {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("File under a topic")
                        .font(Typo.ui(13, .semibold))
                }
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.inkFaint)
                Spacer()
            }
            .foregroundStyle(Tokens.inkSecondary)
        }
        .buttonStyle(.plain)
    }

    private var onJourneys: [Mission] {
        allJourneys.filter { $0.contains(bookmark.id) }
    }

    private var journeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showingJourneys = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(onJourneys.isEmpty ? "Add to a side quest" : "On \(Copy.countedSideQuests(onJourneys.count))")
                        .font(Typo.ui(13, .semibold))
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Tokens.inkFaint)
                }
                .foregroundStyle(Tokens.inkSecondary)
            }
            .buttonStyle(.plain)

            if !onJourneys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(onJourneys) { journey in
                            Text(journey.title)
                                .font(Typo.ui(11.5, .semibold))
                                .foregroundStyle((journey.topic?.palette ?? NeutralPalette.value).deep)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background((journey.topic?.palette ?? NeutralPalette.value).tint, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !bookmark.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bookmark.tags, id: \.self) { tag in
                            Button {
                                bookmark.tags = bookmark.tags.filter { $0 != tag }
                                bookmark.touch()
                                try? context.save()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("#\(tag)").font(Typo.ui(11.5, .semibold))
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .foregroundStyle(Tokens.inkSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Tokens.mutedControl, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("+ tag", text: $tagDraft)
                    .font(Typo.ui(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitTag)
                Button("Add", action: commitTag)
                    .font(Typo.ui(12.5, .semibold))
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Tokens.surface, in: Capsule())
            .overlay(Capsule().stroke(Tokens.hairline, lineWidth: 1))
        }
    }

    private func commitTag() {
        let cleaned = tagDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !cleaned.isEmpty, !bookmark.tags.contains(cleaned) else { tagDraft = ""; return }
        bookmark.tags = bookmark.tags + [cleaned]
        bookmark.touch()
        try? context.save()
        tagDraft = ""
    }

    @ViewBuilder
    private var noteBlock: some View {
        if editingNote {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Why does this matter?", text: $draftNote, axis: .vertical)
                    .font(Typo.ui(14.5))
                    .lineLimit(3...8)
                DatePicker("Date", selection: $draftDate, displayedComponents: .date)
                    .font(Typo.ui(12.5, .medium))
                HStack {
                    Button("Cancel") { editingNote = false }
                        .font(Typo.ui(13, .semibold))
                    Spacer()
                    Button("Save note", action: commitNote)
                        .font(Typo.ui(13, .bold))
                }
            }
            .padding(14)
            .background(noteGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Tokens.noteBorder, lineWidth: 1)
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
                            .font(Typo.ui(14))
                            .foregroundStyle(Tokens.noteInk)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let date = bookmark.noteDate {
                            Text(RelativeDate.full(date))
                                .font(Typo.ui(11, .medium))
                                .foregroundStyle(Tokens.noteMeta)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(noteGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Tokens.noteBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        } else {
            Button { beginEditing() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add a note")
                        .font(Typo.ui(13.5, .semibold))
                    Spacer()
                }
                .foregroundStyle(Tokens.inkSecondary)
                .padding(14)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var noteGradient: LinearGradient {
        LinearGradient(colors: [Tokens.noteTop, Tokens.noteBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    private var savedLine: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Liked \(RelativeDate.full(bookmark.savedAt)) · from \(bookmark.platform.name)")
                .font(Typo.ui(11.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
            if let posted = bookmark.postedAt {
                Text("Posted \(RelativeDate.full(posted))")
                    .font(Typo.ui(11.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
            } else if bookmark.platform == .instagram || bookmark.platform == .tiktok || bookmark.platform == .x {
                Text("Posted date isn’t published by \(bookmark.platform.name)")
                    .font(Typo.ui(11, .medium))
                    .foregroundStyle(Tokens.inkFaint)
            }
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.destructive)
                    .frame(width: 50, height: 48)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous)
                            .stroke(Tokens.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                guard let url = bookmark.url else { return }
                // Records that you actually went back to this. Without it the
                // library is as blind as the platform bookmarks it replaces.
                bookmark.markOpened()
                try? context.save()
                openURL(url)
            } label: {
                HStack(spacing: 7) {
                    Text("Open original").font(Typo.ui(15, .bold))
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                .shadow(color: accent.base.opacity(0.32), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
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
