import Foundation
import Observation
import HeyClaudeKit

/// Owns the Phase 2 voice pipeline (`AudioCapture → WakeWordEngine →
/// CaptureSession → VoiceSession → ActionExecutor`) and publishes a single
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
    private var executor: ActionExecutor?
    private var userMuted = false
    private var didStart = false

    init() {
        self.settings = SettingsStore().load()
    }

    /// Boots the pipeline. Idempotent — safe to call from a SwiftUI `.task`.
    func start() {
        guard !didStart else { return }
        didStart = true

        guard let modelsDir = resolveModelsDir() else {
            emit(.micDenied)   // surfaced as `.off`: no models means nothing to run
            return
        }

        let launcher: TerminalLauncher
        switch settings.preferredTerminal {
        case .terminalApp: launcher = TerminalAppLauncher()
        case .iterm2:      launcher = ITerm2Launcher()
        case .ghostty:     launcher = GhosttyLauncher()
        }
        let executor = ActionExecutor(settings: settings, launcher: launcher)
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
                execute: { [weak self] action in
                    // VoiceSession runs `execute` on the audio queue; perform the
                    // launch there, then report the result to the UI on main.
                    do { try executor.execute(action) }
                    catch {
                        FileHandle.standardError.write(
                            Data("launch failed: \(error)\n".utf8))
                    }
                    Task { @MainActor in self?.didExecute(action) }
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
    }

    private func didExecute(_ action: Action) {
        let directory: String? = {
            switch action {
            case .launchCLI:      return settings.projectDirectory
            case .openDesktopApp: return nil
            case .custom:         return nil
            }
        }()
        recentLog.record(action, directory: directory, at: Date().timeIntervalSinceReferenceDate)
        recent = recentLog
        emit(.launching)
        // Settle shortly after launch so the icon returns to armed.
        Task { @MainActor in
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
