import Foundation
import HeyClaudeKit

// Real headless Hey Claude: wake -> capture -> transcribe -> route -> LAUNCH.
// Unlike the Phase 1 spike, this EXECUTES the action (opens a terminal running
// `claude`). Run from a terminal; grant Microphone + Automation permissions.
//
// Pipeline (spec §3–5), wired from tested HeyClaudeKit components:
//   AudioCapture(frame) ──listening──▶ CaptureSession.feedWhileListening + WakeWordEngine.feed
//                        ──fire──────▶ CaptureSession.feedWhileCapturing
//   CaptureSession.onUtterance ──▶ VoiceSession.handle ──▶ transcribe → strip → route → ActionExecutor

let store = SettingsStore()
let settings = store.load()

let models = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // heyclaude
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // repo root
    .appendingPathComponent("Models")

let launcher: TerminalLauncher = {
    switch settings.preferredTerminal {
    case .terminalApp: return TerminalAppLauncher()
    case .iterm2: return ITerm2Launcher()
    case .ghostty: return GhosttyLauncher()
    }
}()
let executor = ActionExecutor(settings: settings, launcher: launcher)

let wake: WakeWordEngine
let transcriber: ParakeetTranscriber
do {
    wake = try WakeWordEngine(
        modelDir: models.appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"),
        keywordsFile: models.appendingPathComponent("keywords.txt"),
        keywordsThreshold: settings.wakeKeywordsThreshold,
        keywordsScore: settings.wakeKeywordsScore)
    transcriber = try ParakeetTranscriber(
        modelDir: models.appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"))
} catch {
    FileHandle.standardError.write("failed to load models: \(error)\n".data(using: .utf8)!)
    exit(1)
}

let voice = VoiceSession(
    transcribe: { (try? transcriber.transcribe($0)) ?? "" },
    now: { Date().timeIntervalSinceReferenceDate },
    cooldownSeconds: settings.cooldownSeconds,
    execute: { action in
        print("[route] -> \(action) — launching")
        do { try executor.execute(action) }
        catch { FileHandle.standardError.write("launch failed: \(error)\n".data(using: .utf8)!) }
    })

let capture = CaptureSession(onUtterance: { voice.handle(utterance: $0) })

// The wake check happens here, on the AudioCapture serial queue, while listening.
let mic: AudioCapture
do {
    mic = try AudioCapture(onFrame: { frame in
        switch capture.state {
        case .listening:
            capture.feedWhileListening(frame)
            if wake.feed(frame) {
                print("[wake] detected")
                capture.fire()
            }
        case .capturing:
            capture.feedWhileCapturing(frame)
        }
    })
    try mic.start()
} catch {
    FileHandle.standardError.write("failed to start audio: \(error)\n".data(using: .utf8)!)
    exit(1)
}

print("Hey Claude is listening. Say \"hey claude\" … (Ctrl-C to quit)")
print("  terminal: \(settings.preferredTerminal.rawValue)   project: \(settings.projectDirectory)")
RunLoop.main.run()
