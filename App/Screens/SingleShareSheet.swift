import SwiftUI

/// Local sharing works without an account; nothing is published to a server.
struct SingleShareSheet: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var includeNote = false
    private var payload: String {
        SingleBookmarkShare.text(title: bookmark.displayTitle, url: bookmark.urlString,
            topic: bookmark.category?.name, subtopic: bookmark.subcategory, tags: bookmark.tags,
            note: bookmark.noteText, includeNote: includeNote)
    }
    var body: some View {
        VStack(spacing: 0) {
            ClaySheetHeader(title: "Share this bork") { dismiss() }
                .padding(.horizontal, Tokens.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What you'll send")
                        .textRole(.label, color: Tokens.inkSecondary)
                        .padding(.leading, 4)
                    Text(payload)
                        .textRole(.body, color: Tokens.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .cardSurface()
                    if bookmark.hasNote {
                        Toggle(isOn: $includeNote) {
                            Text("Include my note").textRole(.cardTitle, color: Tokens.ink)
                        }
                        .tint(accent.base)
                        .padding(.horizontal, 16)
                        .frame(minHeight: Tokens.slimRowHeight)
                        .cardSurface()
                    }
                    Text("Your note is private unless you include it. The link opens the original post; recipients don't need bookmarker.")
                        .textRole(.meta)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                    ShareLink(item: payload) {
                        Label("Share link & details", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.clayPrimary)
                    .padding(.top, 8)
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(Tokens.paper)
        .presentationDetents([.large])
        .claySheet()
    }
}
