import Foundation
import Observation

@Observable
@MainActor
final class RecordingState {
    var isRecording = false
    var isPaused = false
}

extension Notification.Name {
    private static let prefix = AppIdentity.bundleIdentifier

    static let appStartCallCapture = Notification.Name("\(prefix).startCallCapture")
    static let appStartVoiceMemo = Notification.Name("\(prefix).startVoiceMemo")
    static let appStopRecording = Notification.Name("\(prefix).stopRecording")
    static let appPauseRecording = Notification.Name("\(prefix).pauseRecording")
    static let appResumeRecording = Notification.Name("\(prefix).resumeRecording")
    static let appOpenSummarize = Notification.Name("\(prefix).openSummarize")
    static let appClosePopover = Notification.Name("\(prefix).closePopover")
    static let appShowOnboarding = Notification.Name("\(prefix).showOnboarding")
}
