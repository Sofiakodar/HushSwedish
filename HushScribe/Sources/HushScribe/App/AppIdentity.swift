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
}
