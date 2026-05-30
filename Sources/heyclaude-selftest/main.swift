import Foundation
import HeyClaudeKit

// On-machine verification harness.
//
// This CLT-only Swift toolchain has no XCTest runner, so the canonical XCTest
// suites in Tests/HeyClaudeKitTests/ cannot execute here (they remain for CI /
// Xcode). This executable mirrors those assertions so each task can be proven
// on this machine with `swift run heyclaude-selftest <check>`.

// MARK: - Tiny assertion harness

final class Check {
    let name: String
    var failures: [String] = []
    init(_ name: String) { self.name = name }

    func fail(_ message: String) { failures.append(message) }
    func assert(_ cond: Bool, _ message: @autoclosure () -> String) {
        if !cond { failures.append(message()) }
    }
    func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "") {
        if a != b { failures.append("expected \(b), got \(a). \(message())") }
    }
}

func run(_ name: String, _ body: (Check) throws -> Void) -> Bool {
    let c = Check(name)
    do {
        try body(c)
    } catch {
        c.fail("threw: \(error)")
    }
    if c.failures.isEmpty {
        print("PASS  \(name)")
        return true
    } else {
        print("FAIL  \(name)")
        for f in c.failures { print("      - \(f)") }
        return false
    }
}

// MARK: - Path helpers

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // heyclaude-selftest
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // repo root
let modelsDir = repoRoot.appendingPathComponent("Models")
let fixturesDir = repoRoot
    .appendingPathComponent("Tests/HeyClaudeKitTests/Fixtures")

func fixture(_ name: String) -> URL {
    fixturesDir.appendingPathComponent("\(name).wav")
}

let kwsDir = modelsDir
    .appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01")
let asrDir = modelsDir
    .appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8")
let keywordsFile = modelsDir.appendingPathComponent("keywords.txt")

// MARK: - Checks

func checkSherpaLinks() -> Bool {
    run("sherpaLinks") { c in
        c.assert(HeyClaudeKit.sherpaLinks(), "sherpa-onnx C symbols did not link")
    }
}

// Mirrors AudioSamplesTests.test_loads16kMonoFloatSamples.
func checkAudioLoader() -> Bool {
    run("audio.loads16kMonoFloatSamples") { c in
        let samples = try AudioSamples.load(fixture("hey_claude_only"))
        c.assert(samples.count > 8000, "expected > 8000 samples, got \(samples.count)")
        c.assert(samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 },
                 "samples out of [-1, 1] range")
    }
}

// Calibrated wake-word threshold; see internal design notes.
let wakeThreshold: Float = 0.25

func makeWakeEngine(threshold: Float = wakeThreshold) throws -> WakeWordEngine {
    let t0 = Date()
    let e = try WakeWordEngine(modelDir: kwsDir, keywordsFile: keywordsFile,
                               keywordsThreshold: threshold)
    FileHandle.standardError.write(
        "  [diag] wake engine constructed in \(String(format: "%.2f", -t0.timeIntervalSinceNow))s\n"
            .data(using: .utf8)!)
    return e
}

func diagDetect(_ engine: WakeWordEngine, _ samples: [Float], _ label: String) -> Bool {
    let t0 = Date()
    let r = engine.detects(in: samples)
    FileHandle.standardError.write(
        "  [diag] detect(\(label)) -> \(r) in \(String(format: "%.2f", -t0.timeIntervalSinceNow))s\n"
            .data(using: .utf8)!)
    return r
}

// Mirrors WakeWordEngineTests.test_doesNotFireOnNegativeSpeech.
func checkWakeNegative() -> Bool {
    run("wake.doesNotFireOnNegativeSpeech") { c in
        let engine = try makeWakeEngine()
        let samples = try AudioSamples.load(fixture("negative_speech"))
        c.assert(!diagDetect(engine, samples, "negative"), "fired on negative speech")
    }
}

// Positive control: prove the detection plumbing fires at all, using the
// model's OWN validated keyword file against its OWN test wav (0.wav contains
// "…LIGHT UP HERE…", and test_keywords.txt includes "▁ L IGHT ▁UP").
func checkWakePositiveControl() -> Bool {
    run("wake.positiveControl(model-own-keyword)") { c in
        let ownKeywords = kwsDir.appendingPathComponent("test_wavs/test_keywords.txt")
        let ownWav = kwsDir.appendingPathComponent("test_wavs/0.wav")
        let engine = try WakeWordEngine(modelDir: kwsDir, keywordsFile: ownKeywords,
                                        keywordsThreshold: 0.25)
        let samples = try AudioSamples.load(ownWav)
        c.assert(diagDetect(engine, samples, "0.wav/LIGHT UP"),
                 "engine did not fire on the model's own validated keyword+wav")
    }
}

