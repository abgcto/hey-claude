@preconcurrency import AVFoundation

public enum AudioSamples {
    public enum Error: Swift.Error { case readFailed }

    /// Loads a WAV file as mono Float32 PCM resampled to 16 kHz.
    public static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000, channels: 1, interleaved: false)!

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw Error.readFailed
        }
        let inBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuffer)

        let ratio = targetFormat.sampleRate / file.processingFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1
        let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity)!

        // One-shot feed flag in a reference box: AVAudioConverter calls this
        // block synchronously, but a captured `var` trips the Sendable-closure
        // warning, so use a reference (matches AudioCapture).
        final class Once: @unchecked Sendable { var consumed = false }
        let once = Once()
        var convError: NSError?
        converter.convert(to: outBuffer, error: &convError) { _, status in
            if once.consumed { status.pointee = .noDataNow; return nil }
            once.consumed = true; status.pointee = .haveData; return inBuffer
        }
        if let convError { throw convError }

        let ptr = outBuffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuffer.frameLength)))
    }
}
