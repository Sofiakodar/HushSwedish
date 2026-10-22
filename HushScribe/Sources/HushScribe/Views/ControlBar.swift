import SwiftUI

struct PulsingDot: View {
    var size: CGFloat = 10
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.recordRed)
            .frame(width: size, height: size)
            .opacity(pulse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

struct ControlBar: View {
    let isRecording: Bool
    let isPaused: Bool
    let modelsReady: Bool
    let activeSessionType: SessionType?
    @Binding var sessionLanguage: SessionTranscriptionLanguage
    @Binding var sessionTranscriptName: String
    var suggestedMeetingTitle: String? = nil
    var onApplySuggestedMeetingTitle: (() -> Void)? = nil
    let recordingSessionLanguage: SessionTranscriptionLanguage?
    let recordingSessionTitle: String?
    let transcriptionModel: TranscriptionModel
    let audioLevel: Float
    let detectedApp: String?
    let silenceSeconds: Int
    let statusMessage: String?
    let errorMessage: String?
    let onStartCallCapture: () -> Void
    let onStartVoiceMemo: () -> Void
    let onStop: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    var isPreRollActive: Bool = false
    var showNoMicSignalHint: Bool = false
    var isRestartingCapture: Bool = false
    let onRestartCapture: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.recordRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            if let status = statusMessage, status != "Ready" {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.accent1)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fg2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            if isRecording {
                HStack(spacing: 10) {
                    Button(action: onStop) {
                        HStack(spacing: 10) {
                            PulsingDot(size: 6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Stop")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.fg1)
                                Text(activeSessionLabel)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.fg2)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.accent1.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent1.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(".", modifiers: .command)

                    Button(action: isPaused ? onResume : onPause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.fg1)
                            .frame(width: 44, height: 44)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if silenceSeconds >= 90 {
                    Text("Silence — auto-stop in \(120 - silenceSeconds)s")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                captureRecoverySection
            } else {
                VStack(spacing: 8) {
                    sessionNameField
                    sessionLanguagePicker
                    HStack(spacing: 10) {
                    Button(action: onStartCallCapture) {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(modelsReady ? Color.fg1 : Color.fg3)
                            Text("Call Capture")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(modelsReady ? Color.fg1 : Color.fg3)
                            Text("⌘R")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.fg3)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!modelsReady || isPreRollActive)
                    .keyboardShortcut("r", modifiers: .command)

                    Button(action: onStartVoiceMemo) {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(modelsReady ? Color.fg1 : Color.fg3)
                            Text("Voice Memo")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(modelsReady ? Color.fg1 : Color.fg3)
                            Text("⌘⇧R")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.fg3)
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!modelsReady || isPreRollActive)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }

    private var captureRecoverySection: some View {
        let emphasized = showNoMicSignalHint || isRestartingCapture

        return Button(action: onRestartCapture) {
            HStack(alignment: .top, spacing: 6) {
                Group {
                    if isRestartingCapture {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: showNoMicSignalHint ? "exclamationmark.triangle.fill" : "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .frame(width: 14, height: 14)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRestartingCapture ? "Restarting capture…" : "Restart capture if mic stays flat")
                        .font(.system(size: 10, weight: emphasized ? .semibold : .medium))
                        .foregroundStyle(emphasized ? Color.orange : Color.fg3)
                        .multilineTextAlignment(.leading)

                    if !isRestartingCapture, emphasized {
                        Text("No mic signal detected — tap to reconnect audio.")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(emphasized ? Color.orange.opacity(0.1) : Color.fg3.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(emphasized ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRestartingCapture)
        .help("Restarts the mic and system-audio pipelines without stopping the session. Also if system audio or transcript stops updating.")
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var sessionNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name (optional)", text: $sessionTranscriptName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .disabled(!modelsReady)

            if let suggested = suggestedMeetingTitle, !suggested.isEmpty {
                let current = sessionTranscriptName.trimmingCharacters(in: .whitespacesAndNewlines)
                let isSelected = current == suggested
                HStack(spacing: 6) {
                    Text("Suggested")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button {
                        onApplySuggestedMeetingTitle?()
                    } label: {
                        Text(suggested)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isSelected ? Color.accent1.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.accent1.opacity(0.45) : Color(NSColor.separatorColor)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!modelsReady)
                }
            }

            Text("Vault: \(transcriptNameExample)_Your_name.md")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var transcriptNameExample: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private var sessionLanguagePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Language", selection: $sessionLanguage) {
                ForEach(SessionTranscriptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if transcriptionModel == .parakeet {
                Text("Parakeet auto-detects language. This setting applies to Whisper models.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var activeSessionLabel: String {
        let languageSuffix: String
        if let recordingSessionLanguage {
            languageSuffix = " · \(recordingSessionLanguage.displayName)"
        } else {
            languageSuffix = ""
        }
        if let title = recordingSessionTitle, !title.isEmpty {
            return "\(title)\(languageSuffix)"
        }
        switch activeSessionType {
        case .callCapture:
            if let app = detectedApp {
                return "Call Capture · \(app)\(languageSuffix)"
            }
            return "Call Capture\(languageSuffix)"
        case .voiceMemo:
            return "Voice Memo\(languageSuffix)"
        case .fileImport:
            return "File Import\(languageSuffix)"
        case nil:
            return "Recording\(languageSuffix)"
        }
    }
}
