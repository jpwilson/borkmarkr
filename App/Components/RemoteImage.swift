import SwiftUI
import ImageIO
import UIKit

/// Remote bitmaps — covers, favicons, topic art — downsampled to the size
/// they are drawn at, kept decoded between appearances, and kept on disk
/// between launches.
///
/// `AsyncImage` did none of that. It decoded every cover at full resolution
/// (a 1080×1920 reel still is ~8 MB of pixels, for a card 200pt wide), kept
/// nothing once a view went away, and started the download over every time
/// it came back. With the Library drawing every card at once, a few hundred
/// borks meant a few hundred full-size decodes at launch: the simulator sat
/// at ~900 MB and ~10 s of CPU with a 269-bork library, and a phone with a
/// real library crawled.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    /// A decoded bitmap, and whether it is the whole original — an original
    /// is good enough for any size, a downsample only for the size it was
    /// made for (or smaller).
    final class Entry: @unchecked Sendable {
        let image: UIImage
        let isOriginal: Bool
        init(image: UIImage, isOriginal: Bool) {
            self.image = image
            self.isOriginal = isOriginal
        }

        func covers(_ box: CGSize, fill: Bool) -> Bool {
            if isOriginal { return true }
            let w = CGFloat(image.cgImage?.width ?? 0), h = CGFloat(image.cgImage?.height ?? 0)
            // A few percent short is invisible; a refetch for it is not.
            return fill
                ? w >= box.width * 0.9 && h >= box.height * 0.9
                : w >= box.width * 0.9 || h >= box.height * 0.9
        }
    }

    private struct Request: Hashable {
        let url: URL
        let width: Int
        let height: Int
        let fill: Bool
    }

    private let memory = NSCache<NSURL, Entry>()
    private let session: URLSession
    private let lock = NSLock()
    private var inFlight: [Request: Task<Entry?, Never>] = [:]

    private init() {
        memory.totalCostLimit = 96 * 1024 * 1024

        let config = URLSessionConfiguration.default
        // A cover is a CDN file that never changes under its URL. A stored
        // copy is as good as a fresh one — and it outlives the signed
        // Instagram and TikTok URLs, which stop working weeks after a save.
        config.requestCachePolicy = .returnCacheDataElseLoad
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "covers", directoryHint: .isDirectory)
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 300 << 20, directory: directory)
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    /// Already decoded, if anything. Cheap enough to call from a view's
    /// initialiser, so a card scrolled back into view has its cover on the
    /// very first frame rather than fading in again.
    func cached(_ url: URL?) -> Entry? {
        guard let url else { return nil }
        return memory.object(forKey: url as NSURL)
    }

    /// A bitmap big enough to `fill` (or fit) a box of `box` **pixels**.
    func image(for url: URL, box: CGSize, fill: Bool) async -> Entry? {
        if let hit = cached(url), hit.covers(box, fill: fill) { return hit }

        // Bucketed, so a card a few points wider than the last one reuses
        // the same request instead of starting another.
        let request = Request(url: url,
                              width: Self.bucket(box.width), height: Self.bucket(box.height),
                              fill: fill)
        let task = lock.withLock { () -> Task<Entry?, Never> in
            if let running = inFlight[request] { return running }
            let session = self.session
            let running = Task.detached(priority: .userInitiated) { () -> Entry? in
                guard let (data, response) = try? await session.data(from: url) else { return nil }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                return Self.decode(data, box: CGSize(width: request.width, height: request.height), fill: fill)
            }
            inFlight[request] = running
            return running
        }
        let entry = await task.value
        lock.withLock { inFlight[request] = nil }

        if let entry {
            // Keep the larger of what we had and what we made.
            if let existing = cached(url), existing.covers(box, fill: fill), !entry.isOriginal {
                return existing
            }
            memory.setObject(entry, forKey: url as NSURL, cost: Self.cost(of: entry.image))
        }
        return entry
    }

    private static func bucket(_ pixels: CGFloat) -> Int {
        let step = 64
        return max(step, Int((pixels / CGFloat(step)).rounded(.up)) * step)
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 1 }
        return cg.bytesPerRow * cg.height
    }

    /// Decodes straight to the drawn size with ImageIO — never the full
    /// bitmap first — and never upscales.
    static func decode(_ data: Data, box: CGSize, fill: Bool) -> Entry? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0

        var longSide = max(box.width, box.height)
        var isOriginal = false
        if width > 0, height > 0 {
            let scale = fill
                ? max(box.width / width, box.height / height)
                : min(box.width / width, box.height / height)
            isOriginal = scale >= 1
            longSide = max(width, height) * min(1, scale)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(longSide.rounded(.up))),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Entry(image: UIImage(cgImage: cg), isOriginal: isOriginal)
    }
}

