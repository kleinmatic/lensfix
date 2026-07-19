import Foundation

/// The lens/focal metadata we read from and write to a photo.
/// Mirrors the columns in the CLI tool's `lensfix.csv`.
struct LensMetadata: Sendable, Equatable {
    var lens: String = ""
    var lensMake: String = ""
    var lensModel: String = ""
    var lensSerialNumber: String = ""
    var maxApertureValue: String = ""
    var focalLength: String = ""
    var focalLengthIn35mm: String = ""

    /// True if the user has entered at least one field worth writing.
    var hasAnyValue: Bool {
        LensField.allCases.contains { !value(for: $0).trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func value(for field: LensField) -> String {
        switch field {
        case .lens: return lens
        case .lensMake: return lensMake
        case .lensModel: return lensModel
        case .lensSerialNumber: return lensSerialNumber
        case .maxApertureValue: return maxApertureValue
        case .focalLength: return focalLength
        case .focalLengthIn35mm: return focalLengthIn35mm
        }
    }

    mutating func setValue(_ newValue: String, for field: LensField) {
        switch field {
        case .lens: lens = newValue
        case .lensMake: lensMake = newValue
        case .lensModel: lensModel = newValue
        case .lensSerialNumber: lensSerialNumber = newValue
        case .maxApertureValue: maxApertureValue = newValue
        case .focalLength: focalLength = newValue
        case .focalLengthIn35mm: focalLengthIn35mm = newValue
        }
    }
}

/// What we read back from a file: used both to decide "tagged" vs "needs a
/// lens" and to display the photo's existing values in the right pane.
struct LensReadout: Sendable {
    var focalLengthValue: Double?      // numeric, drives the badge
    var lens: String = ""
    var lensMake: String = ""
    var lensModel: String = ""
    var lensSerialNumber: String = ""
    var maxApertureValue: String = ""
    var focalLength: String = ""       // display form, e.g. "55 mm"
    var focalLengthIn35mm: String = ""

    // Camera body (read-only, shown to jog memory — never written).
    var cameraMake: String = ""
    var cameraModel: String = ""

    var hasFocalLength: Bool { (focalLengthValue ?? 0) > 0 }

    /// Human string for the camera body, avoiding "Canon Canon EOS…" repetition.
    var cameraDescription: String {
        let make = cameraMake.trimmingCharacters(in: .whitespaces)
        let model = cameraModel.trimmingCharacters(in: .whitespaces)
        if model.isEmpty { return make }
        if make.isEmpty || model.lowercased().hasPrefix(make.lowercased()) { return model }
        return "\(make) \(model)"
    }

    /// A short human string for the current lens, if any.
    var displayLens: String? {
        [lens, lensModel].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The existing value for the field that `LensMetadata` key writes.
    func existingValue(forField field: LensField) -> String {
        switch field {
        case .lens: return lens
        case .lensMake: return lensMake
        case .lensModel: return lensModel
        case .lensSerialNumber: return lensSerialNumber
        case .maxApertureValue: return maxApertureValue
        case .focalLength: return focalLength
        case .focalLengthIn35mm: return focalLengthIn35mm
        }
    }
}

/// The seven lens fields, shared by read display, form input, and overwrite checks.
enum LensField: CaseIterable {
    case lens, focalLength, maxApertureValue, focalLengthIn35mm
    case lensMake, lensModel, lensSerialNumber

    var label: String {
        switch self {
        case .lens: return "Lens name"
        case .focalLength: return "Focal length"
        case .maxApertureValue: return "Max aperture"
        case .focalLengthIn35mm: return "35mm equivalent"
        case .lensMake: return "Make"
        case .lensModel: return "Model"
        case .lensSerialNumber: return "Serial number"
        }
    }
}

enum ExifToolError: Error, LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "exiftool was not found. Install it with `brew install exiftool`."
        case .failed(let msg):
            return msg
        }
    }
}

