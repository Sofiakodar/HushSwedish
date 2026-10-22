import SwiftUI
import AppKit
import Combine
import CoreAudio
import UniformTypeIdentifiers

enum MainWindowLayout {
    static let width: CGFloat = 520
    static let height: CGFloat = 548
}

private let conferencingBundleIDs: [String: String] = [
    "com.microsoft.teams2": "Teams",
    "com.microsoft.teams": "Teams",
    "us.zoom.xos": "Zoom",
    "com.apple.FaceTime": "FaceTime",
    "com.tinyspeck.slackmacgap": "Slack",
    "com.cisco.webexmeetingsapp": "Webex",
    "Cisco-Systems.Spark": "Webex",
    "com.google.Chrome": "Chrome",
    "company.thebrowser.Browser": "Arc",
    "com.apple.Safari": "Safari",
    "com.microsoft.edgemac": "Edge",
]

struct ContentView: View {
    @Bindable var settings: AppSettings
    var recordingState: RecordingState
    var transcriptStore: TranscriptStore
    var transcriptionEngine: TranscriptionEngine
    var meetingMonitor: MeetingMonitor
    var meetingProfileStore: MeetingProfileStore
    /// When ContentView is hosted outside the SwiftUI scene (e.g. in a popover),
    /// the caller can supply an override so the Settings button still works.
    var openSettingsOverride: (() -> Void)? = nil
    @State private var sessionStore = SessionStore()
    @Environment(\.openSettings) private var openSettings
    @State private var transcriptLogger = TranscriptLogger()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showQuitConfirmation = false
    @State private var audioLevel: Float = 0
    @State private var micLevel: Float = 0
    @State private var sysLevel: Float = 0
    @State private var activeSessionType: SessionType?
    @State private var detectedAppName: String?
    @State private var silenceSeconds: Int = 0
    @State private var savedFileURL: URL?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var sessionElapsed: Int = 0
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []
    @State private var logoFlash = false
    @State private var showSpeakerNaming = false
    @State private var speakerLabelsForNaming: [String] = []
    @State private var speakerPreviewsForNaming: [String: [String]] = [:]
    @State private var speakerNamingContinuation: CheckedContinuation<[String: String], Never>?
    @State private var showFilePicker = false
    @State private var recordingSessionLanguage: SessionTranscriptionLanguage?
    @State private var recordingSessionTitle: String?
    @State private var preRollPhase: PreRollPhase?
    @State private var flatMicSeconds = 0
    @State private var isRestartingCapture = false
    @State private var suggestedMeetingTitle: String?

    var body: some View {
        coreContent
            .background(notificationHandlers)
            .task { await pollAudioLevels() }
            .task { await runSilenceTimer() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    await transcriptLogger.flushIfNeeded()
                }
            }
            .onChange(of: settings.inputDeviceID) {
                if isRunning { transcriptionEngine.restartMic(inputDeviceID: settings.inputDeviceID) }
            }
            .onChange(of: settings.transcriptionModel) {
                transcriptionEngine.setModel(settings.transcriptionModel)
            }
            .onChange(of: settings.modelIdleUnloadInterval) {
                transcriptionEngine.idleUnloadIntervalDidChange()
            }
            .onChange(of: transcriptStore.utterances.count) {
                handleNewUtterance()
            }
            .task(id: transcriptionEngine.isSpeechDetected) {
                if transcriptionEngine.isSpeechDetected {
                    while !Task.isCancelled {
                        withAnimation(.easeIn(duration: 0.25)) { logoFlash = true }
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { break }
                        withAnimation(.easeOut(duration: 0.35)) { logoFlash = false }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { logoFlash = false }
                }
            }
            .task(id: warmUpKey) {
                await transcriptionEngine.warmUpForRecording(
                    sessionLanguage: settings.sessionTranscriptionLanguage,
                    sysVadThreshold: settings.sysVadThreshold
                )
            }
    }

    private var warmUpKey: String {
        "\(settings.transcriptionModel.rawValue)-\(settings.sessionTranscriptionLanguage.rawValue)"
    }

