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
        engine.inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) {
            [self] buffer, _ in
            let samples = resample(buffer)
            guard !samples.isEmpty else { return }
            queue.async {
                guard !self.muted else { return }
                self.onFrame(samples)
            }
        }
        try engine.start()
    }

    public func stop() { engine.stop(); engine.inputNode.removeTap(onBus: 0) }

    public func setMuted(_ value: Bool) { queue.async { self.muted = value } }

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