// Mirrors WakeWordEngineTests.test_detectsHeyClaudeInPositiveClip.
//
// Fires on the synthetic `say -v Samantha "hey claude"` clip at the calibrated
// defaults. The earlier "never fires" symptom was a streaming-flush bug (the
// tail pad was too short to drain the zipformer's last chunk on a ~0.7s clip),
// fixed in WakeWordEngine.detects(in:). See internal design notes.
func checkWakePositive() -> Bool {
    run("wake.detectsHeyClaudeInPositiveClip") { c in
        let engine = try makeWakeEngine()
        let samples = try AudioSamples.load(fixture("hey_claude_only"))
        c.assert(diagDetect(engine, samples, "hey_claude_only"),
                 "synthetic 'hey claude' clip did not fire the wake word")
    }
}

// Diagnostic sweep: prints detection across thresholds + clips. Not a pass/fail
// gate — used to calibrate `wakeThreshold` honestly. One engine per threshold
// (model load is ~0.3s), all clips reused.
func probeWake() -> Bool {
    print("PROBE wake threshold sweep")
    let clips = ["hey_claude_only", "hey_claude_code", "hey_claude_prompt", "negative_speech"]
    let loaded = clips.compactMap { name -> (String, [Float])? in
        guard let s = try? AudioSamples.load(fixture(name)) else { return nil }
        return (name, s)
    }
    // Fresh engine per (threshold, clip): the wrapper's single internal stream
    // is finished after one detect(), so it is not safely reusable across clips.
    for t in [Float(0.02), 0.05, 0.10, 0.15, 0.20, 0.25] {
        var line = "  thr=\(t):"
        for (name, s) in loaded {
            guard let engine = try? WakeWordEngine(
                modelDir: kwsDir, keywordsFile: keywordsFile, keywordsThreshold: t) else {
                line += " \(name)=ERR"; continue
            }
            line += " \(name)=\(engine.detects(in: s) ? "Y" : "n")"
        }
        print(line)
    }
    return true
}

// What tokens does the KWS transducer ACTUALLY emit for each synthetic clip?
// Drive the same encoder/decoder/joiner as a plain online recognizer so we can
// build the keyword from the real emitted tokens rather than dictionary BPE.
func probeDecode() -> Bool {
    print("PROBE decode (KWS model as online transducer)")
    for clip in ["hey_claude_only", "hey_claude_code", "hey_claude_prompt"] {
        guard let samples = try? AudioSamples.load(fixture(clip)) else { continue }
        let r = KwsDebug.decodeTokens(modelDir: kwsDir, samples: samples)
        print("  \(clip): text=\"\(r.text)\"  tokens=\(r.tokens)")
    }
    return true
}

// Live calibration: record YOUR real "hey claude" and show the tokens the KWS
// model emits for it + whether the current keyword fires. The synthetic fixtures
// may tokenize differently than a real voice; this is the data we build the
// keyword from. Run: `swift run heyclaude-selftest mic-decode`.
func probeMicDecode() -> Bool {
    final class Buf: @unchecked Sendable {
        private var s: [Float] = []
        private let lock = NSLock()
        func append(_ f: [Float]) { lock.lock(); s.append(contentsOf: f); lock.unlock() }
        func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return s }
    }

    let rounds = 5, windowSec = 2.5
    print("PROBE mic-decode — say \"hey claude\" once per round (\(rounds) rounds).")
    let wake = try? WakeWordEngine(modelDir: kwsDir, keywordsFile: keywordsFile,
                                   keywordsThreshold: 0.25, keywordsScore: 2.0)
    for round in 1...rounds {
        let buf = Buf()
        guard let mic = try? AudioCapture(onFrame: { buf.append($0) }) else {
            print("  mic init failed"); return true
        }
        print("  Round \(round)/\(rounds): say \"hey claude\" NOW…")
        do { try mic.start() } catch { print("  mic start failed: \(error)"); return true }
        Thread.sleep(forTimeInterval: windowSec)
        mic.stop()

        let samples = buf.snapshot()
        let r = KwsDebug.decodeTokens(modelDir: kwsDir, samples: samples)
        let fired = wake?.detects(in: samples) ?? false
        print("        text=\"\(r.text)\"")
        print("        tokens=\(r.tokens)")
        print("        current keyword fires? \(fired ? "✅ YES" : "❌ NO")")
    }
    print("\n  Keyword file currently: \(((try? String(contentsOf: keywordsFile, encoding: .utf8)) ?? "?").trimmingCharacters(in: .whitespacesAndNewlines))")
    return true
}

