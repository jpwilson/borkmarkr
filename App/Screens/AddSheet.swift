import SwiftUI
import SwiftData
import UIKit

/// Three steps: paste → reading → details.
///
/// **Engineering deviation.** The prototype fakes a 950ms delay to make the
/// categoriser look like it's thinking. Ours is genuinely instant, so there is
/// nothing to wait for — a fabricated spinner is a lie that costs a second of
/// the user's time on every single save. The reading step stays in the flow
/// because real link unfurling (fetching title/thumbnail/duration) will need
/// it; until that ships it passes straight through.
struct AddSheet: View {
    var initialURL: URL?
    let onSaved: (String) -> Void
    /// Only used to reach AI categorisation, which needs a signed-in session.
    /// Optional so the sheet still works in previews and when signed out.
    var account: Account?

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Bookmark> { $0.deletedAt == nil })
    private var allBookmarks: [Bookmark]

    @Query(
        filter: #Predicate<Mission> { $0.deletedAt == nil && !$0.isArchived },
        sort: \Mission.createdAt, order: .reverse
    )
    private var journeys: [Mission]

    enum Step { case paste, reading, details }

    @State private var step = Step.paste
    @State private var urlText = ""
    @State private var title = ""
    @State private var author: String?
    @State private var categoryID: String?
    @State private var subcategory: String?
    @State private var tags: [String] = []
    @State private var tagDraft = ""
    @State private var noteOpen = false
    @State private var note = ""
    @State private var noteDate = Date.now
    @State private var showingPicker = false
    @State private var error: String?
    @State private var imageURL: URL?
    @State private var duration: Int?
    @State private var postedAt: Date?
    /// Whether the title came from the page or was generated. Drives whether we
    /// present it as a fact or as something to fill in.
    @State private var titleWasFetched = false
    @State private var editingTitle = false
    @State private var selectedJourneyIDs: Set<String> = []
    @State private var showingNewJourney = false
    @FocusState private var urlFocused: Bool

    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let host = url.host, host.contains(".") else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .paste: pasteStep
                case .reading: readingStep
                case .details: detailsStep
                }
            }
            .background(Tokens.paper)
            .navigationTitle(step == .details ? "Save to borkmarkr" : "Add a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .sheet(isPresented: $showingPicker) {
            TopicPickerSheet(categoryID: $categoryID, subcategory: $subcategory)
                .environment(\.accent, accent)
        }
        .sheet(isPresented: $showingNewJourney) {
            NewMissionSheet().environment(\.accent, accent)
        }
        .onAppear {
            if let initialURL, urlText.isEmpty {
                urlText = initialURL.absoluteString
                submit()
            }
        }
    }

    // MARK: Step 1 — paste

    /// No "Fetch preview" button. Paste a link and it just goes — a button
    /// that only ever has one sensible outcome is a step, not a choice.
    ///
    /// Do not touch the pasteboard on appear. `detectPatterns` on iOS 26 was
    /// crashing the sheet the moment + opened. The chip is always there; we
    /// only read the clipboard when you tap it.
    private var pasteStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Paste any link", text: $urlText, axis: .vertical)
                    .font(Typo.mono(13.5))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($urlFocused)
                    .padding(14)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(parsedURL != nil ? accent.base.opacity(0.5) : Tokens.hairline,
                                    lineWidth: parsedURL != nil ? 1.5 : 1)
                    )

                if urlText.isEmpty {
                    Button(action: pasteFromClipboard) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .semibold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Paste the copied link")
                                    .font(Typo.ui(13, .semibold))
                                    .foregroundStyle(Tokens.ink)
                                Text("Only reads the clipboard when you tap")
                                    .font(Typo.ui(11.5))
                                    .foregroundStyle(Tokens.inkMeta)
                            }
                            Spacer()
                        }
                        .foregroundStyle(accent.deep)
                        .padding(13)
                        .cardSurface(radius: 16)
                    }
                    .buttonStyle(PressableStyle())
                }

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                    Text("Saving from another app? Use the share sheet.")
                        .font(Typo.ui(12.5, .medium))
                }
                .foregroundStyle(Tokens.inkSecondary)
            }
            .padding(18)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            urlFocused = true
        }
        // Debounced so it fires once you've finished pasting, not on every
        // character of a typed URL.
        .task(id: urlText) {
            guard parsedURL != nil, step == .paste else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, step == .paste else { return }
            submit()
        }
    }

    /// User-tapped read. iOS treats this as a paste gesture and does not
    /// show the permission banner.
    private func pasteFromClipboard() {
        let raw = UIPasteboard.general.url?.absoluteString
            ?? UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard let url = firstURL(in: raw) else { return }
        urlText = url.absoluteString
    }

    private func firstURL(in raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http"), let url = URL(string: trimmed), url.host != nil {
            return url
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: withScheme), url.host?.contains(".") == true {
            return url
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return detector.firstMatch(in: trimmed, range: range)?.url
    }

    // MARK: Step 2 — reading

    private var readingStep: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Reading the link…")
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(Tokens.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Step 3 — details

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewRow
                sortedForYou
                journeyAttach
                titleField
                noteSection
                saveButton
            }
            .padding(18)
            .padding(.bottom, 30)
        }
    }

    /// The actual card you're about to save — thumbnail, real title, author.
    /// This is the confirmation: you see the thing, not a form about the thing.
    @ViewBuilder
    private var previewRow: some View {
        if let url = parsedURL {
            let platform = Platform.detect(from: url)
            let palette = Taxonomy.category(id: categoryID)?.palette ?? NeutralPalette.value

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    CoverImage(url: imageURL, palette: palette)
                        .frame(height: 150)
                        .clipped()
                    HStack(alignment: .top) {
                        PlatformBadge(platform: platform, size: 24, pageURL: url)
                        Spacer()
                        if let duration {
                            let label = String(format: "%d:%02d", duration / 60, duration % 60)
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                                Text(label).font(Typo.ui(10.5, .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                        }
                    }
                    .padding(10)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.isEmpty ? "Untitled" : title)
                        .font(Typo.display(15, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        Text(author ?? url.host ?? platform.name)
                            .font(Typo.ui(11.5, .medium))
                            .foregroundStyle(Tokens.inkMeta)
                            .lineLimit(1)
                        if !titleWasFetched {
                            Text("· couldn't read the page")
                                .font(Typo.ui(11))
                                .foregroundStyle(Tokens.inkFaint)
                        }
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardSurface(radius: 18)
        }
    }

    private var sortedForYou: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                Text("Sorted for you")
                    .font(Typo.ui(13, .bold))
                Spacer()
            }
            .foregroundStyle(accent.deep)

            Button { showingPicker = true } label: {
                HStack(spacing: 6) {
                    if let category = Taxonomy.category(id: categoryID) {
                        Text(subcategory.map { "\(category.name) › \($0)" } ?? category.name)
                            .font(Typo.ui(13.5, .semibold))
                            .foregroundStyle(category.palette.deep)
                    } else {
                        Text("Pick a topic")
                            .font(Typo.ui(13.5, .semibold))
                            .foregroundStyle(Tokens.inkSecondary)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tokens.inkMeta)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Taxonomy.category(id: categoryID)?.palette.tint ?? Tokens.mutedControl, in: Capsule())
            }
            .buttonStyle(.plain)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("#\(tag)").font(Typo.ui(11.5, .semibold))
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .foregroundStyle(accent.deep)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(accent.tint, in: Capsule())
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

            if !tagSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagSuggestions, id: \.self) { suggestion in
                            Button {
                                tagDraft = suggestion
                                commitTag()
                            } label: {
                                Text("#\(suggestion)")
                                    .font(Typo.ui(11.5, .semibold))
                                    .foregroundStyle(Tokens.inkSecondary)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(Tokens.mutedControl, in: Capsule())
                            }
                            .buttonStyle(ChipStyle())
                        }
                    }
                }
            }

            // When a tag clearly belongs somewhere in the taxonomy and nothing
            // is chosen yet, offer it rather than silently filing it.
            if let placement = tagPlacement {
                Button {
                    categoryID = placement.categoryID
                    subcategory = placement.subcategory
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right").font(.system(size: 10, weight: .bold))
                        Text("File under \(placement.label)?")
                            .font(Typo.ui(12, .semibold))
                        Spacer()
                    }
                    .foregroundStyle(accent.deep)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.base.opacity(0.25), lineWidth: 1)
        )
    }

    private var journeyAttach: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ALSO ON A SIDE QUEST")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            Text("Optional. Topics file what this is. A side quest is why you kept it.")
                .font(Typo.ui(12))
                .foregroundStyle(Tokens.inkMeta)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(journeys) { journey in
                        let on = selectedJourneyIDs.contains(journey.id)
                        Button {
                            if on { selectedJourneyIDs.remove(journey.id) }
                            else { selectedJourneyIDs.insert(journey.id) }
                        } label: {
                            Text(journey.title)
                                .font(Typo.ui(12, .semibold))
                                .foregroundStyle(on ? .white : Tokens.inkSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(on ? accent.base : Tokens.mutedControl, in: Capsule())
                        }
                        .buttonStyle(ChipStyle())
                    }
                    Button { showingNewJourney = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text(Copy.newSideQuest)
                                .font(Typo.ui(12, .semibold))
                        }
                        .foregroundStyle(accent.deep)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .overlay(Capsule().strokeBorder(Tokens.dashed, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Collapsed by default. The whole point is that you don't type — this is
    /// here for the times the fetched title is wrong, not as a step in the flow.
    @ViewBuilder
    private var titleField: some View {
        if editingTitle {
            titleEditor
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { editingTitle = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                    Text(titleWasFetched ? "Edit title" : "Write a title")
                        .font(Typo.ui(13, .semibold))
                    Spacer()
                }
                .foregroundStyle(Tokens.inkSecondary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var titleEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TITLE")
                .font(Typo.ui(10, .heavy)).tracking(0.6)
                .foregroundStyle(Tokens.mutedHeading)
            TextField("What is this?", text: $title, axis: .vertical)
                .font(Typo.ui(14.5))
                .padding(14)
                .cardSurface(radius: 16)
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: $noteOpen.animation(.easeOut(duration: 0.18))) {
                Text("Add a note")
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            if noteOpen {
                TextField("Why does this matter?", text: $note, axis: .vertical)
                    .font(Typo.ui(14.5))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(
                        LinearGradient(colors: [Tokens.noteTop, Tokens.noteBottom],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Tokens.noteBorder, lineWidth: 1)
                    )
                DatePicker("Note date", selection: $noteDate, displayedComponents: .date)
                    .font(Typo.ui(12.5, .medium))
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(Copy.saveVerb)
                .font(Typo.ui(15, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                .shadow(color: accent.base.opacity(0.34), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// One tap. Paste the link, we read the page, everything comes back filled
    /// in — you only touch it if you disagree.
    private func submit() {
        guard let url = parsedURL else { return }
        step = .reading

        Task { @MainActor in
            // Real fetch: oEmbed for YouTube, Open Graph for most of the web.
            let preview = await LinkPreview.fetch(for: url)

            imageURL = preview.imageURL
            duration = preview.durationSeconds
            postedAt = preview.publishedAt
            author = preview.author ?? Categorizer.fallbackAuthor(for: url)

            // A real page title, or nothing — never a routing word dressed up
            // as a description.
            let fetchedTitle = preview.title
            title = fetchedTitle ?? Categorizer.fallbackTitle(for: url)
            titleWasFetched = fetchedTitle != nil

            // Categorise against the real title when we have one; a genuine
            // headline is a far better signal than a URL slug.
            let suggestion = Categorizer.suggest(url: url, title: title)
            categoryID = suggestion.categoryID
            subcategory = suggestion.subcategory
            tags = suggestion.tags

            withAnimation(.easeOut(duration: 0.22)) { step = .details }

            // The offline answer is already on screen and editable. If it came
            // back empty or thin, ask the model — but never make the user wait
            // for it, and never let it overwrite a choice they've since made.
            await refineCategory(url: url, offline: suggestion)
        }
    }

    /// Second-pass categorisation for the links keyword matching can't place.
    ///
    /// Runs after the sheet is already interactive, so the cost is a chip
    /// changing under a thumb that hasn't moved yet rather than a spinner.
    /// Silent on every failure: signed out, offline, quota spent, server down —
    /// all of them just leave the offline answer where it is.
    private func refineCategory(url: URL, offline: Categorizer.Suggestion) async {
        guard !offline.isConfident else { return }
        guard let account, let session = await account.currentSession() else { return }

        guard let better = await SmartCategorizer.suggest(
            url: url,
            title: title,
            author: author,
            tags: tags.filter { !offline.tags.contains($0) },
            session: session
        ) else { return }

        // The user may have picked a topic themselves while this was in
        // flight. Their choice wins — always.
        guard categoryID == offline.categoryID, subcategory == offline.subcategory else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            categoryID = better.categoryID
            subcategory = better.subcategory
            // Merge rather than replace: tags the user typed in the meantime
            // stay, and the platform tag isn't duplicated.
            for tag in better.tags where !tags.contains(tag) { tags.append(tag) }
        }
    }

    /// Your own tags, ranked by how often you've used them, filtered by what
    /// you're typing. Suggesting tags you've never used would just be the
    /// taxonomy again.
    private var tagSuggestions: [String] {
        let draft = tagDraft.trimmingCharacters(in: .whitespaces).lowercased()
        var counts: [String: Int] = [:]
        for bookmark in allBookmarks {
            for tag in bookmark.tags where !tags.contains(tag) {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .filter { draft.isEmpty ? true : $0.key.hasPrefix(draft) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(6)
            .map(\.key)
    }

    /// Where the tags you've added would place this in the taxonomy — e.g.
    /// "fighting" lands on Sports › Combat sports. Uses the same offline
    /// classifier as the URL, run over the tag words instead.
    private var tagPlacement: (categoryID: String, subcategory: String?, label: String)? {
        guard categoryID == nil, !tags.isEmpty else { return nil }
        guard let url = parsedURL else { return nil }
        let suggestion = Categorizer.suggest(url: url, title: tags.joined(separator: " "))
        guard let id = suggestion.categoryID, let topic = Taxonomy.category(id: id) else { return nil }
        let label = suggestion.subcategory.map { "\(topic.name) › \($0)" } ?? topic.name
        return (id, suggestion.subcategory, label)
    }

    private func commitTag() {
        let cleaned = tagDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { tagDraft = ""; return }
        tags.append(cleaned)
        tagDraft = ""
    }

    private func save() {
        guard let url = parsedURL else { return }
        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Categorizer.fallbackTitle(for: url)
            : title

        var draft = BookmarkDraft(
            url: url, title: finalTitle, author: author,
            platform: Platform.detect(from: url), kind: nil,
            categoryID: categoryID, subcategory: subcategory, tags: tags,
            durationSeconds: duration,
            noteText: noteOpen && !note.isEmpty ? note : nil,
            noteDate: noteOpen && !note.isEmpty ? noteDate : nil
        )

        draft.imageURLString = imageURL?.absoluteString
        draft.postedAt = postedAt
        draft.previewFetched = true

        do {
            let saved = try Store.save(draft, in: context)
            if !selectedJourneyIDs.isEmpty {
                for journey in journeys where selectedJourneyIDs.contains(journey.id) {
                    journey.attach(saved.id)
                }
                try? context.save()
            }
            let where_ = Taxonomy.category(id: categoryID).map { category in
                subcategory.map { "\(category.name) › \($0)" } ?? category.name
            } ?? "your library"
            dismiss()
            onSaved("Saved to \(where_)")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
