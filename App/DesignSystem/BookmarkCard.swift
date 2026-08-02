import SwiftUI

/// Feed row. Two densities — the "big-card or compact view" toggle from the
/// design. Compact exists because power users end up with thousands of saves.
struct BookmarkCard: View {
    let bookmark: Bookmark
    var compact: Bool = false

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Chip(text: bookmark.platform.label,
                     symbol: bookmark.platform.symbol,
                     tint: Color(hex: bookmark.platform.tintHex))
                if let category = bookmark.category {
                    Chip(text: category.name,
                         symbol: category.symbol,
                         tint: Color(hex: category.tintHex))
                }
                Spacer()
                if bookmark.isUnread {
                    Circle().fill(Color(hex: "FF5A36")).frame(width: 8, height: 8)
                }
            }

            Text(bookmark.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if let author = bookmark.author, !author.isEmpty {
                Text(author)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
            }

            if let note = bookmark.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !bookmark.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bookmark.tags.prefix(5), id: \.self) { tag in
                            Chip(text: "#\(tag)")
                        }
                    }
                }
            }

            Text(bookmark.savedAt, format: .dateTime.day().month().year())
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.inkSoft.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var compactBody: some View {
        HStack(spacing: 12) {
            Image(systemName: bookmark.platform.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(hex: bookmark.platform.tintHex))
                .frame(width: 34, height: 34)
                .background(Color(hex: bookmark.platform.tintHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let category = bookmark.category {
                        Text(category.name)
                            .foregroundStyle(Color(hex: category.tintHex))
                    }
                    Text(bookmark.savedAt, format: .dateTime.day().month())
                        .foregroundStyle(Theme.inkSoft.opacity(0.8))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
            }

            Spacer(minLength: 0)

            if bookmark.isUnread {
                Circle().fill(Color(hex: "FF5A36")).frame(width: 7, height: 7)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 16)
    }
}
