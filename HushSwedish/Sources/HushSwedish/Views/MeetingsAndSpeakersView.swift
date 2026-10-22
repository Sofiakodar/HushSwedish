import SwiftUI

struct MeetingsAndSpeakersView: View {
    @Bindable var store: MeetingProfileStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SpeakersTab(store: store)
                .tabItem { Label("Speakers", systemImage: "person.2") }
                .tag(0)
            MeetingsTemplatesTab(store: store)
                .tabItem { Label("Meetings", systemImage: "calendar") }
                .tag(1)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private static weak var sharedWindow: NSWindow?

    @MainActor
    static func openWindow(store: MeetingProfileStore) {
        if let w = sharedWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = MeetingsAndSpeakersView(store: store)
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.title = "Meetings and speakers"
        window.setContentSize(NSSize(width: 560, height: 480))
        window.minSize = NSSize(width: 480, height: 360)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        sharedWindow = window
    }
}

// MARK: - Speakers

private struct SpeakersTab: View {
    @Bindable var store: MeetingProfileStore
    @State private var newName = ""
    @State private var editing: ColleaguePerson?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved colleagues appear as quick picks when you name speakers after a call.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            HStack {
                TextField("Add colleague name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    store.addColleague(displayName: newName)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)

            List {
                ForEach(store.colleaguesSortedForPicker) { person in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.displayName)
                                .font(.system(size: 13, weight: .medium))
                            if !person.aliases.isEmpty {
                                Text(person.aliases.joined(separator: ", "))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Button("Edit") { editing = person }
                                .buttonStyle(.borderless)
                            Button("Delete", role: .destructive) {
                                store.deleteColleague(id: person.id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .sheet(item: $editing) { person in
            ColleagueEditorSheet(person: person) { updated in
                store.updateColleague(updated)
                editing = nil
            } onCancel: { editing = nil }
        }
    }
}

private struct ColleagueEditorSheet: View {
    @State var person: ColleaguePerson
    @State private var aliasesText: String
    let onSave: (ColleaguePerson) -> Void
    let onCancel: () -> Void

    init(person: ColleaguePerson, onSave: @escaping (ColleaguePerson) -> Void, onCancel: @escaping () -> Void) {
        _person = State(initialValue: person)
        _aliasesText = State(initialValue: person.aliases.joined(separator: ", "))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit colleague")
                .font(.headline)
            TextField("Display name", text: $person.displayName)
                .textFieldStyle(.roundedBorder)
            TextField("Aliases (comma-separated)", text: $aliasesText)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    person.aliases = aliasesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    onSave(person)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Meetings

private struct MeetingsTemplatesTab: View {
    @Bindable var store: MeetingProfileStore
    @State private var editing: MeetingTemplate?

    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default transcript names for Call Capture and file import. Slot: \(store.templateMatchingDefaults.minutesBefore) min before → \(store.templateMatchingDefaults.minutesAfter) min after scheduled time. Closest schedule wins if several match.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            List {
                ForEach(store.meetingTemplates) { template in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(template.title)
                                .font(.system(size: 13, weight: .semibold))
                            if !template.enabled {
                                Text("Off")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 10) {
                                Button("Edit") { editing = template }
                                    .buttonStyle(.borderless)
                                Button("Delete", role: .destructive) {
                                    store.deleteMeetingTemplate(id: template.id)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Text(scheduleSummary(template.schedule))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("Add meeting rule…") {
                editing = MeetingTemplate(
                    title: "Standup",
                    schedule: MeetingSchedule(weekdays: [1, 2, 3, 4, 5], time: "09:00")
                )
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .sheet(item: $editing) { template in
            MeetingTemplateEditorSheet(template: template) { updated in
                if store.meetingTemplates.contains(where: { $0.id == updated.id }) {
                    store.updateMeetingTemplate(updated)
                } else {
                    store.addMeetingTemplate(updated)
                }
                editing = nil
            } onCancel: { editing = nil }
        }
    }

    private func scheduleSummary(_ schedule: MeetingSchedule) -> String {
        let days = schedule.weekdays.sorted().compactMap { iso -> String? in
            guard iso >= 1, iso <= 7 else { return nil }
            return weekdayLabels[iso - 1]
        }.joined(separator: ", ")
        return "\(days.isEmpty ? "No days" : days) at \(schedule.time)"
    }
}

private struct MeetingTemplateEditorSheet: View {
    @State var template: MeetingTemplate
    @State private var selectedWeekdays: Set<Int>
    @State private var timeDate: Date
    let onSave: (MeetingTemplate) -> Void
    let onCancel: () -> Void

    init(template: MeetingTemplate, onSave: @escaping (MeetingTemplate) -> Void, onCancel: @escaping () -> Void) {
        _template = State(initialValue: template)
        _selectedWeekdays = State(initialValue: Set(template.schedule.weekdays))
        let parts = template.schedule.time.split(separator: ":")
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts.count >= 1 ? Int(parts[0]) : 9
        comps.minute = parts.count >= 2 ? Int(parts[1]) : 0
        _timeDate = State(initialValue: Calendar.current.date(from: comps) ?? Date())
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meeting rule")
                .font(.headline)
            TextField("Transcript title", text: $template.title)
                .textFieldStyle(.roundedBorder)
            Toggle("Enabled", isOn: $template.enabled)
            Text("Weekdays")
                .font(.system(size: 11, weight: .medium))
            WeekdayPicker(selection: $selectedWeekdays)
            DatePicker("Time", selection: $timeDate, displayedComponents: .hourAndMinute)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save") {
                    let cal = Calendar.current
                    let h = cal.component(.hour, from: timeDate)
                    let m = cal.component(.minute, from: timeDate)
                    template.schedule = MeetingSchedule(
                        weekdays: selectedWeekdays.sorted(),
                        time: String(format: "%02d:%02d", h, m)
                    )
                    onSave(template)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { iso in
                let on = selection.contains(iso)
                Button(labels[iso - 1]) {
                    if on { selection.remove(iso) } else { selection.insert(iso) }
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .background(on ? Color.accentColor.opacity(0.25) : Color(NSColor.controlBackgroundColor))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(NSColor.separatorColor)))
            }
        }
    }
}
