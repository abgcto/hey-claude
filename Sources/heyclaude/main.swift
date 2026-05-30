import Foundation
import HeyClaudeKit

// Real headless Hey Claude: wake -> capture -> transcribe -> route -> LAUNCH.
// Unlike the Phase 1 spike, this EXECUTES the action (opens a terminal running
// `claude`). Run from a terminal; grant Microphone + Automation permissions.
//
// Pipeline (spec §3–5), wired from tested HeyClaudeKit components:
//   AudioCapture(frame) ──listening──▶ CaptureSession.feedWhileListening + WakeWordEngine.feed
//                        ──fire──────▶ CaptureSession.feedWhileCapturing
//   CaptureSession.onUtterance ──▶ VoiceSession.handle ──▶ transcribe → strip → resolve → CommandExecutor

let store = SettingsStore()
let settings = store.load()

let models = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // heyclaude
    .deletingLastPathComponent()   // Sources
    .deletingLastPathComponent()   // repo root
    .appendingPathComponent("Models")

let registry = CommandRegistry(commands: settings.commands,
                               defaultCommandID: settings.defaultCommandID,
                               promptCommandID: settings.promptCommandID)
let executor = CommandExecutor(settings: settings,
                               launcherFor: { kind in
                                   switch kind {
                                   case .terminalApp: return TerminalAppLauncher()
                                   case .iterm2: return ITerm2Launcher()
                                   case .ghostty: return GhosttyLauncher()
                                   }
                               })

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
    registry: registry,
    execute: { cmd, prompt in
        print("[route] -> \(cmd.label)\(prompt.map { " : \($0)" } ?? "") — launching")
        do { try executor.execute(cmd, prompt: prompt) }
        catch { FileHandle.standardError.write("launch failed: \(error)\n".data(using: .utf8)!) }
    },
    // Diagnostic: show exactly what the model heard and how it stripped/resolved,
    // BEFORE the launch — this is what reveals a bare "hey claude" picking up a
    // stray trailing token and escaping to the Claude Code fallthrough.
    observe: { o in
        let stripped = o.strippedCommand.map { "\"\($0)\"" } ?? "nil (bare wake)"
        print("[heard] raw=\"\(o.transcript)\"  stripped=\(stripped)")
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

// Preflight: warn (don't block) if `claude` isn't resolvable. Best-effort —
// the launched terminal uses a login shell whose PATH may differ from ours.
func resolvesExecutable(_ exe: String) -> Bool {
    if exe.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: exe) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["which", exe]
    p.standardOutput = Pipe(); p.standardError = Pipe()
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 }
    catch { return false }
}
if !resolvesExecutable(settings.claudeExecutable) {
    print("⚠️  '\(settings.claudeExecutable)' not found on this shell's PATH — a launched terminal may show 'command not found'. If so, set an absolute path in settings.")
}

print("Hey Claude is listening. Say \"hey claude\" … (Ctrl-C to quit)")
print("  target: \(settings.preferredTarget.label)   project: \(settings.projectDirectory)")
RunLoop.main.run()
