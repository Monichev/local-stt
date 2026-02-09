import Foundation
import WhisperKit

struct TranscriptionResult {
    let text: String
    let language: String
}

final class TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isModelLoaded = false
    private(set) var currentModelName: String = Constants.Model.defaultName

    /// When true, translates any language to English. When false, transcribes in the spoken language.
    var translateToEnglish = false

    /// Load (or reload) the Whisper model.
    func loadModel(modelName: String = Constants.Model.defaultName) async throws {
        isModelLoaded = false
        whisperKit = nil
        currentModelName = modelName
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalSTT")
        whisperKit = try await WhisperKit(
            model: "openai_whisper-\(modelName)",
            downloadBase: cacheURL,
            computeOptions: .init(
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU
            )
        )
        isModelLoaded = true
    }

    /// Transcribe a Float32 audio buffer (16kHz mono) to text
    func transcribe(audioBuffer: [Float]) async throws -> TranscriptionResult {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            task: translateToEnglish ? .translate : .transcribe,
            language: nil,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            topK: 5,
            usePrefillPrompt: true,
            detectLanguage: true,
            skipSpecialTokens: true,
            clipTimestamps: []
        )

        let result = try await whisperKit.transcribe(
            audioArray: audioBuffer,
            decodeOptions: options
        )

        let text = result.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let language = result.first?.language ?? "en"

        // Filter common Whisper hallucinations
        if isHallucination(text) {
            return TranscriptionResult(text: "", language: language)
        }

        return TranscriptionResult(text: text, language: language)
    }

    /// Detect common Whisper hallucination patterns
    private func isHallucination(_ text: String) -> Bool {
        let hallucinations = [
            "thank you for watching",
            "thanks for watching",
            "subscribe",
            "[BLANK_AUDIO]",
            "you",
            "...",
        ]

        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check exact hallucination matches
        if hallucinations.contains(where: { lower == $0 }) {
            return true
        }

        // Check repeated phrases (same phrase 3+ times)
        let words = lower.split(separator: " ")
        if words.count >= 6 {
            let half = words.prefix(words.count / 2)
            let otherHalf = words.suffix(words.count / 2).prefix(half.count)
            if half.elementsEqual(otherHalf) {
                return true
            }
        }

        return false
    }

    enum TranscriptionError: LocalizedError {
        case modelNotLoaded
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                return "Whisper model is not loaded yet. Please wait for initialization."
            case .transcriptionFailed(let msg):
                return "Transcription failed: \(msg)"
            }
        }
    }
}
