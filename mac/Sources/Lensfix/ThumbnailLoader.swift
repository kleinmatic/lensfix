import AppKit
import QuickLookThumbnailing

/// Generates thumbnails with QuickLook, which handles JPEG, HEIC, TIFF and
/// most RAW formats out of the box.
enum ThumbnailLoader {
    static func thumbnail(for url: URL, pointSize: CGFloat) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pointSize, height: pointSize),
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let rep = try await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            return rep.nsImage
        } catch {
            return nil
        }
    }
}
