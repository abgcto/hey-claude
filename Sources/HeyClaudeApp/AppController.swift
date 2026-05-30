import Foundation
import Observation
import HeyClaudeKit

/// Appends one line per fired wake to `/tmp/heyclaude-route.log` (and stderr) so
/// the live transcript → routing decision is visible for diagnosis — the one
/// thing synthetic fixtures and unit tests cannot reproduce. Off by default;
/// opt in with `HEYCLAUDE_ROUTE_LOG=1` so production stays quiet. Free function
/// (not on the @MainActor class) so it is safe to call from the audio queue.
private func logRoute(_ o: VoiceSession.Outcome) {
    guard ProcessInfo.processInfo.environment["HEYCLAUDE_ROUTE_LOG"] != nil else { return }
    let stripped = o.strippedCommand.map { "\"\($0)\"" } ?? "nil"
    let routed = o.resolved.map { "\($0.command.label) [\($0.command.id)] prompt=\($0.prompt.map { "\"\($0)\"" } ?? "nil")" }
        ?? "nil (no command)"
    let line = "raw=\"\(o.transcript)\"  stripped=\(stripped)  ->  \(routed)\n"
    FileHandle.standardError.write(Data(line.utf8))
    let url = URL(fileURLWithPath: "/tmp/heyclaude-route.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

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
    private(set) var settings: Settings

    /// Set by the app layer (HeyClaudeApp) to present the onboarding window when
    /// first-run setup hasn't happened. `start()` calls this instead of booting
    /// the listening pipeline. nil before the window layer is wired.
    var onNeedsOnboarding: (() -> Void)?

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

        // First run: don't boot the listening pipeline — hand off to onboarding.
        // Make the placeholder the island's FIRST update (no idle flash before it),
        // so the empty shell blooms cleanly into the notch through setup. The
        // resident island only appears once onboarding is done; the choreography
        // animates the mascot up to the notch itself.
        guard settings.onboardingCompleted else {
            island?.update(.onboardingPlaceholder)   // empty island shell — blooms in at resting width
            onNeedsOnboarding?()
            return
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
            // Prefer the per-user keyword from enrollment; fall back to bundled.
            let keywordsFile = KeywordStore().urlIfPresent
                ?? modelsDir.appendingPathComponent("keywords.txt")
            let wake = try WakeWordEngine(
                modelDir: modelsDir.appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"),
                keywordsFile: keywordsFile,
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
                },
                // Observability seam: log what each fire heard + how it routed.
                // Runs on the audio queue; `logRoute` is queue-safe (no self).
                observe: { logRoute($0) })
            self.voice = voice

            let capture = CaptureSession(
                postFireMaxSeconds: settings.maxUtteranceSeconds,
                vad: VoiceActivityDetector(hangoverMs: settings.endpointSilenceMs),
                onUtterance: { clip in
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

    /// The resolved models directory (KWS + ASR live under here), or nil if
    /// missing. Exposed so onboarding can drive enrollment off the same models.
    var modelsDirectory: URL? { resolveModelsDir() }

    /// Finish onboarding: persist the enrolled per-user keyword + tuned threshold
    /// + chosen terminal/folder, mark done, and boot the listening pipeline (which
    /// then picks up the per-user keyword via `start()`'s resolution).
    func finishOnboarding(keywordLines: [String], threshold: Float,
                          terminal: TerminalKind, projectDirectory: String) {
        if !keywordLines.isEmpty { try? KeywordStore().save(lines: keywordLines) }
        var s = settings
        s.wakeKeywordsThreshold = threshold
        s.preferredTerminal = terminal
        s.projectDirectory = projectDirectory
        s.onboardingCompleted = true
        try? SettingsStore().save(s)
        settings = s
        restartPipeline()
    }

    /// Skip enrollment: mark done (falls back to the bundled keyword) and boot.
    func completeOnboarding() {
        var s = settings
        s.onboardingCompleted = true
        try? SettingsStore().save(s)
        settings = s
        restartPipeline()
    }

    /// Tear down any running capture and (re)boot from the current settings —
    /// used after onboarding / re-run so we never stack a second mic tap.
    private func restartPipeline() {
        audio?.stop(); audio = nil
        wake = nil; transcriber = nil; capture = nil; voice = nil; executor = nil
        didStart = false
        start()
    }

    var needsOnboarding: Bool { !settings.onboardingCompleted }

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
