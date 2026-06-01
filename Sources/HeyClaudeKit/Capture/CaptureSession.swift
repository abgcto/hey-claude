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
    /// True while a push-to-talk hold drives capture: VAD endpointing is
    /// suppressed (only `manualEndpoint()` or the safety cap ends it), so a pause
    /// mid-thought never truncates.
    public private(set) var isManual = false

    public init(sampleRate: Double = 16000,
                prerollSeconds: Double = 2.0,
                // Generous safety cap, NOT the normal terminator: the VAD's
                // silence endpoint ends a normal utterance whenever the speaker
                // pauses. This only bounds the clip if the (energy-based) VAD
                // never sees silence — e.g. a noisy room — so it can't capture
                // forever. Speak as long as you like; it ends when you stop.
                postFireMaxSeconds: Double = 30.0,
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

    /// Push-to-talk press. Like `fire()` but enters manual mode. Pre-roll is
    /// whatever lookback exists (empty on the muted→unmute path, since the mic
    /// was just re-acquired) — acceptable: the speaker holds the key *then*
    /// speaks, so the spoken words land in the post-fire stream.
    public func fireManual() {
        captured = preroll
        preroll.removeAll(keepingCapacity: true)
        postFireCount = 0
        isManual = true
        state = .capturing
    }

    /// Feed a frame while capturing; emits the utterance + returns to listening
    /// once the speaker endpoints or the safety cap is hit. In manual mode the
    /// VAD endpoint is suppressed — only the safety cap ends it here; the normal
    /// terminator is `manualEndpoint()` on key release.
    public func feedWhileCapturing(_ frame: [Float]) {
        captured.append(contentsOf: frame)
        postFireCount += frame.count
        let vadEndpoint = !isManual && vad.hasEndpointed(captured, sampleRate: Int(sampleRate))
        if vadEndpoint || postFireCount >= postFireMax {
            emitAndReset()
        }
    }

    /// Push-to-talk release: emit the captured clip immediately, regardless of
    /// VAD. No-op if not currently in a manual capture.
    public func manualEndpoint() {
        guard state == .capturing, isManual else { return }
        emitAndReset()
    }

    /// Push-to-talk cancel (Esc): drop the captured clip and return to listening
    /// WITHOUT emitting — the spoken audio is discarded, nothing transcribes or
    /// launches. No-op if not currently in a manual capture.
    public func manualCancel() {
        guard state == .capturing, isManual else { return }
        captured.removeAll(keepingCapacity: true)
        postFireCount = 0
        isManual = false
        state = .listening
    }

    private func emitAndReset() {
        let clip = captured
        captured.removeAll(keepingCapacity: true)
        postFireCount = 0
        isManual = false
        state = .listening
        onUtterance(clip)
    }
}
