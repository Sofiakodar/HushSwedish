import Foundation

/// Product name and app-specific paths. Model caches (FluidAudio, WhisperKit, MLX) stay on shared system paths.
enum AppIdentity {
    static let displayName = "HushSwedish"
    static let bundleIdentifier = "com.hushswedish.app"
    static let loggerSubsystem = bundleIdentifier

    static let defaultMeetingsVaultPath = "~/Documents/HushSwedish/Meetings"
    static let defaultVoiceVaultPath = "~/Documents/HushSwedish/Voice"

    static let applicationSupportDirectoryName = "HushSwedish"
    static let transcriptSourceTag = "source/hushswedish"

    /// Uppercase title in the main window header (replaces legacy HUSHSCRIBE wordmark).
    static var wordmark: String { displayName.uppercased() }

    /// Prefix for temp audio/log files (not user-visible).
    static let tempFileToken = "hushswedish"
}
