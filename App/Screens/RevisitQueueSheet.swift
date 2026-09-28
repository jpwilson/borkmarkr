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
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
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
        .presentationDragIndicator(.visible)
        .confirmationDialog("Delete this bork?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCurrent(queue) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func topBar(_ queue: [Bookmark]) -> some View {
        HStack {
            Text(position < queue.count ? "\(position + 1) of \(queue.count)" : "All caught up")
                .font(Typo.ui(13, .semibold))
                .foregroundStyle(Tokens.inkMeta)
                .monospacedDigit()
            Spacer()
            Button("Done") { dismiss() }
                .font(Typo.ui(15, .bold))
                .foregroundStyle(accent.deep)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func actions(_ bookmark: Bookmark, isLast: Bool) -> some View {
        VStack(spacing: 10) {
            Button {
                BorkOpener.open(bookmark, in: context, using: openURL)
            } label: {
                HStack(spacing: 7) {
                    Text(bookmark.platform.openLabel).font(Typo.ui(15, .bold))
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                .shadow(color: accent.base.opacity(0.32), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("queue-open")

            HStack(spacing: 10) {
                Button {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.destructive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous)
                            .stroke(Tokens.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    withAnimation(Motion.gentle) { position += 1 }
                } label: {
                    Label(isLast ? "Finish" : "Next", systemImage: isLast ? "checkmark" : "arrow.right")
                        .labelStyle(TrailingIconLabel())
                        .font(Typo.ui(14, .bold))
                        .foregroundStyle(Tokens.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous)
                            .stroke(Tokens.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("queue-next")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Spacer()
            QuestArt(motif: .scroll)
                .frame(width: 148, height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            Text("That's the pile.")
                .font(Typo.display(24, .bold))
                .foregroundStyle(Tokens.ink)
            Text("Everything you'd saved and never opened, looked at.")
                .font(Typo.ui(14))
                .foregroundStyle(Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Done") { dismiss() }
                .font(Typo.ui(15, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(accent.base, in: Capsule())
                .padding(.top, 6)
            Spacer()
        }
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

    private var palette: CategoryPalette {
        bookmark.category?.palette ?? NeutralPalette.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !bookmark.isTextPost {
                ZStack(alignment: .topLeading) {
                    CoverImage(url: bookmark.imageURL, palette: palette)
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
                        .font(Typo.ui(13, .semibold))
                        .foregroundStyle(Tokens.inkSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Saved \(RelativeDate.label(for: bookmark.savedAt).lowercased())")
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }

                Text(bookmark.isTextPost ? (bookmark.text ?? bookmark.displayTitle) : bookmark.displayTitle)
                    .font(bookmark.isTextPost ? Typo.ui(16) : Typo.display(19, .bold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !bookmark.isTextPost, let caption = SavedContent.excerpt(bookmark.text),
                   caption != bookmark.displayTitle {
                    Text(caption)
                        .font(Typo.ui(13.5))
                        .foregroundStyle(Tokens.bodyOnWhite)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BookmarkFiling(bookmark: bookmark)

                if let note = bookmark.noteText, !note.isEmpty {
                    Text("“\(note)”")
                        .font(Typo.ui(13, .medium))
                        .foregroundStyle(Tokens.inkSecondary)
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(strong: bookmark.isMedia)
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
