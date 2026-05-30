import Foundation

/// Records ONE spoken utterance from the mic for wake-word enrollment.
///
/// Mirrors the live pipeline so samples are representative: it keeps a rolling
/// pre-roll while listening, detects speech onset (VAD), then `fire()`s — seeding
/// the captured clip with the pre-roll so the leading "hey" is never lost to mic
/// warmup. Ends on the same silence endpoint the real pipeline uses. Delivers the
/// clip once, then stops. One recorder = one utterance.
///
/// `@unchecked Sendable`: capture state is touched only on `AudioCapture`'s serial
/// queue; `finished`/`audio` (read across the stop hop) are lock-guarded.
public final class EnrollmentRecorder: @unchecked Sendable {
    private let vad: VoiceActivityDetector
    private let maxSeconds: Double
    private let onsetWindow: Int      // samples of recent audio used for onset detection
    private let lock = NSLock()
    private var audio: AudioCapture?
    private var finished = false

    // Serial-queue-confined (only touched in onFrame):
    private var didFire = false
    private var recent: [Float] = []

    public init(endpointSilenceMs: Int = 800, maxSeconds: Double = 8.0) {
        self.vad = VoiceActivityDetector(hangoverMs: endpointSilenceMs)
        self.maxSeconds = maxSeconds
        self.onsetWindow = 16000 / 4   // 0.25s
    }

    /// Start the mic and deliver the captured clip once the speaker endpoints (or
    /// the cap is hit). `onSpeechStart` fires the moment speech is detected (for a
    /// "now talking" UI); `onClip` delivers the finished clip. Both run on the
    /// audio queue — hop to main yourself.
    public func record(onSpeechStart: (@Sendable () -> Void)? = nil,
                       onClip: @escaping @Sendable ([Float]) -> Void) throws {
        let capture = CaptureSession(prerollSeconds: 1.5, postFireMaxSeconds: maxSeconds,
                                     vad: vad, onUtterance: { [weak self] clip in
            guard let self else { return }
            self.lock.lock()
            let already = self.finished; self.finished = true
            self.lock.unlock()
            guard !already else { return }
            onClip(clip)
            DispatchQueue.main.async { [weak self] in self?.stop() }
        })
        let vad = self.vad
        let onsetWindow = self.onsetWindow
        let audio = try AudioCapture(onFrame: { [weak self] frame in
            guard let self else { return }
            if !self.didFire {
                capture.feedWhileListening(frame)     // maintain pre-roll (retains onset)
                self.recent.append(contentsOf: frame)
                if self.recent.count > onsetWindow {
                    self.recent.removeFirst(self.recent.count - onsetWindow)
                }
                if vad.containsSpeech(self.recent) {
                    self.didFire = true
                    capture.fire()                    // seed captured with the pre-roll
                    onSpeechStart?()                  // "now talking" → equalizer
                }
            } else {
                capture.feedWhileCapturing(frame)     // endpoint → onUtterance
            }
        })
        lock.lock(); self.audio = audio; lock.unlock()
        try audio.start()
    }

    /// Stop the mic (idempotent).
    public func stop() {
        lock.lock(); let a = audio; audio = nil; lock.unlock()
        a?.stop()
    }
}