// Full wake enrollment over 3 live utterances — the real algorithm end to end,
// dry-run (does NOT overwrite your per-user keyword). Run: `… enroll`.
func probeEnroll() -> Bool {
    let kws = kwsDir   // capture locally so the @Sendable closures don't touch globals
    print("PROBE enroll — 3 live utterances (2 isolated + 1 natural).")

    func recordOne(_ label: String) -> [Float] {
        print("  \(label)")
        final class Clip: @unchecked Sendable { var s: [Float] = [] }
        let clip = Clip()
        let sem = DispatchSemaphore(value: 0)
        let rec = EnrollmentRecorder(endpointSilenceMs: 800, maxSeconds: 8)
        do { try rec.record(onClip: { c in clip.s = c; sem.signal() }) }
        catch { print("    mic failed: \(error)"); return [] }
        sem.wait()
        print("    captured \(clip.s.count) samples (~\(String(format: "%.1f", Double(clip.s.count) / 16000))s)")
        return clip.s
    }

    let samples: [WakeEnrollment.Sample] = [
        .init(audio: recordOne("Isolated 1 — say \"Hey Claude\" NOW…"), kind: .isolated),
        .init(audio: recordOne("Isolated 2 — say \"Hey Claude\" NOW…"), kind: .isolated),
        .init(audio: recordOne("Natural — say \"Hey Claude\" and ask for something…"), kind: .natural),
    ]

    let enroll = WakeEnrollment(
        decode: { s in KwsDebug.decodeTokens(modelDir: kws, samples: s).tokens },
        fires: { lines, threshold, audio in
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("hc-enroll-kw.txt")
            try? (lines.joined(separator: "\n") + "\n").write(to: tmp, atomically: true, encoding: .utf8)
            guard let e = try? WakeWordEngine(modelDir: kws, keywordsFile: tmp,
                                              keywordsThreshold: threshold, keywordsScore: 2.0)
            else { return false }
            return e.detects(in: audio)
        })

    let r = enroll.enroll(samples: samples)
    print("\n  === ENROLLMENT RESULT (dry run — not saved) ===")
    print("  keyword lines:"); for l in r.keywordLines { print("    \(l)") }
    print("  threshold: \(r.threshold)")
    print("  all samples fire: \(r.allFired ? "✅ YES" : "❌ NO")")
    print("  derived from voice: \(r.usedFallbackOnly ? "NO (fallback only)" : "YES")")
    print("\n  per-sample (at threshold \(r.threshold)):")
    let labels = ["isolated-1", "isolated-2", "natural   "]
    for (i, s) in samples.enumerated() {
        let toks = KwsDebug.decodeTokens(modelDir: kws, samples: s.audio).tokens
        let f = enroll.fires(r.keywordLines, r.threshold, s.audio)
        print("    \(labels[i]): fires \(f ? "✅" : "❌")   tokens=\(toks)")
    }
    return true
}

// DIAG 1 — audio sanity: transcribe the EXACT wake clip used by the wake test.
func probeTranscribeOnly() -> Bool {
    print("PROBE asr transcript of hey_claude_only")
    guard let samples = try? AudioSamples.load(fixture("hey_claude_only")),
          let t = try? ParakeetTranscriber(modelDir: asrDir) else {
        print("  ERR could not load model/clip"); return true
    }
    let text = (try? t.transcribe(samples)) ?? "<threw>"
    print("  hey_claude_only: \"\(text)\"")
    return true
}

// DIAG 2 — boost sweep. keywords_score keeps the keyword path alive in the
// beam when acoustic evidence is weak (a different lever than threshold). Sweep
// it over the positive clip AND negative_speech so we can pick a value with
// separation (fires on positive, quiet on negative). Threshold pinned low.
func probeBoostSweep() -> Bool {
    print("PROBE wake boost sweep (threshold=0.10)")
    let clips = ["hey_claude_only", "negative_speech"]
    let loaded = clips.compactMap { name -> (String, [Float])? in
        guard let s = try? AudioSamples.load(fixture(name)) else { return nil }
        return (name, s)
    }
    print("  boost  | " + loaded.map { $0.0 }.joined(separator: "  "))
    for boost in [Float(1.0), 2.0, 3.0, 5.0, 8.0] {
        var line = "  \(String(format: "%.1f", boost))    |"
        for (_, s) in loaded {
            // Fresh engine per (boost, clip): the single internal stream is
            // finished after one detect().
            guard let e = try? WakeWordEngine(
                modelDir: kwsDir, keywordsFile: keywordsFile,
                keywordsThreshold: 0.10, keywordsScore: boost) else {
                line += " ERR"; continue
            }
            line += " \(e.detects(in: s) ? "FIRE" : "----")"
        }
        print(line)
    }
    return true
}

