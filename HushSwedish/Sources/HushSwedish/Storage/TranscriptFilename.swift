import Foundation

enum TranscriptFilename {
    /// Turns user input into a safe filename segment (spaces → underscores).
    static func slug(from raw: String, maxLength: Int = 80) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        s = s.components(separatedBy: invalid).joined(separator: "-")
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.replacingOccurrences(of: ":", with: "-")

        while s.contains("__") {
            s = s.replacingOccurrences(of: "__", with: "_")
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if s.count > maxLength {
            s = String(s.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        return s
    }

    /// `2026-10-21_Meeting_about_release.md`, or `2026-10-21_14-30-45_Call_Recording.md` when no custom name.
    static func makeFilename(date: Date, customTitle: String?, defaultLabel: String) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let datePart = dateFmt.string(from: date)

        if let slug = customTitle.map({ slug(from: $0) }), !slug.isEmpty {
            return "\(datePart)_\(slug).md"
        }

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH-mm-ss"
        let timePart = timeFmt.string(from: date)
        let labelSlug = slug(from: defaultLabel)
        let labelPart = labelSlug.isEmpty ? "Recording" : labelSlug
        return "\(datePart)_\(timePart)_\(labelPart).md"
    }

    static func uniqueURL(in directory: URL, filename: String) -> URL {
        var url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return url }

        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)_\(n).\(ext)")
            n += 1
        }
        return url
    }
}
