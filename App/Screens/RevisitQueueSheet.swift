import SwiftUI
import SwiftData

/// "Saved, never opened", one at a time.
///
/// The pile is the point of Revisit — and a list of forty is still a list you
/// scroll past. This deals the borks out one by one: see what it was, open it
/// where it lives, or move on. Coming back from Instagram or TikTok lands on
/// the same card with **Next** ready, so a pile becomes ten minutes of
/// catching up instead of a guilty number.
///
/// Works from a snapshot of ids taken when it opens: opening a bork takes it
/// out of "never opened", and the queue must not reshuffle under your thumb
/// because of it.
struct RevisitQueueSheet: View {
    let bookmarks: [Bookmark]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.accent) private var accent

    @State private var position = 0
    @State private var confirmingDelete = false
    /// Borks deleted from here, so the count stays honest.
    @State private var removed: Set<String> = []

    private var remaining: [Bookmark] {
        bookmarks.filter { !removed.contains($0.id) && $0.deletedAt == nil }
    }

    var body: some View {
        let queue = remaining
        VStack(spacing: 0) {
            topBar(queue)
            if position < queue.count {
                ScrollView {
                    BorkQueueCard(bookmark: queue[position])
                        .padding(.horizontal, Tokens.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .id(queue[position].id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
                actions(queue[position], isLast: position == queue.count - 1)
            } else {
                finished
            }
        }
        .background(Tokens.paper)
        .claySheet()
        .confirmationDialog("Delete this bork?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCurrent(queue) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from bookmarker. The original post isn't touched.")
        }
    }

    /// A's sheet header: "Saved, never opened", the position under it, Done.
    private func topBar(_ queue: [Bookmark]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 18)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved, never opened")
                        .font(.custom("Instrument Sans", size: 17, relativeTo: .headline).weight(.semibold))
                        .foregroundStyle(Tokens.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(position < queue.count ? "\(position + 1) of \(queue.count)" : "All caught up")
                        .textRole(.meta)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Done") { dismiss() }
                    .buttonStyle(.clayQuiet)
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, 4)
    }

    private func actions(_ bookmark: Bookmark, isLast: Bool) -> some View {
        VStack(spacing: 10) {
            Button {
                BorkOpener.open(bookmark, in: context, using: openURL)
            } label: {
                HStack(spacing: 7) {
                    Text(bookmark.platform.openLabel)
                    Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(.clayPrimary)
            .accessibilityIdentifier("queue-open")

            HStack(spacing: 10) {
                Button {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(Tokens.destructive)
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))

                Button {
                    Haptics.tap()
                    withAnimation(Motion.gentle) { position += 1 }
                } label: {
                    Label(isLast ? "Finish" : "Next", systemImage: isLast ? "checkmark" : "arrow.right")
                        .labelStyle(TrailingIconLabel())
                }
                .buttonStyle(SecondaryButtonStyle(height: 48))
                .accessibilityIdentifier("queue-next")
            }
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Tokens.paper)
        .overlay(alignment: .top) { Tokens.hairline.frame(height: 1) }
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Spacer()
            ClayArtImage(source: .quest(.scroll))
                .frame(width: 148, height: 148)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text("That's the pile.")
                .textRole(.screenTitle, color: Tokens.ink)
                .padding(.top, 8)
            Text("Everything you'd saved and never opened, looked at.")
                .textRole(.body, color: Tokens.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.clayPrimary)
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private func deleteCurrent(_ queue: [Bookmark]) {
        guard position < queue.count else { return }
        let bookmark = queue[position]
        bookmark.deletedAt = .now
        bookmark.touch()
        try? context.save()
        // The next bork slides into this position; nothing to advance.
        withAnimation(Motion.gentle) { _ = removed.insert(bookmark.id) }
    }
}

/// One bork, big enough to recognise: cover, who made it, what it said.
private struct BorkQueueCard: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !bookmark.isTextPost {
                ZStack(alignment: .topLeading) {
                    CoverImage(url: bookmark.imageURL, topicID: bookmark.categoryID)
                        .frame(height: bookmark.isMedia ? 340 : 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    PlatformBadge(platform: bookmark.platform, size: 28, pageURL: bookmark.url)
                        .padding(12)
                }
                .frame(height: bookmark.isMedia ? 340 : 200)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    if bookmark.isTextPost {
                        PlatformBadge(platform: bookmark.platform, size: 22, pageURL: bookmark.url)
                    }
                    Text(bookmark.displayAuthor ?? bookmark.platform.name)
                        .textRole(.meta)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Saved \(RelativeDate.label(for: bookmark.savedAt).lowercased())")
                        .textRole(.meta)
                }

                Text(bookmark.isTextPost ? (bookmark.text ?? bookmark.displayTitle) : bookmark.displayTitle)
                    .textRole(bookmark.isTextPost ? .body : .sectionTitle, color: Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !bookmark.isTextPost, let caption = SavedContent.excerpt(bookmark.text),
                   caption != bookmark.displayTitle {
                    Text(caption)
                        .textRole(.body, color: Tokens.bodyOnWhite)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BookmarkFiling(bookmark: bookmark)

                if let note = bookmark.noteText, !note.isEmpty {
                    Text("“\(note)”")
                        .textRole(.meta)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// "Next →": the arrow after the word, where it points.
private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
