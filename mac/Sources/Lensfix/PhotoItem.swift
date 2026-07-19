import SwiftUI
import AppKit

/// One photo in the working set. Observable so grid cells refresh as the
/// thumbnail and metadata load in asynchronously.
@MainActor
final class PhotoItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL

    @Published var thumbnail: NSImage?
    @Published var readout: LensReadout?
    @Published var isLoadingMeta: Bool = true

    /// Set true after this app successfully writes a lens tag to the file
    /// during the current session — drives the "changed" badge.
    @Published var wasTagged: Bool = false

    init(url: URL) {
        self.url = url
    }

    var filename: String { url.lastPathComponent }

    /// A photo "needs a lens" when its FocalLength is missing or zero.
    var needsLens: Bool {
        guard let readout else { return false } // unknown until metadata loads
        return !readout.hasFocalLength
    }

    var currentLensDescription: String? { readout?.displayLens }
}
