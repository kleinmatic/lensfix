import Foundation

/// A saved lens loaded from the CLI tool's `lensfix.csv`.
struct LensPreset: Identifiable, Sendable {
    let id = UUID()
    let nickname: String
    let metadata: LensMetadata

    /// Display name for the pull-down: prefer the full lens name, fall back to nickname.
    var displayName: String {
        let lens = metadata.lens.trimmingCharacters(in: .whitespaces)
        return lens.isEmpty ? nickname : "\(nickname) — \(lens)"
    }
}

/// Loads the shared lens database (same CSV the command-line `lensfix.py` uses).
enum LensDatabase {
    /// UserDefaults key remembering a CSV location the user picked explicitly.
    static let savedPathKey = "lensCSVPath"

    /// Resolve the CSV path: a user-chosen path wins, otherwise look next to
    /// the repo (works when running via `swift run` from the `mac/` dir).
    static func resolvePath() -> URL? {
        let fm = FileManager.default
        if let saved = UserDefaults.standard.string(forKey: savedPathKey),
           fm.fileExists(atPath: saved) {
            return URL(fileURLWithPath: saved)
        }
        let cwd = fm.currentDirectoryPath
        let candidates = [
            "\(cwd)/lensfix.csv",            // running from repo root
            "\(cwd)/../lensfix.csv",         // running from mac/ via `swift run`
            "\(cwd)/lensfix.csv.example",    // fallback so the pull-down isn't empty
            "\(cwd)/../lensfix.csv.example"  // example from mac/ via `swift run`
        ]
        for path in candidates where fm.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return nil
    }

    static func load(from url: URL) -> [LensPreset] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        let index = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func value(_ row: [String], _ column: String) -> String {
            guard let i = index[column], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespaces)
        }

        var presets: [LensPreset] = []
        for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
            let nickname = value(row, "nickname")
            guard !nickname.isEmpty else { continue }
            var meta = LensMetadata()
            meta.lens = value(row, "Lens")
            meta.lensMake = value(row, "LensMake")
            meta.lensModel = value(row, "LensModel")
            meta.lensSerialNumber = value(row, "LensSerialNumber")
            meta.maxApertureValue = value(row, "MaxApertureValue")
            meta.focalLength = value(row, "FocalLength")
            meta.focalLengthIn35mm = value(row, "FocalLengthIn35mmFormat")
            presets.append(LensPreset(nickname: nickname, metadata: meta))
        }
        return presets.sorted { $0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending }
    }

    /// Minimal CSV parser: handles quoted fields and escaped quotes ("").
    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    rows.append(row); row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
