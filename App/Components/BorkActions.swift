import SwiftUI
import SwiftData
import UIKit

/// The one way the app opens a bork: count the open, then hand the link to
/// iOS — which takes it straight to the post in Instagram, TikTok or YouTube
/// when that app is installed, and to Safari when it isn't.
@MainActor
enum BorkOpener {
    static func open(_ bookmark: Bookmark, in context: ModelContext, using openURL: OpenURLAction) {
        guard let url = bookmark.url else { return }
        // Records that you actually went back to this. Without it the
        // library is as blind as the platform bookmarks it replaces.
        bookmark.markOpened()
        try? context.save()
        openURL(url)
    }
}

/// Side quests you can file into from anywhere a bork is shown. Read once at
/// the root rather than queried by every card on screen.
private struct SideQuestsKey: EnvironmentKey {
    static var defaultValue: [Mission] { [] }
}

extension EnvironmentValues {
    var sideQuests: [Mission] {
        get { self[SideQuestsKey.self] }
        set { self[SideQuestsKey.self] = newValue }
    }
}

extension View {
    /// Press and hold a bork for what you would otherwise open it to do:
    /// open it where it lives, copy or share the link, put it on a side
    /// quest, or delete it. Every item says exactly what it does.
    ///
    /// Off in select mode, where a press picks the bork instead.
    func borkActions(_ bookmark: Bookmark, enabled: Bool = true) -> some View {
        modifier(BorkActionsModifier(bookmark: bookmark, enabled: enabled))
    }
}

private struct BorkActionsModifier: ViewModifier {
    let bookmark: Bookmark
    let enabled: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.sideQuests) private var quests
    @State private var confirmingDelete = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .contextMenu { menu }
                .confirmationDialog("Delete this bork?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: delete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(bookmark.displayTitle)
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            BorkOpener.open(bookmark, in: context, using: openURL)
        } label: {
            Label(bookmark.platform.openLabel, systemImage: "arrow.up.right")
        }

        if let url = bookmark.url {
            Button {
                UIPasteboard.general.url = url
                Haptics.success()
            } label: {
                Label("Copy link", systemImage: "link")
            }
            ShareLink(item: url, preview: SharePreview(bookmark.displayTitle)) {
                Label("Share link", systemImage: "square.and.arrow.up")
            }
        }

        if !quests.isEmpty {
            Menu {
                ForEach(quests) { quest in
                    Button { toggle(quest) } label: {
                        if quest.contains(bookmark.id) {
                            Label(quest.title, systemImage: "checkmark")
                        } else {
                            Text(quest.title)
                        }
                    }
                }
            } label: {
                Label("Side quest", systemImage: "flag")
            }
        }

        Divider()

        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    private func toggle(_ quest: Mission) {
        if quest.contains(bookmark.id) {
            quest.detach(bookmark.id)
        } else {
            quest.attach(bookmark.id)
        }
        try? context.save()
        Haptics.tap()
    }

    /// Soft delete, the same as the bin in the detail sheet: a tombstone
    /// rather than a removed row, so a signed-in delete reaches every device.
    private func delete() {
        bookmark.deletedAt = .now
        bookmark.touch()
        try? context.save()
    }
}
