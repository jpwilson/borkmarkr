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
                        .font(Typo.display(28, .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 6) {
                        TopicDot(palette: topic.palette)
                        Text("\(Copy.countedBorks(count)) I saved with bookmarker")
                            .font(Typo.ui(13, .medium))
                            .foregroundStyle(Tokens.inkSecondary)
                    }
                }

                // Takes whatever height is left and clips rather than pushing.
                // Six two-line titles at the largest plausible length overflow
                // 4:5, and the thing that must never be the casualty is the
                // line that says where the app is.
                // An overlay reports no size of its own, so however long the
                // titles are they can only be clipped, never push the footer
                // off the card.
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) { titleList }
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
                        .font(Typo.ui(12, .semibold).monospacedDigit())
                        .foregroundStyle(topic.palette.deep)
                        .frame(width: 14, alignment: .trailing)
                    Text(title)
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The same band the topic page opens with, so the card is recognisably
    /// the screen it came from.
    /// No gradient (1.4): the scene on the clay ground, or the compass there
    /// when the topic has no scene of its own.
    private var band: some View {
        Tokens.clayGround
            .overlay {
                if let art {
                    Image(uiImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ClayArtImage(source: .topic(topic.id))
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
                    .font(Typo.display(13, .bold))
                    .foregroundStyle(Tokens.ink)
                Text(TopicShare.footer)
                    .font(Typo.ui(11, .medium))
                    .foregroundStyle(Tokens.inkSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}
