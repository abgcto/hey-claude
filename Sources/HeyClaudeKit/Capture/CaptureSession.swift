import Foundation

/// Pre-roll + endpoint capture state machine (promoted from the Phase 1 spike).
/// While listening, retains a rolling lookback. On `fire()` it seeds the
/// captured buffer with that lookback (so a command spoken in the same breath
/// as the wake word is not lost), then accumulates until the speaker endpoints
/// (VAD trailing silence) or a safety cap, then calls `onUtterance`.
///
/// Not thread-safe by itself; the owner (AudioCapture/VoiceSession) drives it
/// on a single serial queue.
public final class CaptureSession {
    public enum State { case listening, capturing }

    private let sampleRate: Double
    private let prerollCap: Int
    private let postFireMax: Int
    private let vad: VoiceActivityDetector
    private let onUtterance: ([Float]) -> Void

    public private(set) var state: State = .listening
    private var preroll: [Float] = []
    private var captured: [Float] = []
    private var postFireCount = 0

    public init(sampleRate: Double = 16000,
                prerollSeconds: Double = 2.0,
                postFireMaxSeconds: Double = 2.5,
                vad: VoiceActivityDetector = VoiceActivityDetector(),
                onUtterance: @escaping ([Float]) -> Void) {
        self.sampleRate = sampleRate
        self.prerollCap = Int(sampleRate * prerollSeconds)
        self.postFireMax = Int(sampleRate * postFireMaxSeconds)
        self.vad = vad
        self.onUtterance = onUtterance
    }

    /// Feed a frame while in the listening state (maintains lookback).
    public func feedWhileListening(_ frame: [Float]) {
        preroll.append(contentsOf: frame)
        if preroll.count > prerollCap { preroll.removeFirst(preroll.count - prerollCap) }
    }

    /// Transition to capturing; seed with the retained lookback.
    public func fire() {
        captured = preroll
        preroll.removeAll(keepingCapacity: true)
        postFireCount = 0
        state = .capturing
    }

    /// Feed a frame while capturing; emits the utterance + returns to listening
    /// once the speaker endpoints or the safety cap is hit.
    public func feedWhileCapturing(_ frame: [Float]) {
        captured.append(contentsOf: frame)
        postFireCount += frame.count
        if vad.hasEndpointed(captured, sampleRate: Int(sampleRate)) || postFireCount >= postFireMax {
            let clip = captured
            captured.removeAll(keepingCapacity: true)
            postFireCount = 0
            state = .listening
            onUtterance(clip)
        }
    }
}
