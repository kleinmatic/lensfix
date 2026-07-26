import SwiftUI
import UniformTypeIdentifiers

/// A per-file write failure carried back from the background task.
struct WriteFailure: Sendable {
    let path: String
    let message: String
}

/// Owns the working set of photos, the current selection, and drives exiftool
/// reads/writes and thumbnail loading.
@MainActor
final class PhotoStore: ObservableObject {
    @Published var items: [PhotoItem] = []
    @Published var selection: Set<UUID> = []
    @Published var status: String = "Open a folder or drop photos to begin."
    @Published var isBusy: Bool = false
    @Published var exiftoolMissing: Bool

    // Lens database (shared with the CLI's lensfix.csv)
    @Published var lensPresets: [LensPreset] = []
    @Published var lensCSVName: String?
    // Set when a previously-chosen CSV has gone missing, so the UI can say so
    // instead of silently falling back to the bundled example.
    @Published var lensCSVMissingNote: String?

    // The editable lens form. Mirrors the selection's existing values until the
    // user starts editing (formDirty), after which their input is preserved.
    @Published var form = LensMetadata()
    private var formDirty = false

    // Progress of the background metadata read, shown in the status bar while a
    // batch of files is still being read (nil when idle).
    @Published var readProgress: TaskProgress?
    private var readsDone = 0
    private var readsTotal = 0

    // Progress of a tagging (write) operation, shown while files are being
    // written (nil when idle).
    @Published var writeProgress: TaskProgress?

    struct TaskProgress: Equatable {
        var done: Int
        var total: Int
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    private let exiftool: ExifToolService?

    init() {
        if let toolURL = ExifToolService.locate() {
            self.exiftool = ExifToolService(toolURL: toolURL)
            self.exiftoolMissing = false
        } else {
            self.exiftool = nil
            self.exiftoolMissing = true
        }
        reloadLensDatabase()
    }

    // MARK: - Lens database

    func reloadLensDatabase() {
        lensCSVMissingNote = nil
        let fm = FileManager.default

        // A path the user picked explicitly wins — unless it's gone missing, in
        // which case forget it and note that, rather than silently reverting to
        // the bundled example as if nothing happened.
        if let saved = LensDatabase.savedPath {
            if fm.fileExists(atPath: saved) {
                let url = URL(fileURLWithPath: saved)
                lensPresets = LensDatabase.load(from: url)
                lensCSVName = url.lastPathComponent
                return
            }
            lensCSVMissingNote = "Previous lens CSV not found (\(URL(fileURLWithPath: saved).lastPathComponent))"
            LensDatabase.clearSavedPath()
        }

        if let url = LensDatabase.defaultPath() {
            lensPresets = LensDatabase.load(from: url)
            lensCSVName = url.lastPathComponent
        } else {
            lensPresets = []
            lensCSVName = nil
        }
    }

    func setLensCSV(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: LensDatabase.savedPathKey)
        reloadLensDatabase()
    }

    var selectedItems: [PhotoItem] {
        items.filter { selection.contains($0.id) }
    }

    // MARK: - Loading

    /// Add photos from a mix of file and folder URLs (folders scanned shallowly).
    func open(urls: [URL]) {
        let expanded = Self.expandToImageFiles(urls)
        let existing = Set(items.map { $0.url.standardizedFileURL.path })
        let fresh = expanded.filter { !existing.contains($0.standardizedFileURL.path) }
        guard !fresh.isEmpty else {
            status = "No new images found."
            return
        }
        let newItems = fresh.map { PhotoItem(url: $0) }
        items.append(contentsOf: newItems)
        status = "\(items.count) photo\(items.count == 1 ? "" : "s") loaded."
        loadMetadata(for: newItems)
        for item in newItems { loadThumbnail(for: item) }
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        status = "Open a folder or drop photos to begin."
    }

    private func loadThumbnail(for item: PhotoItem) {
        let url = item.url
        Task { [weak item] in
            let image = await ThumbnailLoader.thumbnail(for: url, pointSize: 160)
            item?.thumbnail = image
        }
    }

