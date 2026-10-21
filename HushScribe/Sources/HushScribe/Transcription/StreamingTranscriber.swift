@preconcurrency import AVFoundation
import FluidAudio
import os

// VAD + ASR pipeline
final class StreamingTranscriber: @unchecked Sendable {
    private let asrBackend: any ASRBackend
    private let vadManager: VadManager
    private let speaker: Speaker
    private let audioSource: AudioSource
    private let onSpeechStart: (@Sendable () -> Void)?
    private let onPartial: @Sendable (String) -> Void
    private let onFinal: @Sendable (String) -> Void
    private let log = Logger(subsystem: AppIdentity.loggerSubsystem, category: "StreamingTranscriber")

    /// Resampler from source format to 16kHz mono Float32.
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    private struct BufferedSpeech: Sendable {
        var speechSamples: [Float] = []
        var vadBuffer: [Float] = []
        var isSpeaking = false
    }

    private let _buffered = OSAllocatedUnfairLock<BufferedSpeech>(uncheckedState: BufferedSpeech())
    private let asrQueue = ASRSerialQueue()

    init(
        asrBackend: any ASRBackend,
        vadManager: VadManager,
        speaker: Speaker,
        audioSource: AudioSource = .microphone,
        onSpeechStart: (@Sendable () -> Void)? = nil,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void
    ) {
        self.asrBackend = asrBackend
        self.vadManager = vadManager
        self.speaker = speaker
        self.audioSource = audioSource
        self.onSpeechStart = onSpeechStart
        self.onPartial = onPartial
        self.onFinal = onFinal
    }

    /// Silero VAD expects chunks of 4096 samples (256ms at 16kHz).
    private static let vadChunkSize = 4096
    /// Flush speech for transcription every ~6 seconds (96,000 samples at 16kHz).
    private static let flushInterval = 96_000
    /// Minimum speech length for a normal VAD end (~0.5s at 16kHz).
    private static let minSpeechSamples = 8000
    /// Lower bar when user pauses/stops so short trailing phrases still transcribe (~0.25s).
    private static let minTailSamples = 4000

