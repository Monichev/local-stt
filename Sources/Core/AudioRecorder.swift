import AVFoundation
import Foundation

final class AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    /// Target sample rate for Whisper models
    private let targetSampleRate: Double = 16000

    func startRecording() throws {
        audioBuffer = []

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputSampleRate: inputFormat.sampleRate)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopRecording() -> [Float] {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        bufferLock.lock()
        let result = audioBuffer
        audioBuffer = []
        bufferLock.unlock()

        return result
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, inputSampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Mix down to mono if stereo
        var monoSamples = [Float](repeating: 0, count: frameCount)
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        } else {
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                monoSamples[i] = sum / Float(channelCount)
            }
        }

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(inputSampleRate - targetSampleRate) > 1 {
            resampled = resample(monoSamples, from: inputSampleRate, to: targetSampleRate)
        } else {
            resampled = monoSamples
        }

        bufferLock.lock()
        audioBuffer.append(contentsOf: resampled)
        bufferLock.unlock()
    }

    /// Simple linear interpolation resampling
    private func resample(_ samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        let ratio = inputRate / outputRate
        let outputLength = Int(Double(samples.count) / ratio)
        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)
        for i in 0..<outputLength {
            let srcIndex = Double(i) * ratio
            let srcIndexInt = Int(srcIndex)
            let fraction = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - fraction) + samples[srcIndexInt + 1] * fraction
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }
        return output
    }
}
