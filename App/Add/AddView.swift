import SwiftUI
import SwiftData

/// Paste a link → it detects the source, suggests a category/subcategory/tags
/// you can override, add an optional dated note → Save.
struct AddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.brandAccent) private var accent
    @Environment(\.modelContext) private var context

    /// Pre-filled when arriving from the Share Extension hand-off.
    var initialURL: URL?

    @State private var urlText = ""
    @State private var title = ""
    @State private var categoryID: String?
    @State private var subcategory: String?
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var note = ""
    @State private var noteDate = Date.now
    @State private var includeNote = false
    @State private var error: String?

    private var parsedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    linkField
                    if let url = parsedURL {
                        detected(url: url)
                        titleField
                        categoryPicker
                        tagEditor
                        noteEditor
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(Theme.background)
            .navigationTitle("Save a link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                        .disabled(parsedURL == nil)
                }
            }
            .alert("Couldn't save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .onAppear {
                if let initialURL, urlText.isEmpty {
                    urlText = initialURL.absoluteString
                    refreshSuggestion()
                }
            }
        }
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Link", systemImage: "link")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)

            TextField("Paste any link", text: $urlText, axis: .vertical)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(14)
                .card(radius: 16)
                .onChange(of: urlText) { _, _ in refreshSuggestion() }

            if !urlText.isEmpty && parsedURL == nil {
                Text("That doesn't look like a link yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private func detected(url: URL) -> some View {
        let platform = Platform.detect(from: url)
        return HStack(spacing: 8) {
            Chip(text: platform.label, symbol: platform.symbol, tint: Color(hex: platform.tintHex))
            Text(url.host ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Title", systemImage: "textformat")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            TextField("What is this?", text: $title, axis: .vertical)
                .font(.system(size: 15))
                .padding(14)
                .card(radius: 16)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Category", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                if categoryID != nil {
                    Button("Clear") {
                        categoryID = nil
                        subcategory = nil
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Taxonomy.all) { category in
                        let active = categoryID == category.id
                        Button {
                            categoryID = active ? nil : category.id
                            subcategory = nil
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: category.symbol).font(.system(size: 11, weight: .bold))
                                Text(category.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(active ? .white : Color(hex: category.tintHex))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(active ? Color(hex: category.tintHex) : Color(hex: category.tintHex).opacity(0.12),
                                        in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if let category = Taxonomy.category(id: categoryID) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(category.subcategories, id: \.self) { sub in
                            let active = subcategory == sub
                            Button {
                                subcategory = active ? nil : sub
                            } label: {
                                Text(sub)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(active ? .white : Theme.inkSoft)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(active ? Theme.ink : Theme.surface, in: Capsule())
                                    .overlay(Capsule().stroke(active ? .clear : Theme.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tags", systemImage: "number")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("#\(tag)")
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(accent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                TextField("Add a tag", text: $newTag)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(commitTag)
                Button("Add", action: commitTag)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .card(radius: 14)
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $includeNote) {
                Label("Add a note", systemImage: "note.text")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }

            if includeNote {
                TextField("Why does this matter?", text: $note, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(3...6)
                    .padding(14)
                    .card(radius: 16)

                DatePicker("Note date", selection: $noteDate, displayedComponents: .date)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 4)
            }
        }
    }

    private func commitTag() {
        let cleaned = newTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
        guard !cleaned.isEmpty, !tags.contains(cleaned) else { newTag = ""; return }
        tags.append(cleaned)
        newTag = ""
    }

    /// Re-runs whenever the link changes, but never clobbers a category or tag
    /// the user has already chosen for themselves.
    private func refreshSuggestion() {
        guard let url = parsedURL else { return }
        let suggestion = Categorizer.suggest(url: url, title: title)
        if categoryID == nil {
            categoryID = suggestion.categoryID
            subcategory = suggestion.subcategory
        }
        if tags.isEmpty {
            tags = suggestion.tags
        }
        if title.isEmpty {
            title = Self.fallbackTitle(for: url)
        }
    }

    /// No network fetch in v1 — we build a readable title from the URL slug.
    /// Real preview fetching is the obvious next upgrade.
    static func fallbackTitle(for url: URL) -> String {
        let slug = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .last { $0.count > 3 && !$0.allSatisfy(\.isNumber) }

        guard let slug else {
            return Platform.detect(from: url).label + " link"
        }
        return slug
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func save() {
        guard let url = parsedURL else { return }
        do {
            try Store.save(
                url: url,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Self.fallbackTitle(for: url)
                    : title,
                categoryID: categoryID,
                subcategory: subcategory,
                tags: tags,
                note: includeNote && !note.isEmpty ? note : nil,
                noteDate: includeNote && !note.isEmpty ? noteDate : nil,
                in: context
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
