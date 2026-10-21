import FluidAudio
@preconcurrency import WhisperKit

/// Wraps WhisperKit for use as an ASR backend.
final class WhisperKitASRBackend: @unchecked Sendable, ASRBackend {
    let whisperKit: WhisperKit
    let languageCode: String

    init(_ whisperKit: WhisperKit, languageCode: String) {
        self.whisperKit = whisperKit
        self.languageCode = languageCode
    }

    func transcribe(_ samples: [Float], source: AudioSource, onPartial: (@Sendable (String) -> Void)?) async throws -> String {
        let options = DecodingOptions(
            task: .transcribe,
            language: languageCode,
            detectLanguage: false,
            withoutTimestamps: true
        )
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
