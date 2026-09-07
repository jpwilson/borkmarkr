import SwiftUI

/// A topic, as a picture you can post.
///
/// The text share (`Core/TopicShare.swift`) is for someone who is going to tap
/// the links. This is for the other half of sharing — a story, a group chat, a
/// screenshot someone sends a friend — where nothing is tappable and the only
/// job is to look like something worth asking about.
///
/// 4:5 at 1080×1350, which is what Instagram, Threads and every other feed
/// crops least. Laid out at 360×450pt and rendered by `ImageRenderer` at
/// scale 3, so the design is expressed in the same units as the rest of the
/// app rather than in pixels.
struct TopicShareCard: View {
    let topic: Topic
    /// The topic's current name — a custom topic can have been renamed since
    /// the taxonomy entry was built.
    let name: String
    let subtopic: String?
    let count: Int
    /// Already shortened by `TopicShare.shortTitle`. Titles only: a caption
    /// belongs on the post, not on the card.
    let titles: [String]
    /// The bundled scene for a built-in, the fetched one for a topic you made,
    /// or nothing — in which case the band is the topic's own tint, exactly as
    /// the hero band does it.
    var art: UIImage?

    static let size = CGSize(width: 360, height: 450)
    /// 1080×1350.
    static let scale: CGFloat = 3

    private var heading: String {
        TopicShare.heading(topic: name, subtopic: subtopic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            band

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading)
                        .font(Typo.display(28, .heavy))
                        .tracking(-0.8)
                        .foregroundStyle(topic.palette.deep)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text("\(Copy.countedBorks(count)) I saved with bookmarker")
                        .font(Typo.ui(12.5, .semibold))
                        .foregroundStyle(Tokens.inkMeta)
                }

                // Takes whatever height is left and clips rather than pushing.
                // Six two-line titles at the largest plausible length overflow
                // 4:5, and the thing that must never be the casualty is the
                // line that says where the app is.
                titleList
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()

                footer
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(Tokens.paper)
    }

    private var titleList: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(titles.prefix(TopicShare.cardLimit).enumerated()), id: \.offset) { index, title in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)")
                        .font(Typo.mono(11))
                        .foregroundStyle(topic.palette.deep.opacity(0.7))
                        .frame(width: 14, alignment: .trailing)
                    Text(title)
                        .font(Typo.ui(13, .semibold))
                        .foregroundStyle(Tokens.bodyOnWhite)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The same band the topic page opens with, so the card is recognisably
    /// the screen it came from.
    private var band: some View {
        ZStack {
            LinearGradient(colors: [topic.palette.tint, topic.palette.tint.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let art {
                Image(uiImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: Self.size.width, height: 138)
        .clipped()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image("brandMark")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("bookmarker")
                    .font(Typo.ui(12.5, .bold))
                    .foregroundStyle(Tokens.ink)
                Text(TopicShare.footer)
                    .font(Typo.ui(10.5, .medium))
                    .foregroundStyle(Tokens.inkMeta)
            }
            Spacer(minLength: 0)
        }
    }
}
