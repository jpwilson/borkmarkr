import ImageIO
import UIKit

/// Topic pictures for the dial's hub, where the Share Extension can reach them.
///
/// The extension compiles no asset catalogue with the clay scenes in it, and
/// it must never decode a full-size image (it runs under a ~120 MB cap over
/// someone else's app). So the app copies each topic's scene into the App
/// Group as a 240 px square JPEG — about 230 KB once decoded — and the
/// extension reads only those, through ImageIO, never larger than 240 px even
/// if a bigger file turns up. No thumbnail, no picture: the dial draws the
/// topic's colour disc with its initial instead.
///
/// `<AppGroup>/quickfile/art/<topicID>.jpg`, next to the ranking snapshot.
enum QuickFileArt {
    static let thumbnailPixels = 240

    static var sharedDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Store.appGroupID)?
            .appendingPathComponent("quickfile", isDirectory: true)
            .appendingPathComponent("art", isDirectory: true)
    }

    static func sharedURL(for topicID: String) -> URL? {
        guard !topicID.isEmpty else { return nil }
        let name = topicID.replacingOccurrences(of: "/", with: "_")
        return sharedDirectory?.appendingPathComponent(name + ".jpg")
    }

    static func hasThumbnail(for topicID: String) -> Bool {
        guard let url = sharedURL(for: topicID) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The topic's thumbnail, decoded once and kept; nil when there is none.
    @MainActor
    static func image(for topicID: String) -> UIImage? {
        if let known = cache[topicID] { return known }
        let image = sharedURL(for: topicID).flatMap(decode)
        cache[topicID] = .some(image)
        return image
    }

    /// Decodes the ring's pictures up front, so turning never waits on a file.
    @MainActor
    static func preload(_ topicIDs: [String]) {
        for id in topicIDs { _ = image(for: id) }
    }

    /// App only — the extension never writes. Squares `image` (centre crop)
    /// to 240 px and writes it where `image(for:)` reads.
    static func install(_ image: UIImage, for topicID: String) throws {
        guard let url = sharedURL(for: topicID) else { throw CocoaError(.fileNoSuchFile) }
        let side = CGFloat(thumbnailPixels)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let size = image.size
            let scale = max(side / max(size.width, 1), side / max(size.height, 1))
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        guard let data = square.jpegData(compressionQuality: 0.82) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        Task { @MainActor in cache[topicID] = nil }
    }

    /// Hits and misses both, so a topic with no thumbnail is looked for once.
    @MainActor private static var cache: [String: UIImage?] = [:]

    private static func decode(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
