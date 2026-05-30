import Foundation
import Observation
import HeyClaudeKit

/// Owns the Phase 2 voice pipeline (`AudioCapture → WakeWordEngine →
/// CaptureSession → VoiceSession → CommandExecutor`) and publishes a single
/// `AppState` for the menu-bar icon and menu to render.
///
/// Threading: the `AudioCapture` callback runs on `AudioCapture`'s serial
/// queue. `CaptureSession` and `WakeWordEngine` are driven on that queue (the
/// Phase 1 audio-isolation rule — never hop them to the main actor, or frames
/// drop / the real-time thread crashes). Only `emit(...)` and other UI-state
/// mutations hop to `@MainActor`.
@MainActor
@Observable
final class AppController {
    private(set) var state: AppState = .armed
    private(set) var recent = RecentActions()
    let settings: Settings

    private let machine = AppStateMachine()
    private let recentLog = RecentActions()
    private var audio: AudioCapture?
    private var wake: WakeWordEngine?
    private var transcriber: ParakeetTranscriber?
    private var capture: CaptureSession?
    private var voice: VoiceSession?
    private var executor: CommandExecutor?
    private var userMuted = false
    private var didStart = false

    // The notch island (3B-2). Owned here; driven on every state change. `nil`
    // when the user has hidden it (`settings.islandVisible == false`).
    private var island: NotchIslandPanel?
    // Held during the reveal beat: while `true` (and state is `.hot`) the island
    // shows the finalized transcript instead of "Listening…".
    private var revealing = false

    init() {
        self.settings = SettingsStore().load()
    }

    /// Boots the pipeline. Idempotent — safe to call from a SwiftUI `.task`.
    func start() {
        guard !didStart else { return }
        didStart = true

        // Bring up the island first so even the `.micDenied` early-out below
        // renders correctly (it maps to `.off` → hidden, ordering the panel out).
        if settings.islandVisible {
            island = NotchIslandPanel()
        }
        updateIsland()

        guard let modelsDir = resolveModelsDir() else {
            emit(.micDenied)   // surfaced as `.off`: no models means nothing to run
            return
        }

        let registry = CommandRegistry(commands: settings.commands,
                                       defaultCommandID: settings.defaultCommandID,
                                       promptCommandID: settings.promptCommandID)
        let executor = CommandExecutor(settings: settings,
                                       launcherFor: { kind in
                                           switch kind {
                                           case .terminalApp: return TerminalAppLauncher()
                                           case .iterm2:      return ITerm2Launcher()
                                           case .ghostty:     return GhosttyLauncher()
                                           }
                                       })
        self.executor = executor

        do {
            let wake = try WakeWordEngine(
                modelDir: modelsDir.appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"),
                keywordsFile: modelsDir.appendingPathComponent("keywords.txt"),
                keywordsThreshold: settings.wakeKeywordsThreshold,
                keywordsScore: settings.wakeKeywordsScore)
            let transcriber = try ParakeetTranscriber(
                modelDir: modelsDir.appendingPathComponent("sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"))
            self.wake = wake
            self.transcriber = transcriber

            let settings = self.settings
            let voice = VoiceSession(
                transcribe: { (try? transcriber.transcribe($0)) ?? "" },
                now: { Date().timeIntervalSinceReferenceDate },
                cooldownSeconds: settings.cooldownSeconds,
                registry: registry,
                execute: { [weak self] cmd, prompt in
                    // VoiceSession runs `execute` on the audio queue; perform the
                    // launch there, then report the result to the UI on main.
                    do { try executor.execute(cmd, prompt: prompt) }
                    catch {
                        FileHandle.standardError.write(
                            Data("launch failed: \(error)\n".utf8))
                    }
                    // `prompt` is the user's words post wake-strip — the text
                    // the island hands back during the reveal beat.
                    Task { @MainActor in self?.didExecute(cmd, transcript: prompt) }
                })
            self.voice = voice

            let capture = CaptureSession(onUtterance: { clip in
                // Runs on the audio queue. Route + execute via VoiceSession (which
                // also transcribes). CaptureSession stays on this queue.
                voice.handle(utterance: clip)
            })
            self.capture = capture

            // The closure captures the pipeline components as locals (never the
            // main-actor `self` for audio work) — the Phase 1 isolation rule.
            let audio = try AudioCapture(onFrame: { [weak self] frame in
                // Runs on AudioCapture's serial queue. AudioCapture itself drops
                // frames while muted, so no mute check is needed here.
                switch capture.state {
                case .listening:
                    capture.feedWhileListening(frame)
                    if wake.feed(frame) {
                        capture.fire()
                        Task { @MainActor in self?.emit(.wakeFired) }
                    }
                case .capturing:
                    capture.feedWhileCapturing(frame)
                }
            })
            self.audio = audio
            try audio.start()
        } catch {
            // Mic-permission denial or model-load failure — surfaced as `.off`.
            FileHandle.standardError.write(Data("Hey Claude failed to start: \(error)\n".utf8))
            emit(.micDenied)
        }
    }

    /// Sticky user mute. `AudioCapture` enforces the gate on its own queue, so
    /// the controller only flips the flag and reflects it in `AppState`.
    func toggleMute() {
        userMuted.toggle()
        audio?.setMuted(userMuted)
        emit(userMuted ? .muted : .unmuted)
    }

    private func emit(_ e: AppEvent) {
        machine.apply(e)
        state = machine.state
        updateIsland()
    }

    /// Rebuilds the island's display config from the current state + transcript
    /// and pushes it to the panel. Called from `emit(...)` for every state
    /// change, and directly during the reveal beat (which is *not* a state
    /// change — the machine holds `.hot` while `revealing` flips).
    private func updateIsland() {
        guard let island else { return }
        let model = IslandModel(state: machine.state,
                                transcript: machine.lastHeard,
                                revealing: revealing)
        island.update(model)
    }

    private func didExecute(_ command: Command, transcript: String?) {
        let directory: String? = {
            switch command.kind {
            case .runCLI:   return settings.projectDirectory
            case .openApp:  return nil
            case .runShell: return nil
            }
        }()
        recentLog.record(label: command.label, directory: directory,
                         at: Date().timeIntervalSinceReferenceDate)
        recent = recentLog

        // Reveal sequence: hold the transcript on the island for ~1.2s (state
        // stays `.hot`), then launch (`.hot → .working`, "Launching Claude"),
        // then settle back to the resting seam. The real launch already happened
        // on the audio queue; this is the cosmetic hand-back beat.
        let hasTranscript = !(transcript ?? "").isEmpty
        machine.apply(.heard(transcript ?? ""))   // records lastHeard while `.hot`
        revealing = hasTranscript
        updateIsland()                            // show transcript (or hold listening)

        Task { @MainActor in
            if hasTranscript {
                try? await Task.sleep(for: .milliseconds(1200))
            }
            self.revealing = false
            self.emit(.launching)
            try? await Task.sleep(for: .milliseconds(900))
            self.emit(.settled)
        }
    }

    /// Resolves the models directory. Prefers the app bundle's `Models/`
    /// (Phase 3B packaging); falls back to the repo `Models/` next to the
    /// current working directory (Phase 3A `swift run`). Returns the first that
    /// actually contains the KWS model directory.
    private func resolveModelsDir() -> URL? {
        let kwsDir = "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Models"))
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Models"))

        let fm = FileManager.default
        for dir in candidates {
            var isDir: ObjCBool = false
            let kws = dir.appendingPathComponent(kwsDir)
            if fm.fileExists(atPath: kws.path, isDirectory: &isDir), isDir.boolValue {
                return dir
            }
        }
        return nil
    }
}