/// Thin wrapper around the `exiftool` binary. All methods are blocking and
/// meant to be called off the main actor (via `Task.detached`).
struct ExifToolService: Sendable {
    let toolURL: URL

    /// Search the usual locations for exiftool. Returns nil if not found.
    static func locate() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/exiftool",
            "/usr/local/bin/exiftool",
            "/usr/bin/exiftool",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to `which` in case it lives somewhere else on PATH.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["exiftool"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let line = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty, fm.isExecutableFile(atPath: line) {
                return URL(fileURLWithPath: line)
            }
        } catch {
            // ignore — treated as not found below
        }
        return nil
    }

    /// Batch-read lens metadata for a set of files. Keyed by standardized path.
    func read(urls: [URL]) -> [String: LensReadout] {
        guard !urls.isEmpty else { return [:] }
        var args = ["-j", "-n",
                    "-FocalLength", "-Lens", "-LensModel", "-LensMake",
                    "-LensSerialNumber", "-MaxApertureValue",
                    "-FocalLengthIn35mmFormat", "-Make", "-Model"]
        args.append(contentsOf: urls.map { $0.path })

        guard let output = runData(args) else { return [:] }
        guard let array = try? JSONSerialization.jsonObject(with: output) as? [[String: Any]] else {
            return [:]
        }

        var result: [String: LensReadout] = [:]
        for entry in array {
            guard let source = entry["SourceFile"] as? String else { continue }
            let key = URL(fileURLWithPath: source).standardizedFileURL.path
            var readout = LensReadout()
            let focal = doubleValue(entry["FocalLength"])
            readout.focalLengthValue = focal
            readout.focalLength = focal.map { numberString($0) + " mm" } ?? ""
            if let f35 = doubleValue(entry["FocalLengthIn35mmFormat"]) {
                readout.focalLengthIn35mm = numberString(f35) + " mm"
            }
            if let aperture = doubleValue(entry["MaxApertureValue"]) {
                readout.maxApertureValue = numberString(aperture)
            }
            readout.lens = stringValue(entry["Lens"]) ?? ""
            readout.lensModel = stringValue(entry["LensModel"]) ?? ""
            readout.lensMake = stringValue(entry["LensMake"]) ?? ""
            readout.lensSerialNumber = stringValue(entry["LensSerialNumber"]) ?? ""
            readout.cameraMake = stringValue(entry["Make"]) ?? ""
            readout.cameraModel = stringValue(entry["Model"]) ?? ""
            result[key] = readout
        }
        return result
    }

    /// Write the given metadata into one file. When `keepBackup` is true,
    /// exiftool leaves a `<name>_original` copy beside it.
    func write(_ metadata: LensMetadata, to url: URL, keepBackup: Bool) throws {
        var args: [String] = []
        if !keepBackup { args.append("-overwrite_original") }

        func add(_ tag: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { args.append("-\(tag)=\(v)") }
        }
        add("Lens", metadata.lens)
        add("LensMake", metadata.lensMake)
        add("LensModel", metadata.lensModel)
        add("LensSerialNumber", metadata.lensSerialNumber)
        add("MaxApertureValue", metadata.maxApertureValue)
        add("FocalLength", metadata.focalLength)
        add("FocalLengthIn35mmFormat", metadata.focalLengthIn35mm)

        // Nothing to write is not an error — just skip.
        guard args.contains(where: { $0.hasPrefix("-") && $0.contains("=") }) else { return }
        args.append(url.path)

        let (status, stderr) = run(args)
        if status != 0 {
            throw ExifToolError.failed(stderr.isEmpty
                ? "exiftool exited with status \(status) for \(url.lastPathComponent)"
                : stderr)
        }
    }

    // MARK: - Process helpers

    private func runData(_ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        } catch {
            return nil
        }
    }

    private func run(_ args: [String]) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = args
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let err = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, err)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s.split(separator: " ").first.map(String.init) ?? s) }
        return nil
    }

    private func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    /// Format a number without a trailing ".0" (55.0 -> "55", 1.4 -> "1.4").
    private func numberString(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(value)
    }
}