    private func loadMetadata(for targets: [PhotoItem]) {
        guard let exiftool else {
            for t in targets { t.isLoadingMeta = false }
            return
        }
        // Read in chunks rather than one opaque exiftool call so the status-bar
        // progress bar advances and badges appear in waves. Chunks accumulate
        // into a single progress total across overlapping open() calls.
        readsTotal += targets.count
        updateReadProgress()

        Task {
            let chunkSize = 24
            for start in stride(from: 0, to: targets.count, by: chunkSize) {
                let chunk = Array(targets[start ..< min(start + chunkSize, targets.count)])
                let urls = chunk.map { $0.url }
                let readouts = await Task.detached { exiftool.read(urls: urls) }.value
                for item in chunk {
                    let key = item.url.standardizedFileURL.path
                    item.readout = readouts[key] ?? LensReadout()
                    item.isLoadingMeta = false
                }
                readsDone += chunk.count
                updateReadProgress()
                // `readout`/`needsLens` live on each PhotoItem, so mutating them
                // only refreshes the grid cells. Counts and toolbar/status state
                // that read through `items` (untaggedCount, taggedCount) are
                // derived on the store, so nudge the store to re-publish or they
                // stay stale at their pre-load values (e.g. "0 need lens").
                objectWillChange.send()
            }
        }
    }

    /// Publish the current read progress, clearing it (and resetting the running
    /// totals) once every in-flight file has been read.
    private func updateReadProgress() {
        if readsDone >= readsTotal {
            readsDone = 0
            readsTotal = 0
            readProgress = nil
        } else {
            readProgress = TaskProgress(done: readsDone, total: readsTotal)
        }
    }

    // MARK: - Selection helpers

    func toggle(_ item: PhotoItem) {
        if selection.contains(item.id) { selection.remove(item.id) }
        else { selection.insert(item.id) }
        syncFormToSelection()
    }

    func selectAll() { selection = Set(items.map { $0.id }); syncFormToSelection() }
    func clearSelection() { selection.removeAll(); syncFormToSelection() }
    func selectUntagged() {
        selection = Set(items.filter { $0.needsLens }.map { $0.id })
        syncFormToSelection()
    }

    // MARK: - Form editing

    /// User edited a field — mark the form dirty so selection changes won't
    /// clobber their input.
    func setFormField(_ field: LensField, _ value: String) {
        form.setValue(value, for: field)
        formDirty = true
    }

    /// Load a preset's values into the form (an explicit intent — protected like typing).
    func loadPreset(_ metadata: LensMetadata) {
        form = metadata
        formDirty = true
    }

    /// Reset the form to blank and let the next selection refill it.
    func clearForm() {
        form = LensMetadata()
        formDirty = false
    }

    /// Refill the form from the current selection's existing values, unless the
    /// user has unsaved edits in progress.
    private func syncFormToSelection() {
        guard !formDirty else { return }
        form = formValuesForSelection()
    }

    var untaggedCount: Int { items.filter { $0.needsLens }.count }

    /// Photos that already have a focal length (i.e. are lens-tagged).
    var taggedCount: Int { items.filter { $0.readout?.hasFocalLength == true }.count }

    /// Remove already-tagged photos from the work area, leaving the ones that
    /// still need a lens. Only removes files whose metadata has finished loading.
    func clearTagged() {
        let removedIDs = Set(items.filter { $0.readout?.hasFocalLength == true }.map { $0.id })
        guard !removedIDs.isEmpty else { return }
        items.removeAll { removedIDs.contains($0.id) }
        selection.subtract(removedIDs)
        status = "Removed \(removedIDs.count) tagged photo\(removedIDs.count == 1 ? "" : "s"). \(items.count) remaining."
    }

    // MARK: - Current values / overwrite detection

    /// Aggregate an existing field across the current selection for display.
    enum FieldSummary: Equatable {
        case blank              // all selected photos have no value
        case value(String)      // all share one value
        case multiple           // values differ across the selection
    }

    /// Read-only camera body across the selection, for display.
    func cameraSummary() -> FieldSummary {
        let values = selectedItems.map { $0.readout?.cameraDescription ?? "" }
        let distinct = Set(values)
        if distinct.count > 1 { return .multiple }
        let single = distinct.first ?? ""
        return single.isEmpty ? .blank : .value(single)
    }

    func summary(for field: LensField) -> FieldSummary {
        let values = selectedItems.map { $0.readout?.existingValue(forField: field) ?? "" }
        let distinct = Set(values)
        if distinct.count > 1 { return .multiple }
        let single = distinct.first ?? ""
        return single.isEmpty ? .blank : .value(single)
    }

