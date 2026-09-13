import SwiftUI

/// Local sharing works without an account; nothing is published to a server.
struct SingleShareSheet: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var includeNote = false
    private var payload: String {
        SingleBookmarkShare.text(title:bookmark.displayTitle,url:bookmark.urlString,
            topic:bookmark.category?.name,subtopic:bookmark.subcategory,tags:bookmark.tags,
            note:bookmark.noteText,includeNote:includeNote)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("This is what you'll send")
                        .font(Typo.display(22,.bold))
                    Text(payload).font(Typo.ui(15)).textSelection(.enabled)
                        .frame(maxWidth:.infinity,alignment:.leading).padding(18)
                        .background(.white,in:RoundedRectangle(cornerRadius:20))
                    if bookmark.hasNote {
                        Toggle("Include my note",isOn:$includeNote).tint(accent.base)
                    }
                    Text("Your note is private unless you include it. The link opens the original post; recipients don't need bookmarker.")
                        .font(Typo.ui(12)).foregroundStyle(Tokens.inkSecondary)
                    ShareLink(item:payload) {
                        Label("Share link & details",systemImage:"square.and.arrow.up")
                            .font(Typo.ui(15,.semibold)).frame(maxWidth:.infinity).padding(16)
                            .foregroundStyle(.white).background(accent.base,in:RoundedRectangle(cornerRadius:16))
                    }
                }.padding(18)
            }.background(Tokens.paper)
                .navigationTitle("Share this bork").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.large]).presentationCornerRadius(Tokens.sheetRadius)
    }
}