// Mirrors ParakeetTranscriberTests.test_transcribesPromptClip.
func checkTranscribe() -> Bool {
    run("asr.transcribesPromptClip") { c in
        let t0 = Date()
        let t = try ParakeetTranscriber(modelDir: asrDir)
        FileHandle.standardError.write(
            "  [diag] ASR engine constructed in \(String(format: "%.2f", -t0.timeIntervalSinceNow))s\n"
                .data(using: .utf8)!)
        let text = try t.transcribe(try AudioSamples.load(fixture("hey_claude_prompt")))
        print("  [asr] transcript: \"\(text)\"")
        c.assert(text.contains("refactor"), "expected 'refactor', got: \(text)")
        c.assert(text.contains("auth"), "expected 'auth', got: \(text)")
    }
}

// Diagnostic (not a test): reproduces the app's exact routing for each
// "hey claude" fixture — transcribe -> WakePrefixStripper -> CommandRegistry —
// to reveal which command a bare/coded/prompt utterance actually resolves to.
// Mirrors VoiceSession.handle. Run: `swift run heyclaude-selftest route`.
func probeRoute() -> Bool {
    run("route.resolvesFixturesToCommands") { _ in
        let asr = try ParakeetTranscriber(modelDir: asrDir)
        let s = Settings.default
        let registry = CommandRegistry(commands: s.commands,
                                       defaultCommandID: s.defaultCommandID,
                                       promptCommandID: s.promptCommandID)

        func kindLabel(_ k: CommandKind) -> String {
            switch k {
            case .runCLI(let t):   return "runCLI(\(t))"
            case .openApp(let b):  return "openApp(\(b))"
            case .runShell(let s): return "runShell(\(s))"
            }
        }

        func report(_ tag: String, _ raw: String) {
            let stripped = WakePrefixStripper.command(from: raw)
            let res = registry.resolve(transcript: stripped)
            print("  [route] \(tag)")
            print("          raw       = \"\(raw)\"")
            print("          stripped  = \(stripped.map { "\"\($0)\"" } ?? "nil (bare wake)")")
            if let res = res {
                print("          resolved  = \(res.command.label)  [\(kindLabel(res.command.kind))]  prompt=\(res.prompt.map { "\"\($0)\"" } ?? "nil")")
            } else {
                print("          resolved  = nil (no command)")
            }
        }

        for name in ["hey_claude_only", "hey_claude_code", "hey_claude_prompt"] {
            report(name, try asr.transcribe(try AudioSamples.load(fixture(name))))
        }

        // Simulate the LIVE capture clip: 2.0s preroll silence + utterance +
        // trailing silence to the 2.5s post-fire cap. Tests whether Parakeet
        // hallucinates/repeats on the silence padding the live path adds.
        let only = try AudioSamples.load(fixture("hey_claude_only"))
        let lead = [Float](repeating: 0, count: 32000)   // 2.0s @ 16kHz preroll
        for tailS in [0.6, 1.5, 2.5] {
            let tail = [Float](repeating: 0, count: Int(16000 * tailS))
            let padded = lead + only + tail
            report("padded(lead2.0s+tail\(tailS)s)", try asr.transcribe(padded))
        }
    }
}

// MARK: - Dispatch

func main() -> Int32 {
    setbuf(stdout, nil)  // unbuffered: see progress live even when piped
    let requested = CommandLine.arguments.dropFirst().first ?? "all"
    var allOK = true

    func maybe(_ key: String, _ check: () -> Bool) {
        if requested == "all" || requested == key {
            if !check() { allOK = false }
        }
    }

    maybe("sherpa", checkSherpaLinks)
    maybe("audio", checkAudioLoader)
    maybe("wake-negative", checkWakeNegative)
    maybe("wake-control", checkWakePositiveControl)
    maybe("wake-positive", checkWakePositive)
    maybe("wake-probe", probeWake)
    maybe("decode-probe", probeDecode)
    maybe("mic-decode", probeMicDecode)
    maybe("enroll", probeEnroll)
    maybe("asr-only", probeTranscribeOnly)
    maybe("boost-sweep", probeBoostSweep)
    maybe("asr", checkTranscribe)
    maybe("route", probeRoute)

    return allOK ? 0 : 1
}

exit(main())