    /// Transcribe buffered speech after pause/stop (call after capture is paused).
    func flushPendingSpeech(minSamples: Int = minTailSamples) async {
        let segment = _buffered.withLock { buffer -> [Float] in
            buffer.isSpeaking = false
            let segment = buffer.speechSamples
            buffer.speechSamples.removeAll(keepingCapacity: true)
            return segment
        }
        guard segment.count >= minSamples else { return }
        _ = await transcribeSegment(segment)
    }

    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    /// - Parameter offsetTracker: optional tracker updated with total 16 kHz samples consumed,
    ///   used during file transcription to compute file-relative utterance timestamps.
    /// Returns `true` if the loop exited due to fatal (repeated) errors.
    @discardableResult
    func run(stream: AsyncStream<AVAudioPCMBuffer>, offsetTracker: FileOffsetTracker? = nil) async -> Bool {
        var vadState = await vadManager.makeStreamState()
        var bufferCount = 0
        var consecutiveErrors = 0
        var totalVADSamples = 0

        outerLoop: for await buffer in stream {
            bufferCount += 1
            if bufferCount <= 3 {
                let fmt = buffer.format
                diagLog("[\(speaker.rawValue)] buffer #\(bufferCount): frames=\(buffer.frameLength) sr=\(fmt.sampleRate) ch=\(fmt.channelCount) interleaved=\(fmt.isInterleaved) common=\(fmt.commonFormat.rawValue)")
            }

            guard let samples = extractSamples(buffer) else { continue }

            if bufferCount <= 3 {
                let maxVal = samples.max() ?? 0
                diagLog("[\(speaker.rawValue)] samples: count=\(samples.count) max=\(maxVal)")
            }

            _buffered.withLock { $0.vadBuffer.append(contentsOf: samples) }

            while true {
                let chunk: [Float]? = _buffered.withLock { buffer -> [Float]? in
                    guard buffer.vadBuffer.count >= Self.vadChunkSize else { return nil }
                    let chunk = Array(buffer.vadBuffer.prefix(Self.vadChunkSize))
                    buffer.vadBuffer.removeFirst(Self.vadChunkSize)
                    return chunk
                }
                guard let chunk else { break }

                totalVADSamples += Self.vadChunkSize
                offsetTracker?.set(totalVADSamples)

                do {
                    let result = try await vadManager.processStreamingChunk(
                        chunk,
                        state: vadState,
                        config: .default,
                        returnSeconds: true,
                        timeResolution: 2
                    )
                    vadState = result.state
                    consecutiveErrors = 0

                    if let event = result.event {
                        switch event.kind {
                        case .speechStart:
                            _buffered.withLock { buffer in
                                buffer.isSpeaking = true
                                buffer.speechSamples.removeAll(keepingCapacity: true)
                            }
                            onSpeechStart?()
                            diagLog("[\(self.speaker.rawValue)] speech start")

                        case .speechEnd:
                            _buffered.withLock { $0.isSpeaking = false }
                            let segment = _buffered.withLock { buffer -> [Float] in
                                let segment = buffer.speechSamples
                                buffer.speechSamples.removeAll(keepingCapacity: true)
                                return segment
                            }
                            diagLog("[\(self.speaker.rawValue)] speech end, samples=\(segment.count)")
                            if segment.count > Self.minSpeechSamples {
                                if await !transcribeSegment(segment) {
                                    consecutiveErrors += 1
                                    if consecutiveErrors > 10 { break outerLoop }
                                } else {
                                    consecutiveErrors = 0
                                }
                            }

                        }
                    }

                    let shouldFlushMidSpeech = _buffered.withLock { buffer -> (Bool, [Float]) in
                        guard buffer.isSpeaking else { return (false, []) }
                        buffer.speechSamples.append(contentsOf: chunk)
                        guard buffer.speechSamples.count >= Self.flushInterval else {
                            return (false, [])
                        }
                        let segment = buffer.speechSamples
                        buffer.speechSamples.removeAll(keepingCapacity: true)
                        return (true, segment)
                    }

                    if shouldFlushMidSpeech.0 {
                        let segment = shouldFlushMidSpeech.1
                        if await !transcribeSegment(segment) {
                            consecutiveErrors += 1
                            if consecutiveErrors > 10 { break outerLoop }
                        } else {
                            consecutiveErrors = 0
                        }
                    }
                } catch {
                    log.error("VAD error: \(error.localizedDescription)")
                    consecutiveErrors += 1
                    if consecutiveErrors > 10 { break outerLoop }
                }
            }
        }

        await flushPendingSpeech(minSamples: Self.minSpeechSamples)

        return consecutiveErrors > 10
    }

    /// Returns `true` on success, `false` on ASR error.
    private func transcribeSegment(_ samples: [Float]) async -> Bool {
        await asrQueue.run {
            await self.transcribeSegmentUnlocked(samples)
        }
    }

    private func transcribeSegmentUnlocked(_ samples: [Float]) async -> Bool {
        do {
            let text = try await asrBackend.transcribe(samples, source: audioSource, onPartial: onPartial)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            log.info("[\(self.speaker.rawValue)] transcribed: \(trimmed.prefix(80))")
            onFinal(trimmed)
            return true
        } catch {
            log.error("ASR error: \(error.localizedDescription)")
            return false
        }
    }

    /// Extract [Float] samples from an AVAudioPCMBuffer, resampling if needed.
    private func extractSamples(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return nil }

        // Fast path: already Float32 at 16kHz (common for system audio from ScreenCaptureKit)
        if sourceFormat.commonFormat == .pcmFormatFloat32 && sourceFormat.sampleRate == 16000 {
            guard let channelData = buffer.floatChannelData else { return nil }
            if sourceFormat.channelCount == 1 {
                // Mono — direct copy
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            } else {
                // Multi-channel — take first channel only
                return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }
        }

        // Slow path: need to resample via AVAudioConverter
        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        final class ConsumedFlag: @unchecked Sendable { var value = false }
        let consumed = ConsumedFlag()
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            log.error("Resample error: \(error.localizedDescription)")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}

/// Ensures only one ASR request runs at a time (live loop + pause/stop flush).
private actor ASRSerialQueue {
    func run(_ body: @Sendable () async -> Bool) async -> Bool {
        await body()
    }
}