    /// Pre-fill the form with the selection's existing values so the right pane
    /// reflects the photo(s) rather than a blank slate. Fields that differ
    /// across a multi-selection come back empty (surfaced as "(multiple)").
    func formValuesForSelection() -> LensMetadata {
        var meta = LensMetadata()
        for field in LensField.allCases {
            if case .value(let v) = summary(for: field) {
                meta.setValue(v, for: field)
            }
        }
        return meta
    }

    /// True if applying the current form would *change* a non-empty existing
    /// value on any selected photo (drives the "are you sure" confirmation).
    /// Re-writing an identical value is a no-op and doesn't prompt.
    func wouldOverwrite() -> Bool {
        let fieldsToWrite = LensField.allCases.filter {
            !form.value(for: $0).trimmingCharacters(in: .whitespaces).isEmpty
        }
        for item in selectedItems {
            guard let readout = item.readout else { continue }
            // A photo that still needs a lens carries only camera placeholders
            // (e.g. FocalLength 0, MaxApertureValue 1 that an adapted lens
            // leaves behind), not real lens metadata — filling those in isn't an
            // overwrite. Only warn about photos that already have a real lens.
            guard readout.hasFocalLength else { continue }
            for field in fieldsToWrite {
                let existing = readout.existingValue(forField: field).trimmingCharacters(in: .whitespaces)
                let incoming = form.value(for: field).trimmingCharacters(in: .whitespaces)
                if !existing.isEmpty && existing != incoming {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Applying

    func apply(keepBackup: Bool) {
        guard let exiftool else { return }
        let targets = selectedItems
        let metadata = form
        guard !targets.isEmpty, metadata.hasAnyValue else { return }

        isBusy = true
        let total = targets.count
        status = "Tagging \(total) photo\(total == 1 ? "" : "s")…"
        writeProgress = TaskProgress(done: 0, total: total)
        let urls = targets.map { $0.url }

        Task {
            // Write one file at a time so the progress bar can advance after each
            // (exiftool writes a single file per call regardless, so this adds no
            // extra process spawns over the old batch loop).
            var failures: [WriteFailure] = []
            for (index, url) in urls.enumerated() {
                let failure = await Task.detached { () -> WriteFailure? in
                    do {
                        try exiftool.write(metadata, to: url, keepBackup: keepBackup)
                        return nil
                    } catch {
                        return WriteFailure(path: url.standardizedFileURL.path,
                                            message: error.localizedDescription)
                    }
                }.value
                if let failure { failures.append(failure) }
                writeProgress = TaskProgress(done: index + 1, total: total)
            }
            let failedPaths = Set(failures.map { $0.path })

            // Re-read so badges and "current lens" reflect the new state, and
            // flag the successfully-written photos as changed this session.
            status = "Reading back \(total) photo\(total == 1 ? "" : "s")…"
            let readouts = await Task.detached { exiftool.read(urls: urls) }.value
            for item in targets {
                let key = item.url.standardizedFileURL.path
                if let r = readouts[key] { item.readout = r }
                if !failedPaths.contains(key) { item.wasTagged = true }
            }

            writeProgress = nil
            isBusy = false
            let ok = total - failedPaths.count
            if failures.isEmpty {
                status = "Tagged \(ok) photo\(ok == 1 ? "" : "s")."
            } else {
                status = "Tagged \(ok), \(failures.count) failed: \(failures.first?.message ?? "")"
            }

            // The written values are now the photos' real values — drop the
            // dirty guard and refresh the form to reflect them.
            formDirty = false
            syncFormToSelection()
        }
    }

    // MARK: - File discovery

    private static func expandToImageFiles(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let contents = (try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentTypeKey],
                    options: [.skipsHiddenFiles])) ?? []
                results.append(contentsOf: contents.filter(isImageFile))
            } else if isImageFile(url) {
                results.append(url)
            }
        }
        // Stable, human-friendly order.
        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .image) { return true }
        }
        // Extension fallback for anything QuickLook/UTType misses.
        let raw: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif",
                                "dng", "cr2", "cr3", "nef", "arw", "raf", "orf",
                                "rw2", "pef", "srw"]
        return raw.contains(url.pathExtension.lowercased())
    }
}
