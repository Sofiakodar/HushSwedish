import Foundation

/// Replaces ASR mis-hearings with canonical glossary forms (whole-word / phrase aware).
enum GlossaryNormalizer {
    static func apply(_ text: String, entries: [GlossaryEntry]) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        var result = text
        let sorted = entries.sorted { $0.canonical.count > $1.canonical.count }

        for entry in sorted {
            let targets = ([entry.canonical] + entry.variants)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for variant in targets where variant.caseInsensitiveCompare(entry.canonical) != .orderedSame {
                result = replacePhrase(result, variant: variant, canonical: entry.canonical)
            }
        }
        return result
    }

    private static func replacePhrase(_ text: String, variant: String, canonical: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: variant)
        let pattern = "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: canonical)
    }
}
