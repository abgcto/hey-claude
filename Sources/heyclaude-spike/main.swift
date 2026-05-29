import AVFoundation
import Foundation
import HeyClaudeKit

// Live-mic spike: continuous wake-word streaming → capture → VAD gate →
// transcribe → route → print the resolved action.
//
// This is the Phase 2 manual spike. It is NOT run by CI or `swift test`; it
// needs a real microphone and human speech. `swift build` must stay clean.
//
//   say "hey claude"                  -> Action.launchCLI(prompt: nil)
//   say "hey claude code"             -> Action.launchCLI(prompt: nil)
//   say "hey claude <some prompt>"    -> Action.launchCLI(prompt: "<some prompt>")
//
// Pipeline stages (spec §3–5):
//   1. WakeWordEngine.feed() on every mic frame (continuous stream, never
//      finished) until "hey claude" fires.
//   2. On fire, keep ~2.5s of trailing audio and gate it through the energy
//      VAD: no speech -> bare launch; speech -> transcribe + route.
//   3. ParakeetTranscriber turns the trailing speech into text.
//   4. CommandRouter resolves text -> Action.

// MARK: - Configuration

let sampleRate = 16000.0
let captureSeconds = 2.5
let captureSamples = Int(sampleRate * captureSeconds)

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // heyclaude-spike
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // repo root
let modelsDir = repoRoot.appendingPathComponent("Models")
let kwsDir = modelsDir
    .appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01")
let asrDir = modelsDir
    .appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8")
let keywordsFile = modelsDir.appendingPathComponent("keywords.txt")

// MARK: - Pipeline coordinator

/// Drives the continuous wake loop and the post-wake capture/transcribe/route
/// stages on a serial queue so mic frames are processed in order.
final class Spike {
    private let wake: WakeWordEngine
    private let transcriber: ParakeetTranscriber
    private let vad = VoiceActivityDetector()
    private let router = CommandRouter(
        defaultAction: .launchCLI(prompt: nil),
        phraseMap: [
            "code": .launchCLI(prompt: nil),
            "open the app": .openDesktopApp,
        ])

    /// Rolling buffer of post-wake audio, filled while `capturing` is true.
    private var capturing = false
    private var captured: [Float] = []

    init() throws {
        self.wake = try WakeWordEngine(modelDir: kwsDir, keywordsFile: keywordsFile)
        self.transcriber = try ParakeetTranscriber(modelDir: asrDir)
    }

    /// Process one frame of 16 kHz mono samples from the mic tap.
    func process(frame: [Float]) {
        if capturing {
            captured.append(contentsOf: frame)
            if captured.count >= captureSamples {
                finishCapture()
            }
            return
        }
        if wake.feed(frame) {
            print("\n[wake] \"hey claude\" detected — capturing \(captureSeconds)s …")
            capturing = true
            captured.removeAll(keepingCapacity: true)
        }
    }

    private func finishCapture() {
        capturing = false
        let clip = captured
        captured.removeAll(keepingCapacity: true)

        let action: Action
        if vad.containsSpeech(clip) {
            let transcript = (try? transcriber.transcribe(clip)) ?? ""
            print("[asr] transcript: \"\(transcript)\"")
            // `clip` is the audio AFTER the wake word, so the transcript is the
            // trailing command ("code", "refactor …") — the router maps it.
            action = router.route(transcript: transcript.isEmpty ? nil : transcript)
        } else {
            print("[vad] no trailing speech — bare launch")
            action = router.route(transcript: nil)
        }
        print("[route] -> \(action)")
        print("[listen] say \"hey claude\" …")
    }
}

// MARK: - Mic capture

print("heyclaude-spike \(HeyClaudeKit.version)")
print("sherpa-onnx links: \(HeyClaudeKit.sherpaLinks())")

let spike: Spike
do {
    spike = try Spike()
} catch {
    FileHandle.standardError.write("failed to init pipeline: \(error)\n".data(using: .utf8)!)
    exit(1)
}

let engine = AVAudioEngine()
let input = engine.inputNode
let inputFormat = input.outputFormat(forBus: 0)

// Target: 16 kHz mono Float32, matching the models.
guard let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: sampleRate, channels: 1, interleaved: false),
    let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
    FileHandle.standardError.write("could not build 16 kHz converter\n".data(using: .utf8)!)
    exit(1)
}

/// Convert a hardware-format buffer to 16 kHz mono Float samples.
func toModelSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
    let ratio = sampleRate / inputFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
    guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
        return []
    }
    var fed = false
    var err: NSError?
    converter.convert(to: out, error: &err) { _, status in
        if fed { status.pointee = .noDataNow; return nil }
        fed = true; status.pointee = .haveData; return buffer
    }
    guard err == nil, let ch = out.floatChannelData else { return [] }
    return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
}

// Serial queue so frames are handled in capture order without blocking the
// audio thread.
let work = DispatchQueue(label: "heyclaude.spike.pipeline")

input.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { buffer, _ in
    let samples = toModelSamples(buffer)
    guard !samples.isEmpty else { return }
    work.async { spike.process(frame: samples) }
}

do {
    try engine.start()
} catch {
    FileHandle.standardError.write("failed to start audio engine: \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("[listen] say \"hey claude\" …  (Ctrl-C to quit)")
RunLoop.main.run()