    private var coreContent: some View {
        VStack(spacing: 0) {
            topBar
            windowToolbar
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            if let url = savedFileURL, activeSessionType == nil {
                saveBanner(url: url)
            }
            waveformSection
            if !showOnboarding {
                controlBarSection
                    .layoutPriority(1)
            }
        }
        .frame(width: MainWindowLayout.width, height: MainWindowLayout.height)
        .background(Color.bg0)
        .allowsHitTesting(!showOnboarding)
        .onAppear { transcriptionEngine.noteTranscriptionUIAppeared() }
        .onDisappear { transcriptionEngine.noteTranscriptionUIDisappeared() }
        .confirmationDialog("Quit \(AppIdentity.displayName)?", isPresented: $showQuitConfirmation, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding, settings: settings, isReplay: hasCompletedOnboarding)
                    .allowsHitTesting(true)
                    .transition(.opacity)
            }
        }
        .overlay { if showSpeakerNaming { speakerNamingOverlay } }
        .overlay { if let phase = preRollPhase { PreRollOverlay(phase: phase) } }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                startFileSession(url: url)
            }
        }
        .onChange(of: showOnboarding) { _, showing in
            if showing {
                NSApp.keyWindow?.makeFirstResponder(nil)
            } else {
                hasCompletedOnboarding = true
            }
        }
        .task {
            if !hasCompletedOnboarding {
                showOnboarding = true
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    @ViewBuilder
    private var mainContentArea: some View {
        if !isRunning && transcriptStore.utterances.isEmpty
            && transcriptStore.volatileYouText.isEmpty
            && transcriptStore.volatileThemText.isEmpty
            && !transcriptionEngine.isSpeechDetected {
            if transcriptionEngine.isDownloadingSelectedModel {
                modelDownloadProgress
            } else if transcriptionEngine.showsModelDownloadGate {
                modelDownloadPrompt
            } else {
                emptyState
            }
        } else {
            TranscriptView(
                utterances: transcriptStore.utterances,
                volatileYouText: transcriptStore.volatileYouText,
                volatileThemText: transcriptStore.volatileThemText
            )
        }
    }

    private var speakerNamingOverlay: some View {
        SpeakerNamingView(
            speakerLabels: speakerLabelsForNaming,
            previews: speakerPreviewsForNaming,
            colleagues: meetingProfileStore.colleaguesSortedForPicker,
            onApply: { mapping in
                for name in mapping.values {
                    meetingProfileStore.ensureColleagueSaved(displayName: name)
                }
                showSpeakerNaming = false
                speakerNamingContinuation?.resume(returning: mapping)
                speakerNamingContinuation = nil
            },
            onSkip: {
                showSpeakerNaming = false
                speakerNamingContinuation?.resume(returning: [:])
                speakerNamingContinuation = nil
            }
        )
        .transition(.opacity)
    }

    private var notificationHandlers: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .appStartCallCapture)) { _ in
                startSession(type: .callCapture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appStartVoiceMemo)) { _ in
                startSession(type: .voiceMemo)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appStopRecording)) { _ in
                stopSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appPauseRecording)) { _ in
                pauseFromMenu()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appResumeRecording)) { _ in
                resumeFromMenu()
            }
            .onReceive(NotificationCenter.default.publisher(for: .appOpenSummarize)) { _ in
                SummarizeView.openWindow(settings: settings, logger: transcriptLogger)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appOpenMeetingsAndSpeakers)) { _ in
                MeetingsAndSpeakersView.openWindow(store: meetingProfileStore)
            }
            .onChange(of: settings.sessionTranscriptNameDraft) { _, _ in
                guard !settings.suppressSessionTranscriptNameDraftTracking else { return }
                settings.sessionTranscriptNameUserEdited = true
            }
            .onChange(of: showFilePicker) { _, isOpen in
                if isOpen { refreshSuggestedMeetingTitle(for: .fileImport) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .appPopoverDidOpen)) { _ in
                refreshSuggestedMeetingTitle(for: .callCapture)
            }
            .onAppear {
                refreshSuggestedMeetingTitle(for: .callCapture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appShowOnboarding)) { _ in
                showOnboarding = true
            }
    }

    private func pollAudioLevels() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            if transcriptionEngine.isRunning {
                let newMic = transcriptionEngine.micAudioLevel
                let newSys = transcriptionEngine.sysAudioLevel
                let newCombined = transcriptionEngine.audioLevel
                if abs(newMic - micLevel) > 0.005 { micLevel = newMic }
                if abs(newSys - sysLevel) > 0.005 { sysLevel = newSys }
                if abs(newCombined - audioLevel) > 0.005 { audioLevel = newCombined }
                if audioLevel > 0.01 { silenceSeconds = 0 }
            } else if audioLevel != 0 {
                audioLevel = 0; micLevel = 0; sysLevel = 0
            }
        }
    }

    private func runSilenceTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard isRunning else {
                silenceSeconds = 0
                flatMicSeconds = 0
                continue
            }
            guard !transcriptionEngine.isPaused else { continue }
            sessionElapsed += 1
            if audioLevel < 0.01 {
                silenceSeconds += 1
                if silenceSeconds >= settings.silenceTimeoutSeconds { stopSession() }
            }
            if !transcriptionEngine.isMicMuted, micLevel < 0.02 {
                flatMicSeconds += 1
            } else {
                flatMicSeconds = 0
            }
        }
    }

    private var showNoMicSignalHint: Bool {
        isRunning && !transcriptionEngine.isPaused && !transcriptionEngine.isMicMuted && flatMicSeconds >= 10
    }

    private func restartCaptureFromUI() {
        guard isRunning, !isRestartingCapture else { return }
        Task {
            isRestartingCapture = true
            await transcriptionEngine.resetCapture(inputDeviceID: settings.inputDeviceID)
            flatMicSeconds = 0
            isRestartingCapture = false
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            HushSwedishHeaderWordmark(highlighted: logoFlash)

            Spacer()

            HStack(spacing: 10) {
                Menu {
                    Button {
                        settings.inputDeviceID = 0
                    } label: {
                        HStack {
                            Text("System Default")
                            if settings.inputDeviceID == 0 { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(inputDevices, id: \.id) { device in
                        Button {
                            settings.inputDeviceID = device.id
                        } label: {
                            HStack {
                                Text(device.name)
                                if settings.inputDeviceID == device.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Text(topBarStatus)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isRunning ? Color.fg1 : Color.fg2)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onAppear { inputDevices = MicCapture.availableInputDevices() }
                .help("Click to select input device")

                if isRunning {
                    PulsingDot(size: 6)
                } else {
                    Circle()
                        .fill(Color.fg2)
                        .frame(width: 6, height: 6)
                        .opacity(0.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Window Toolbar

    private var windowToolbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                toolbarButton(icon: "doc.text.magnifyingglass", label: "Transcripts") {
                    SummarizeView.openWindow(settings: settings, logger: transcriptLogger)
                    if settings.mainWindowMode == .attached {
                        NotificationCenter.default.post(name: .appClosePopover, object: nil)
                    }
                }
                toolbarButton(icon: "person.2.crop.square.stack", label: "Meetings") {
                    MeetingsAndSpeakersView.openWindow(store: meetingProfileStore)
                }
                toolbarButton(icon: "gear", label: "Settings") {
                    settings.preferredSettingsTab = 0
                    if let openSettingsOverride {
                        openSettingsOverride()
                    } else {
                        openSettings()
                    }
                }
                toolbarButton(icon: "arrow.up.doc", label: "Import") {
                    showFilePicker = true
                }
                .disabled(isRunning || !transcriptionEngine.canStartRecording)
                .opacity(isRunning || !transcriptionEngine.canStartRecording ? 0.35 : 1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                if settings.mainWindowMode == .attached {
                    toolbarIconButton(
                        icon: settings.autoMeetingDetect ? "waveform.badge.magnifyingglass" : "waveform.slash",
                        help: "Auto-record meetings"
                    ) {
                        settings.autoMeetingDetect.toggle()
                    }
                    .opacity(settings.autoMeetingDetect ? 1.0 : 0.4)
                    .overlay(alignment: .topTrailing) {
                        if settings.autoMeetingDetect && meetingMonitor.isMeetingActive {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                                .offset(x: 2, y: -2)
                        }
                    }
                    toolbarIconButton(icon: "power", help: "Quit") {
                        showQuitConfirmation = true
                    }
                    toolbarIconButton(icon: "arrow.up.left.and.arrow.down.right", help: "Detach window") {
                        settings.mainWindowMode = .detached
                    }
                } else {
                    toolbarIconButton(icon: "arrow.down.right.and.arrow.up.left", help: "Attach to menu bar") {
                        settings.mainWindowMode = .attached
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 42)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.fg2)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toolbarIconButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.fg2)
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var topBarStatus: String {
        let deviceID = settings.inputDeviceID == 0
            ? (MicCapture.defaultInputDeviceID() ?? 0)
            : settings.inputDeviceID
        let deviceSuffix = deviceID != 0 ? MicCapture.deviceName(for: deviceID).map { " · \($0)" } ?? "" : ""

        if isRunning {
            let pauseSuffix = transcriptionEngine.isPaused ? " · Paused" : ""
            return "\(formatTime(sessionElapsed))\(pauseSuffix)\(deviceSuffix)"
        } else if savedFileURL != nil {
            return "\(formatTime(sessionElapsed)) · Done\(deviceSuffix)"
        } else {
            return "Ready\(deviceSuffix)"
        }
    }

    // MARK: - Model Download State

    @ViewBuilder
    private func modelRecommendationRow(title: String, detail: String, size: String?, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accent1 : Color.fg3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.fg1)
                    if let size, !size.isEmpty {
                        Text(size)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.fg3)
                    }
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modelDownloadProgress: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accent1)
            Text(transcriptionEngine.assetStatus)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.fg2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var modelDownloadPrompt: some View {
        let model = settings.transcriptionModel
        return VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.fg3)
            Text("Download a model to start")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.fg1)
            Text("\(model.displayName) is not on this Mac yet.\(model.sizeLabel.isEmpty ? "" : " (\(model.sizeLabel))")")
                .font(.system(size: 11))
                .foregroundStyle(Color.fg3)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Recommended")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.fg2)
                modelRecommendationRow(
                    title: TranscriptionModel.whisperLargeV3.displayName,
                    detail: "Swedish and English — best for HushSwedish meetings",
                    size: TranscriptionModel.whisperLargeV3.sizeLabel,
                    isSelected: model == .whisperLargeV3
                )
                modelRecommendationRow(
                    title: TranscriptionModel.parakeet.displayName,
                    detail: "English-only meetings",
                    size: TranscriptionModel.parakeet.sizeLabel,
                    isSelected: model == .parakeet
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("Pick a model in Settings → Models, then download it here or from that tab.")
                .font(.system(size: 10))
                .foregroundStyle(Color.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button("Download \(model.displayName)") {
                Task { await transcriptionEngine.downloadModel(model) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accent1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accent1.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let error = transcriptionEngine.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.recordRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 28))
                .foregroundStyle(Color.fg3)
            Text("No active session")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.fg2)
            Text("Start a call capture or voice memo\nto begin transcribing.")
                .font(.system(size: 11))
                .foregroundStyle(Color.fg3)
                .multilineTextAlignment(.center)
            Text("Model: \(settings.transcriptionModel.displayName)")
                .font(.system(size: 10))
                .foregroundStyle(Color.fg3)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Waveform + Countdown Section

    private var waveformSection: some View {
        VStack(spacing: 0) {
            if isRunning {
                statusIndicator
            }
            WaveformView(
                isRecording: isRunning,
                micLevel: micLevel,
                sysLevel: sysLevel,
                isMicMuted: transcriptionEngine.isMicMuted,
                isSysMuted: transcriptionEngine.isSysMuted,
                onToggleMicMute: { transcriptionEngine.isMicMuted.toggle() },
                onToggleSysMute: { transcriptionEngine.isSysMuted.toggle() }
            )
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if transcriptionEngine.isPaused {
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10))
                Text("Paused")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.fg3)
            .padding(.vertical, 4)
        } else if transcriptionEngine.isSpeechDetected {
            TypingEllipsis()
                .padding(.vertical, 4)
        } else {
            silenceTimeoutDisplay
        }
    }

    // MARK: - Control Bar Section

    private var controlBarSection: some View {
        ControlBar(
            isRecording: isRunning,
            isPaused: transcriptionEngine.isPaused,
            modelsReady: transcriptionEngine.canStartRecording,
            activeSessionType: activeSessionType,
            sessionLanguage: $settings.sessionTranscriptionLanguage,
            sessionTranscriptName: $settings.sessionTranscriptNameDraft,
            suggestedMeetingTitle: suggestedMeetingTitle,
            onApplySuggestedMeetingTitle: applySuggestedMeetingTitle,
            recordingSessionLanguage: recordingSessionLanguage,
            recordingSessionTitle: recordingSessionTitle,
            transcriptionModel: settings.transcriptionModel,
            audioLevel: audioLevel,
            detectedApp: detectedAppName,
            silenceSeconds: silenceSeconds,
            statusMessage: transcriptionEngine.isDownloadingSelectedModel ? nil : transcriptionEngine.assetStatus,
            errorMessage: transcriptionEngine.lastError,
            onStartCallCapture: { startSession(type: .callCapture) },
            onStartVoiceMemo: { startSession(type: .voiceMemo) },
            onStop: stopSession,
            onPause: pauseFromMenu,
            onResume: resumeFromMenu,
            isPreRollActive: preRollPhase != nil,
            showNoMicSignalHint: showNoMicSignalHint,
            isRestartingCapture: isRestartingCapture,
            onRestartCapture: restartCaptureFromUI
        )
    }

    // MARK: - Silence Timeout Display

    private var silenceTimeoutDisplay: some View {
        let remaining = max(0, settings.silenceTimeoutSeconds - silenceSeconds)
        let isUrgent = remaining <= 30
        let isActive = silenceSeconds > 0
        return Button {
            silenceSeconds = 0
        } label: {
            Text(formatTime(remaining))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isUrgent ? Color.red : (isActive ? Color.primary : Color.secondary))
                .opacity(isActive ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 3)
    }

    // MARK: - Save Banner

    private func saveBanner(url: URL) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accent1.opacity(0.15))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accent1)
                )
            Text("Saved to \(url.lastPathComponent)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.fg1)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Show Transcript") {
                SummarizeView.openWindow(for: url, settings: settings, logger: transcriptLogger)
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accent1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Helpers

    private var isRunning: Bool {
        transcriptionEngine.isRunning
    }

    private func formatTime(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    // MARK: - Actions

    private func refreshSuggestedMeetingTitle(for sessionType: SessionType) {
        guard !isRunning else { return }
        suggestedMeetingTitle = meetingProfileStore.suggestedTitle(for: Date(), sessionType: sessionType)
    }

    private func applySuggestedMeetingTitle() {
        guard let title = suggestedMeetingTitle else { return }
        settings.suppressSessionTranscriptNameDraftTracking = true
        settings.sessionTranscriptNameDraft = title
        settings.suppressSessionTranscriptNameDraftTracking = false
        settings.sessionTranscriptNameUserEdited = true
    }

    /// Call Capture / file import: use meeting rule title when the name field is empty (manual or auto-start).
    private func applySuggestedMeetingTitleIfNameEmpty(for sessionType: SessionType, at instant: Date = Date()) {
        guard sessionType == .callCapture || sessionType == .fileImport else { return }
        let draft = settings.sessionTranscriptNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.isEmpty else { return }
        guard let title = meetingProfileStore.suggestedTitle(for: instant, sessionType: sessionType) else { return }
        settings.suppressSessionTranscriptNameDraftTracking = true
        settings.sessionTranscriptNameDraft = title
        settings.suppressSessionTranscriptNameDraftTracking = false
        settings.sessionTranscriptNameUserEdited = false
        suggestedMeetingTitle = title
    }

    private func clearSessionNameDraftAfterMeeting() {
        settings.suppressSessionTranscriptNameDraftTracking = true
        settings.sessionTranscriptNameDraft = ""
        settings.suppressSessionTranscriptNameDraftTracking = false
        settings.sessionTranscriptNameUserEdited = false
        refreshSuggestedMeetingTitle(for: .callCapture)
    }

    private func startSession(type: SessionType) {
        guard preRollPhase == nil else { return }
        guard transcriptionEngine.canStartRecording else { return }
        guard settings.hasAcknowledgedDisclaimer else {
            transcriptionEngine.lastError = "Please complete the setup wizard and acknowledge the legal disclaimer before recording."
            return
        }
        transcriptStore.clear()
        silenceSeconds = 0
        sessionElapsed = 0
        savedFileURL = nil
        bannerDismissTask?.cancel()

        // Determine output folder and app bundle ID based on session type
        let outputPath: String
        let sourceApp: String
        var appBundleID: String?
        var resolvedAppName: String?

        switch type {
        case .callCapture:
            outputPath = settings.vaultMeetingsPath
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier,
               let appName = conferencingBundleIDs[bundleID] {
                sourceApp = appName
                appBundleID = bundleID
                resolvedAppName = appName
            } else {
                sourceApp = "Call"
            }
        case .voiceMemo:
            outputPath = settings.vaultVoicePath
            sourceApp = "Voice Memo"
        case .fileImport:
            return  // handled by startFileSession(url:)
        }

        if type == .callCapture {
            applySuggestedMeetingTitleIfNameEmpty(for: .callCapture)
        }

        let sessionLanguage = settings.sessionTranscriptionLanguage
        let customTitle = settings.sessionTranscriptNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleForSession = customTitle.isEmpty ? nil : customTitle

        Task {
            preRollPhase = .gettingReady
            transcriptionEngine.beginSessionPrepare()
            defer {
                transcriptionEngine.endSessionPrepare()
                if preRollPhase == .gettingReady { preRollPhase = nil }
            }

            transcriptionEngine.lastError = nil
            await transcriptionEngine.warmUpForRecording(
                sessionLanguage: sessionLanguage,
                sysVadThreshold: settings.sysVadThreshold,
                context: .sessionStart
            )

            await sessionStore.startSession()
            do {
                try await transcriptLogger.startSession(
                    sourceApp: sourceApp,
                    vaultPath: outputPath,
                    sessionType: type,
                    transcriptionLanguage: sessionLanguage,
                    customTitle: titleForSession
                )
            } catch {
                await sessionStore.endSession()
                transcriptionEngine.lastError = error.localizedDescription
                preRollPhase = nil
                return
            }

            if type == .callCapture {
                await transcriptionEngine.start(
                    sessionLanguage: sessionLanguage,
                    inputDeviceID: settings.inputDeviceID,
                    appBundleID: appBundleID,
                    sysVadThreshold: settings.sysVadThreshold
                )
            } else {
                await transcriptionEngine.start(
                    sessionLanguage: sessionLanguage,
                    inputDeviceID: settings.inputDeviceID,
                    sysVadThreshold: settings.sysVadThreshold,
                    captureSystemAudio: false
                )
            }

            guard transcriptionEngine.isRunning else {
                await sessionStore.endSession()
                preRollPhase = nil
                return
            }

            activeSessionType = type
            detectedAppName = resolvedAppName
            recordingSessionLanguage = sessionLanguage
            recordingSessionTitle = titleForSession
            recordingState.isRecording = true
            recordingState.isPaused = false
            preRollPhase = nil

            if settings.notificationSoundEnabled { NSSound(named: .init("Tink"))?.play() }
        }
    }

    private func startFileSession(url: URL) {
        guard !isRunning else { return }
        guard settings.hasAcknowledgedDisclaimer else {
            transcriptionEngine.lastError = "Please complete the setup wizard and acknowledge the legal disclaimer before transcribing."
            return
        }
        if settings.notificationSoundEnabled { NSSound(named: .init("Tink"))?.play() }
        transcriptStore.clear()
        silenceSeconds = 0
        sessionElapsed = 0
        savedFileURL = nil
        bannerDismissTask?.cancel()
        activeSessionType = .fileImport
        applySuggestedMeetingTitleIfNameEmpty(for: .fileImport)
        let sessionLanguage = settings.sessionTranscriptionLanguage
        let customTitle = settings.sessionTranscriptNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleForSession = customTitle.isEmpty ? nil : customTitle

        Task {
            transcriptionEngine.lastError = nil
            await sessionStore.startSession()
            do {
                try await transcriptLogger.startSession(
                    sourceApp: url.deletingPathExtension().lastPathComponent,
                    vaultPath: settings.vaultVoicePath,
                    sessionType: .fileImport,
                    transcriptionLanguage: sessionLanguage,
                    customTitle: titleForSession
                )
            } catch {
                await sessionStore.endSession()
                activeSessionType = nil
                transcriptionEngine.lastError = error.localizedDescription
                return
            }
            recordingSessionLanguage = sessionLanguage
            recordingSessionTitle = titleForSession
            recordingState.isRecording = true
            recordingState.isPaused = false
            await transcriptionEngine.startFileTranscription(url: url, sessionLanguage: sessionLanguage)
        }
    }

    private func pauseFromMenu() {
        Task {
            await transcriptionEngine.pause()
            recordingState.isPaused = transcriptionEngine.isPaused
        }
    }

    private func resumeFromMenu() {
        transcriptionEngine.resume()
        recordingState.isPaused = false
    }

    private func stopSession() {
        if settings.notificationSoundEnabled { NSSound(named: .init("Tink"))?.play() }
        let wasCallCapture = activeSessionType == .callCapture
        let wasFileImport = activeSessionType == .fileImport
        let shouldClearMeetingName = wasCallCapture || wasFileImport
        activeSessionType = nil
        detectedAppName = nil
        recordingSessionLanguage = nil
        recordingSessionTitle = nil
        silenceSeconds = 0
        recordingState.isRecording = false
        recordingState.isPaused = false

        Task {
            await transcriptionEngine.stop()
            await sessionStore.endSession()
            await transcriptLogger.endSession()

            if wasCallCapture || wasFileImport {
                transcriptionEngine.assetStatus = "Identifying speakers..."
                let segments: [(speakerId: String, startTime: Float, endTime: Float)]?
                if wasCallCapture {
                    segments = await transcriptionEngine.runPostSessionDiarization()
                } else {
                    segments = await transcriptionEngine.runFileTranscriptionDiarization()
                }

                if let segments {
                    transcriptionEngine.assetStatus = "Rewriting transcript..."
                    let speakerMap: [String: String]
                    if wasCallCapture {
                        speakerMap = await transcriptLogger.rewriteWithDiarization(segments: segments)
                    } else {
                        speakerMap = await transcriptLogger.rewriteFileTranscriptWithDiarization(segments: segments)
                    }

                    let genericLabels = Set(speakerMap.values).sorted {
                        let n0 = Int($0.components(separatedBy: " ").last ?? "") ?? 0
                        let n1 = Int($1.components(separatedBy: " ").last ?? "") ?? 0
                        return n0 < n1
                    }
                    if !genericLabels.isEmpty {
                        transcriptionEngine.assetStatus = "Ready"

                        let previews = await transcriptLogger.speakerExcerpts(for: genericLabels)

                        let mapping: [String: String] = await withCheckedContinuation { continuation in
                            speakerLabelsForNaming = genericLabels
                            speakerPreviewsForNaming = previews
                            speakerNamingContinuation = continuation
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSpeakerNaming = true
                            }
                        }

                        if !mapping.isEmpty {
                            transcriptionEngine.assetStatus = "Applying names..."
                            await transcriptLogger.applySpeakerRenames(mapping)
                        }
                    }
                }
            }

            transcriptionEngine.assetStatus = "Finalizing..."
            let savedPath = await transcriptLogger.finalizeFrontmatter()

            transcriptionEngine.assetStatus = "Ready"

            if shouldClearMeetingName {
                clearSessionNameDraftAfterMeeting()
            }

            if activeSessionType == nil, let savedPath {
                savedFileURL = savedPath
                bannerDismissTask?.cancel()
                bannerDismissTask = Task {
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { savedFileURL = nil }
                }
            }
        }
    }

    private func handleNewUtterance() {
        guard let last = transcriptStore.utterances.last else { return }

        silenceSeconds = 0

        let speakerName = last.speaker == .you ? "You" : "Them"
        Task {
            await transcriptLogger.append(
                speaker: speakerName,
                text: last.text,
                timestamp: last.timestamp
            )
        }

        Task {
            await sessionStore.appendRecord(SessionRecord(
                speaker: last.speaker,
                text: last.text,
                timestamp: last.timestamp
            ))
        }
    }
}

// MARK: - Header wordmark

private struct HushSwedishHeaderWordmark: View {
    var highlighted: Bool

    private static let swedishBlue = Color(red: 0.0, green: 0.416, blue: 0.655)

    var body: some View {
        HStack(spacing: 0) {
            Text("Hush")
                .foregroundStyle(highlighted ? Color.accent1 : Color.fg1)
            Text("Swedish")
                .foregroundStyle(highlighted ? Color.accent1 : Self.swedishBlue)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
    }
}

// MARK: - Pre-roll countdown

private enum PreRollPhase: Equatable {
    case gettingReady
}

private struct PreRollOverlay: View {
    let phase: PreRollPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                switch phase {
                case .gettingReady:
                    Text("Getting ready…")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Wait until transcribing starts, then begin speaking.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: - Typing Ellipsis

private struct TypingEllipsis: View {
    @State private var dotCount = 1

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 3, height: 3)
                    .opacity(i < dotCount ? 0.6 : 0.2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                dotCount = dotCount % 3 + 1
            }
        }
    }
}

