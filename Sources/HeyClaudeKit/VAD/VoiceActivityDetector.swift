import Foundation

/// Energy-based VAD. Two jobs: gate stage-2 (containsSpeech) and endpoint the prompt (hasEndpointed).
public struct VoiceActivityDetector {
    public let energyThreshold: Float
    public let frameMs: Int
    public let hangoverMs: Int

    public init(energyThreshold: Float = 0.01, frameMs: Int = 20, hangoverMs: Int = 600) {
        self.energyThreshold = energyThreshold
        self.frameMs = frameMs
        self.hangoverMs = hangoverMs
    }

    private func rms(_ s: ArraySlice<Float>) -> Float {
        guard !s.isEmpty else { return 0 }
        let sum = s.reduce(Float(0)) { $0 + $1 * $1 }
        return (sum / Float(s.count)).squareRoot()
    }

    /// True if any frame's RMS exceeds the threshold.
    public func containsSpeech(_ samples: [Float], sampleRate: Int = 16000) -> Bool {
        let frame = max(1, sampleRate * frameMs / 1000)
        var i = samples.startIndex
        while i < samples.endIndex {
            let end = min(i + frame, samples.endIndex)
            if rms(samples[i..<end]) > energyThreshold { return true }
            i = end
        }
        return false
    }

    /// True if speech occurred and was then followed by >= hangoverMs of continuous silence.
    public func hasEndpointed(_ samples: [Float], sampleRate: Int = 16000) -> Bool {
        let frame = max(1, sampleRate * frameMs / 1000)
        let hangoverFrames = max(1, hangoverMs / frameMs)
        var sawSpeech = false
        var trailingSilent = 0
        var i = samples.startIndex
        while i < samples.endIndex {
            let end = min(i + frame, samples.endIndex)
            if rms(samples[i..<end]) > energyThreshold {
                sawSpeech = true; trailingSilent = 0
            } else if sawSpeech {
                trailingSilent += 1
            }
            i = end
        }
        return sawSpeech && trailingSilent >= hangoverFrames
    }
}
