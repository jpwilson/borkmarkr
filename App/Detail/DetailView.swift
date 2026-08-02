import SwiftUI
import SwiftData

/// One saved item: breadcrumb, tags, your dated note, and the three things you
/// actually do with a save — open the original, share it, delete it.
struct DetailView: View {
    @Bindable var bookmark: Bookmark

    @Environment(\.brandAccent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var editingNote = false
    @State private var draftNote = ""
    @State private var draftDate = Date.now
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                breadcrumb
                if !bookmark.tags.isEmpty { tagRow }
                noteSection
                actions
            }
            .padding(16)
            .padding(.bottom, 60)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: bookmark.url ?? URL(string: "https://borkmarkr.app")!) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog("Delete this save?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(bookmark)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from borkmarkr. The original post isn't touched.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Chip(text: bookmark.platform.label,
                     symbol: bookmark.platform.symbol,
                     tint: Color(hex: bookmark.platform.tintHex))
                Spacer()
                Text(bookmark.savedAt, format: .dateTime.day().month().year())
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }

            Text(bookmark.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            if let author = bookmark.author, !author.isEmpty {
                Text(author)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }

            Text(bookmark.urlString)
                .font(.system(size: 12))
                .foregroundStyle(accent)
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var breadcrumb: some View {
        if let category = bookmark.category {
            HStack(spacing: 6) {
                Image(systemName: category.symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(category.name)
                if let sub = bookmark.subcategory {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    Text(sub)
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hex: category.tintHex))
        }
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bookmark.tags, id: \.self) { tag in
                    Chip(text: "#\(tag)", tint: accent)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Note", systemImage: "note.text")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Button(editingNote ? "Done" : (bookmark.note == nil ? "Add" : "Edit")) {
                    if editingNote {
                        commitNote()
                    } else {
                        draftNote = bookmark.note ?? ""
                        draftDate = bookmark.noteDate ?? .now
                        editingNote = true
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            }

            if editingNote {
                TextField("Why does this matter?", text: $draftNote, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(3...8)
                    .padding(14)
                    .card(radius: 16)
                DatePicker("Date", selection: $draftDate, displayedComponents: .date)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            } else if let note = bookmark.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                    if let date = bookmark.noteDate {
                        Text(date, format: .dateTime.day().month().year())
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 16)
            } else {
                Text("No note yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft.opacity(0.8))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if let url = bookmark.url { openURL(url) }
            } label: {
                Label("Open original", systemImage: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func commitNote() {
        let cleaned = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmark.note = cleaned.isEmpty ? nil : cleaned
        bookmark.noteDate = cleaned.isEmpty ? nil : draftDate
        try? context.save()
        editingNote = false
    }
}