/// A remote bitmap that takes exactly the space it is given.
///
/// Size-neutral by construction: it reads its box from a `GeometryReader`
/// and never reports a size of its own, so a wide image cannot push a card —
/// and through it the whole screen — wider than the column it sits in. Put it
/// in an `.overlay` or a fixed frame; on its own it fills whatever it is
/// offered.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// Space kept clear around the bitmap only — the placeholder still gets
    /// the whole box. A favicon sits inset in its badge; its fallback glyph
    /// is laid out for the full badge.
    var inset: CGFloat = 0
    /// Drawn until the bitmap arrives, and for good if it never does.
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        GeometryReader { geo in
            RemoteBitmap(url: url, box: geo.size, inset: inset, contentMode: contentMode, placeholder: placeholder)
        }
    }
}

extension RemoteImage where Placeholder == EmptyView {
    init(url: URL?, contentMode: ContentMode = .fill, inset: CGFloat = 0) {
        self.init(url: url, contentMode: contentMode, inset: inset, placeholder: { EmptyView() })
    }
}

private struct RemoteBitmap<Placeholder: View>: View {
    let url: URL?
    let box: CGSize
    let inset: CGFloat
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    /// The bitmap's own box: the offered space less the inset.
    private var size: CGSize {
        CGSize(width: max(0, box.width - inset * 2), height: max(0, box.height - inset * 2))
    }

    init(url: URL?, box: CGSize, inset: CGFloat, contentMode: ContentMode,
         placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.box = box
        self.inset = inset
        self.contentMode = contentMode
        self.placeholder = placeholder
        _image = State(initialValue: ImagePipeline.shared.cached(url)?.image)
    }

    /// `.fill` draws a bitmap already cut to the box, rather than a larger
    /// one scaled up and clipped: clipping hides the overflow from the eye
    /// but not from layout, and the card's accessibility frame still took
    /// in the whole 4:3 thumbnail — 267pt of it in a 197pt column.
    @ViewBuilder
    private func bitmap(_ image: UIImage) -> some View {
        if contentMode == .fill {
            Image(uiImage: Self.cut(image, toAspectOf: size)).resizable()
        } else {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
        }
    }

    /// The centred part of `image` with `box`'s aspect ratio. A sub-image
    /// that shares the original's pixels — no copy, no redraw.
    private static func cut(_ image: UIImage, toAspectOf box: CGSize) -> UIImage {
        guard let cg = image.cgImage, box.width > 0, box.height > 0 else { return image }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let target = box.width / box.height
        var rect = CGRect(x: 0, y: 0, width: width, height: height)
        if width / height > target {
            rect.size.width = height * target
            rect.origin.x = (width - rect.width) / 2
        } else {
            rect.size.height = width / target
            rect.origin.y = (height - rect.height) / 2
        }
        guard let cropped = cg.cropping(to: rect.integral) else { return image }
        return UIImage(cgImage: cropped)
    }

    private struct Key: Equatable {
        let url: URL?
        let width: Int
        let height: Int
    }

    var body: some View {
        ZStack {
            if let image {
                bitmap(image)
                    .frame(width: size.width, height: size.height)
                    // Decorative: the card's title and creator say what it
                    // is. Exposed, every cover was an unlabelled "image" to
                    // VoiceOver.
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                placeholder()
                    .frame(width: box.width, height: box.height)
            }
        }
        .frame(width: box.width, height: box.height)
        .task(id: Key(url: url, width: Int(size.width), height: Int(size.height))) {
            guard let url else {
                image = nil
                return
            }
            guard size.width > 0, size.height > 0 else { return }
            let box = CGSize(width: size.width * displayScale, height: size.height * displayScale)
            guard let entry = await ImagePipeline.shared.image(
                for: url, box: box, fill: contentMode == .fill
            ), !Task.isCancelled else { return }
            guard entry.image !== image else { return }
            // Cross-fade only a first arrival; a sharper copy of what is
            // already on screen swaps in without a flash.
            if image == nil {
                withAnimation(.easeOut(duration: 0.22)) { image = entry.image }
            } else {
                image = entry.image
            }
        }
    }
}
