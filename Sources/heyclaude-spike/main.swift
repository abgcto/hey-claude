@preconcurrency import AVFoundation
import Foundation
import HeyClaudeKit

// Live-mic spike: continuous wake-word streaming → pre-roll capture → transcribe
// → strip wake prefix → route → print the resolved action.
//
// This is the Phase 2 manual spike. It is NOT run by CI or `swift test`; it
// needs a real microphone and human speech. `swift build` must stay clean.
//
//   say "hey claude"                  -> Action.launchCLI(prompt: nil)
//   say "hey claude code"             -> Action.launchCLI(prompt: nil)
//   say "hey claude <some prompt>"    -> Action.launchCLI(prompt: "<some prompt>")
//
// WHY PRE-ROLL: the keyword spotter fires at the END of "…claude" with some
// latency, so a command spoken in the same breath ("hey claude code") has
// already streamed past by the time we'd start a post-fire capture — the word
// is lost and we only record trailing silence. Instead we keep a rolling ~2s
// lookback buffer at all times; when the wake fires we seed the capture with
// that lookback (which already contains "hey claude <command-so-far>"), keep
// recording until the utterance endpoints, transcribe the whole thing, strip
// the leading "hey claude", and route the remainder.
//
// Concurrency: top-level main.swift is `@MainActor`, but AVAudioEngine invokes
// the tap on a real-time audio thread. All audio state lives inside `Spike`, a
// non–main-actor `@unchecked Sendable` whose tap captures only `self` and reads
// no main-actor global; mutable state is touched only on the serial `work`
// queue. (Capturing a main-actor global on the audio thread trips
// `_swift_task_checkIsolated` and crashes — the original bug.)

/// Owns the audio engine and the full wake→capture→transcribe→route pipeline.
final class Spike: @unchecked Sendable {
    static let sampleRate = 16000.0
    static let prerollSeconds = 2.0      // lookback retained before a fire
    static let postFireMaxSeconds = 2.5  // safety cap on post-fire capture

    enum SetupError: Swift.Error { case audioFormat }
    private enum State { case listening, capturing }

    private let wake: WakeWordEngine
    private let transcriber: ParakeetTranscriber
    private let vad = VoiceActivityDetector()
    private let router = CommandRouter(
        defaultAction: .launchCLI(prompt: nil),
        phraseMap: ["open the app": .openDesktopApp])

    private let engine = AVAudioEngine()
    private let inputFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let prerollCap: Int
    private let postFireMax: Int

    // Serial queue: all frame processing happens here, in capture order, off
    // the real-time audio thread. The only synchronization for the mutable
    // state below.
    private let work = DispatchQueue(label: "heyclaude.spike.pipeline")
    private var state: State = .listening
    private var preroll: [Float] = []   // rolling lookback while listening
    private var captured: [Float] = []  // utterance being captured after a fire
    private var postFireCount = 0

    init() throws {
        let modelsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // heyclaude-spike
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Models")
        let kwsDir = modelsDir.appendingPathComponent(
            "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01")
        let asrDir = modelsDir.appendingPathComponent(
            "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8")
        let keywordsFile = modelsDir.appendingPathComponent("keywords.txt")

        self.wake = try WakeWordEngine(modelDir: kwsDir, keywordsFile: keywordsFile)
        self.transcriber = try ParakeetTranscriber(modelDir: asrDir)
        self.prerollCap = Int(Self.sampleRate * Self.prerollSeconds)
        self.postFireMax = Int(Self.sampleRate * Self.postFireMaxSeconds)

        self.inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inputFormat, to: target) else {
            throw SetupError.audioFormat
        }
        self.targetFormat = target
        self.converter = conv
    }

    func start() throws {
        engine.inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) {
            [self] buffer, _ in
            let samples = toModelSamples(buffer)
            guard !samples.isEmpty else { return }
            work.async { self.process(frame: samples) }
        }
        try engine.start()
    }

    /// Convert a hardware-format buffer to 16 kHz mono Float samples.
    /// Runs on the audio thread; `converter` is only ever used here.
    private func toModelSamples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let ratio = Self.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return []
        }
        // One-shot feed flag in a reference box: AVAudioConverter calls this
        // block synchronously (no real concurrency), but a captured `var` trips
        // the Sendable-closure warning, so use a reference instead.
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

    /// Process one frame of 16 kHz mono samples. Always on `work`.
    private func process(frame: [Float]) {
        switch state {
        case .listening:
            // Maintain the rolling lookback buffer.
            preroll.append(contentsOf: frame)
            if preroll.count > prerollCap {
                preroll.removeFirst(preroll.count - prerollCap)
            }
            if wake.feed(frame) {
                print("\n[wake] \"hey claude\" detected — capturing utterance …")
                captured = preroll            // seed with lookback ("hey claude <cmd-so-far>")
                preroll.removeAll(keepingCapacity: true)
                postFireCount = 0
                state = .capturing
            }
        case .capturing:
            captured.append(contentsOf: frame)
            postFireCount += frame.count
            // Finish once the speaker pauses (endpoint) or we hit the safety cap.
            if vad.hasEndpointed(captured) || postFireCount >= postFireMax {
                finishCapture()
                state = .listening
            }
        }
    }

    private func finishCapture() {
        let clip = captured
        captured.removeAll(keepingCapacity: true)
        postFireCount = 0

        let transcript = (try? transcriber.transcribe(clip)) ?? ""
        print("[asr] heard: \"\(transcript)\"")
        let command = Self.commandAfterWake(transcript)
        print("[parsed] command: \(command.map { "\"\($0)\"" } ?? "<none — bare launch>")")
        let action = router.route(transcript: command)
        print("[route] -> \(action)")
        print("[listen] say \"hey claude\" …")
    }

    /// Strip the leading wake phrase from a full transcript, returning only the
    /// trailing command (or nil for a bare "hey claude"). The ASR may render
    /// "claude" as "cloud"/"claud"/etc., so we match a small set of variants.
    static func commandAfterWake(_ raw: String) -> String? {
        let lowered = raw.lowercased()
        let cleaned = String(lowered.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " })
        let words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        let wakeMarkers: Set<String> = ["claude", "cloud", "claud", "clawed", "clode", "clawd", "clod"]
        if let idx = words.firstIndex(where: { wakeMarkers.contains($0) }) {
            let rest = words[(idx + 1)...].joined(separator: " ")
            return rest.isEmpty ? nil : rest
        }
        // No claude-variant recognized but starts with "hey": drop "hey" + one word.
        if words.first == "hey", words.count >= 2 {
            let rest = words.dropFirst(2).joined(separator: " ")
            return rest.isEmpty ? nil : rest
        }
        return nil
    }
}

// MARK: - Entry point (main actor)

print("heyclaude-spike \(HeyClaudeKit.version)")
print("sherpa-onnx links: \(HeyClaudeKit.sherpaLinks())")

let spike: Spike
do {
    spike = try Spike()
    try spike.start()
} catch {
    FileHandle.standardError.write("failed to start spike: \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("[listen] say \"hey claude\" …  (Ctrl-C to quit)")
RunLoop.main.run()
