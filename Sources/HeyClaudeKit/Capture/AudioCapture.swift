@preconcurrency import AVFoundation
import Foundation

/// Live microphone capture → 16 kHz mono Float frames on a serial queue.
/// `@unchecked Sendable`: all mutable state is confined to `queue`; the tap
/// closure captures only `self` (never a main-actor global) — the Phase 1
/// rule that avoids the real-time-thread isolation crash.
public final class AudioCapture: @unchecked Sendable {
    public enum CaptureError: Swift.Error { case audioFormat }

    private let engine = AVAudioEngine()
    private let inputFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let queue = DispatchQueue(label: "heyclaude.audiocapture")
    private let onFrame: ([Float]) -> Void
    private var muted = false

    /// onFrame is invoked on a private serial queue with 16 kHz mono samples.
    public init(onFrame: @escaping ([Float]) -> Void) throws {
        self.onFrame = onFrame
        self.inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inputFormat, to: target) else {
            throw CaptureError.audioFormat
        }
        self.targetFormat = target
        self.converter = conv
    }

    public func start() throws {
        installTap()
        try engine.start()
    }

    public func stop() { engine.stop(); engine.inputNode.removeTap(onBus: 0) }

    /// Installs the input tap. Each delivered buffer is resampled on the realtime
    /// thread, then handed to `onFrame` on the serial queue. The `muted` flag is a
    /// belt-and-suspenders gate for any frame already in flight when mute lands;
    /// the real release is `setMuted` tearing the engine down (see below).
    private func installTap() {
        engine.inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) {
            [self] buffer, _ in
            let samples = resample(buffer)
            guard !samples.isEmpty else { return }
            queue.async {
                guard !self.muted else { return }
                self.onFrame(samples)
            }
        }
    }

    /// Mute **releases the microphone at the OS level**, it does not merely drop
    /// frames: it stops the engine and removes the tap, so macOS tears down the
    /// input stream — the orange mic indicator turns off and other apps can take
    /// the device. Unmute reinstalls the tap and restarts the engine.
    ///
    /// Returns the resulting *live* state (`true` = mic is capturing). On unmute a
    /// failed `engine.start()` returns `false` so the caller stays truthful — it
    /// must not claim a live mic the OS never re-granted. Mirrors the wake-engine
    /// rebuild rule: an error must never silently leave the app deaf.
    ///
    /// Engine control runs on the caller (the main actor, same as `start()`/`stop()`)
    /// to keep a single serialization domain; only the `muted` flag flips on the
    /// audio queue, synchronized so an in-flight frame can't slip through.
    @discardableResult
    public func setMuted(_ value: Bool) -> Bool {
        if value {
            if engine.isRunning {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
            queue.sync { muted = true }
            return false
        }
        if !engine.isRunning {
            do {
                installTap()
                try engine.start()
            } catch {
                Log.audio.error("unmute failed; mic did not restart: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        queue.sync { muted = false }
        return true
    }

    private func resample(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = 16000.0 / inputFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return [] }
        final class Once: @unchecked Sendable { var fed = false }
        let once = Once()
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if once.fed { status.pointee = .noDataNow; return nil }
            once.fed = true; status.pointee = .haveData; return buffer
        }
        guard err == nil, let ch = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }
}
