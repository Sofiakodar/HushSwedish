import Foundation
import Observation

// MARK: - Models

struct TemplateMatchingDefaults: Codable, Equatable {
    var minutesBefore: Int = 5
    var minutesAfter: Int = 20
}

/// ISO weekday: 1 = Monday … 7 = Sunday
struct MeetingSchedule: Codable, Equatable {
    var weekdays: [Int]
    /// Local time `HH:mm`
    var time: String
}

struct MeetingTemplate: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var enabled: Bool
    var schedule: MeetingSchedule

    init(id: UUID = UUID(), title: String, enabled: Bool = true, schedule: MeetingSchedule) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.schedule = schedule
    }
}

struct ColleaguePerson: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var aliases: [String]
    var notes: String
    var lastUsed: Date?

    init(id: UUID = UUID(), displayName: String, aliases: [String] = [], notes: String = "", lastUsed: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.notes = notes
        self.lastUsed = lastUsed
    }
}

struct GlossaryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var canonical: String
    var variants: [String]

    init(id: UUID = UUID(), canonical: String, variants: [String] = []) {
        self.id = id
        self.canonical = canonical
        self.variants = variants
    }
}

struct MeetingProfileDocument: Codable {
    var templateMatchingDefaults: TemplateMatchingDefaults = .init()
    var colleagues: [ColleaguePerson] = []
    var meetingTemplates: [MeetingTemplate] = []
    var glossaryEntries: [GlossaryEntry] = []
}

// MARK: - Store

@Observable
@MainActor
final class MeetingProfileStore {
    private(set) var templateMatchingDefaults: TemplateMatchingDefaults = .init()
    private(set) var colleagues: [ColleaguePerson] = []
    private(set) var meetingTemplates: [MeetingTemplate] = []
    private(set) var glossaryEntries: [GlossaryEntry] = []

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("meeting-profile.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let doc = try? JSONDecoder().decode(MeetingProfileDocument.self, from: data) else { return }
        templateMatchingDefaults = doc.templateMatchingDefaults
        colleagues = doc.colleagues
        meetingTemplates = doc.meetingTemplates
        glossaryEntries = doc.glossaryEntries
    }

    /// Reload rules from disk (e.g. after editing in Meetings window or before matching).
    func refreshFromDisk() {
        load()
    }

    private func persist() {
        let doc = MeetingProfileDocument(
            templateMatchingDefaults: templateMatchingDefaults,
            colleagues: colleagues,
            meetingTemplates: meetingTemplates,
            glossaryEntries: glossaryEntries
        )
        guard let data = try? JSONEncoder().encode(doc) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Glossary

    func applyGlossary(to text: String) -> String {
        GlossaryNormalizer.apply(text, entries: glossaryEntries)
    }

    func addGlossaryEntry(canonical: String, variants: [String]) {
        let trimmed = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        glossaryEntries.append(GlossaryEntry(canonical: trimmed, variants: variants))
        persist()
    }

    func updateGlossaryEntry(_ entry: GlossaryEntry) {
        guard let i = glossaryEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        glossaryEntries[i] = entry
        persist()
    }

    func deleteGlossaryEntry(id: UUID) {
        glossaryEntries.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Colleagues

    var colleaguesSortedForPicker: [ColleaguePerson] {
        colleagues.sorted { a, b in
            switch (a.lastUsed, b.lastUsed) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
    }

    func addColleague(displayName: String, aliases: [String] = [], notes: String = "") {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        colleagues.append(ColleaguePerson(displayName: name, aliases: aliases, notes: notes))
        persist()
    }

    func updateColleague(_ person: ColleaguePerson) {
        guard let i = colleagues.firstIndex(where: { $0.id == person.id }) else { return }
        colleagues[i] = person
        persist()
    }

    func deleteColleague(id: UUID) {
        colleagues.removeAll { $0.id == id }
        persist()
    }

    func noteColleagueUsed(displayName: String) {
        guard let i = colleagues.firstIndex(where: { $0.displayName == displayName }) else { return }
        colleagues[i].lastUsed = Date()
        persist()
    }

    func ensureColleagueSaved(displayName: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if colleagues.contains(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
            noteColleagueUsed(displayName: name)
            return
        }
        addColleague(displayName: name)
        noteColleagueUsed(displayName: name)
    }

    // MARK: - Meeting templates

    func addMeetingTemplate(_ template: MeetingTemplate) {
        meetingTemplates.append(template)
        persist()
    }

    func updateMeetingTemplate(_ template: MeetingTemplate) {
        guard let i = meetingTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        meetingTemplates[i] = template
        persist()
    }

    func deleteMeetingTemplate(id: UUID) {
        meetingTemplates.removeAll { $0.id == id }
        persist()
    }

    /// Default transcript title for Call Capture / file import at `instant`, or nil.
    func suggestedTitle(for instant: Date, sessionType: SessionType) -> String? {
        guard sessionType == .callCapture || sessionType == .fileImport else { return nil }
        refreshFromDisk()

        let cal = Calendar.current
        let isoWeekday = isoWeekday(for: instant, calendar: cal)
        let before = templateMatchingDefaults.minutesBefore
        let after = templateMatchingDefaults.minutesAfter

        struct Candidate {
            let template: MeetingTemplate
            let scheduled: Date
            let distance: TimeInterval
        }

        var candidates: [Candidate] = []

        for template in meetingTemplates where template.enabled {
            guard template.schedule.weekdays.contains(isoWeekday) else { continue }
            guard let scheduled = scheduledTime(on: instant, timeString: template.schedule.time, calendar: cal) else { continue }
            guard let windowStart = cal.date(byAdding: .minute, value: -before, to: scheduled),
                  let windowEnd = cal.date(byAdding: .minute, value: after + 1, to: scheduled) else { continue }
            guard instant >= windowStart, instant < windowEnd else { continue }
            candidates.append(Candidate(
                template: template,
                scheduled: scheduled,
                distance: abs(instant.timeIntervalSince(scheduled))
            ))
        }

        return candidates.min(by: { $0.distance < $1.distance })?.template.title
    }

    private func isoWeekday(for date: Date, calendar: Calendar) -> Int {
        let w = calendar.component(.weekday, from: date)
        // Calendar: 1=Sun … 7=Sat → ISO: 1=Mon … 7=Sun
        return w == 1 ? 7 : w - 1
    }

    private func scheduledTime(on day: Date, timeString: String, calendar: Calendar) -> Date? {
        let parts = timeString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        return calendar.date(from: comps)
    }
}
