import SwiftUI
import SwiftData

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

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
        .onAppear {
            if let initialURL, urlText.isEmpty {
                urlText = initialURL.absoluteString
                submit()
            }
        }
    }

    // MARK: Step 1 — paste

    private var pasteStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Paste any link", text: $urlText, axis: .vertical)
                    .font(Typo.mono(13.5))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Tokens.hairline, lineWidth: 1)
                    )

                Button(action: submit) {
                    Text("Fetch preview")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(parsedURL == nil ? Tokens.grabber : accent.base,
                                    in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(parsedURL == nil)

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .bold))
                    Text("Saving from another app? Use the share sheet.")
                        .font(Typo.ui(12.5, .medium))
                }
                .foregroundStyle(Tokens.inkSecondary)
            }
            .padding(18)
        }
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
                titleField
                noteSection
                saveButton
            }
            .padding(18)
            .padding(.bottom, 30)
        }
    }

    @ViewBuilder
    private var previewRow: some View {
        if let url = parsedURL {
            let platform = Platform.detect(from: url)
            HStack(spacing: 11) {
                PlatformBadge(platform: platform, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform.name)
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(Tokens.ink)
                    Text(url.host ?? "")
                        .font(Typo.mono(11))
                        .foregroundStyle(Tokens.inkMeta)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(13)
            .cardSurface(radius: 16)
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
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.base.opacity(0.25), lineWidth: 1)
        )
    }

    private var titleField: some View {
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
            Text("Save to borkmarkr")
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

    private func submit() {
        guard let url = parsedURL else { return }
        step = .reading
        Task { @MainActor in
            let suggestion = Categorizer.suggest(url: url, title: "")
            categoryID = suggestion.categoryID
            subcategory = suggestion.subcategory
            tags = suggestion.tags
            title = Categorizer.fallbackTitle(for: url)
            author = Categorizer.fallbackAuthor(for: url)
            withAnimation(.easeOut(duration: 0.2)) { step = .details }
        }
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

        let draft = BookmarkDraft(
            url: url, title: finalTitle, author: author,
            platform: Platform.detect(from: url), kind: nil,
            categoryID: categoryID, subcategory: subcategory, tags: tags,
            noteText: noteOpen && !note.isEmpty ? note : nil,
            noteDate: noteOpen && !note.isEmpty ? noteDate : nil
        )

        do {
            try Store.save(draft, in: context)
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

/// All 50 topics; expand one to pick a subcategory.
struct TopicPickerSheet: View {
    @Binding var categoryID: String?
    @Binding var subcategory: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var expanded: String?
    @State private var filter = ""

    private var shown: [Topic] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Taxonomy.all }
        return Taxonomy.all.filter {
            $0.name.lowercased().contains(needle)
                || $0.subs.contains { $0.lowercased().contains(needle) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(shown) { topic in
                        VStack(alignment: .leading, spacing: 9) {
                            Button {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    expanded = expanded == topic.id ? nil : topic.id
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(topic.palette.dot).frame(width: 10, height: 10)
                                    Text(topic.name)
                                        .font(Typo.ui(14.5, .semibold))
                                        .foregroundStyle(Tokens.ink)
                                    Spacer()
                                    Text("\(topic.subs.count)")
                                        .font(Typo.ui(11.5, .medium))
                                        .foregroundStyle(Tokens.inkMeta)
                                    Image(systemName: expanded == topic.id ? "chevron.up" : "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Tokens.inkFaint)
                                }
                            }
                            .buttonStyle(.plain)

                            if expanded == topic.id {
                                FlowChips(items: topic.subs) { sub in
                                    categoryID = topic.id
                                    subcategory = sub
                                    dismiss()
                                } tint: { topic.palette }
                            }
                        }
                        .padding(13)
                        .cardSurface(radius: 16)
                    }
                }
                .padding(18)
            }
            .background(Tokens.paper)
            .navigationTitle("Pick a topic")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "Find a topic")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }
}

/// Wrapping chip row — subcategory lists run long and a horizontal scroller
/// hides most of them.
struct FlowChips: View {
    let items: [String]
    let onPick: (String) -> Void
    let tint: () -> CategoryPalette

    var body: some View {
        let palette = tint()
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { onPick(item) } label: {
                    Text(item)
                        .font(Typo.ui(12, .semibold))
                        .foregroundStyle(palette.deep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal flow layout — SwiftUI has no built-in wrapping stack.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
