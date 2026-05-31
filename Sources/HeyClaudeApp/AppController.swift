import AppKit
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
    /// The most recent launch failure, held until the next successful launch.
    /// Drives the persistent "Last launch failed" row in the menu and the island's
    /// failure beat. Lives outside `AppState` (which is a pure render bucket), the
    /// same way `lastHeard` does.
    private(set) var lastFailure: LaunchFailure?

    /// Set by the app layer (HeyClaudeApp) to present the onboarding window when
    /// first-run setup hasn't happened. `start()` calls this instead of booting
    /// the listening pipeline. nil before the window layer is wired.
    var onNeedsOnboarding: (() -> Void)?

    /// Set by the app layer to open wake-word re-training (onboarding in retrain
    /// mode) from the Settings ▸ Voice tab. nil before the window layer is wired.
    var onRetrainRequested: (() -> Void)?
    func requestRetrain() { onRetrainRequested?() }

    /// Set by the app layer to open the Settings dashboard from the notch control
    /// panel (mirrors the menu's `Settings` item). nil before the window layer wired.
    var onOpenSettings: (() -> Void)?

    private let machine = AppStateMachine()
    private let recentLog = RecentActions()
    private var audio: AudioCapture?
    /// Live wake engine, boxed so a sensitivity change can hot-swap it without
    /// rebooting the pipeline (which would also reload the ~631MB transcriber).
    /// See `WakeWordEngineHolder`.
    private var wake: WakeWordEngineHolder?
    /// Serial queue for rebuilding the wake engine off the main actor on a
    /// sensitivity change — keeps rapid slider releases ordered and off the UI.
    private let wakeRebuildQueue = DispatchQueue(label: "heyclaude.wake-rebuild")
    private var transcriber: ParakeetTranscriber?
    private var capture: CaptureSession?
    private var voice: VoiceSession?
    /// Live launch executor, boxed so target/folder changes can hot-swap it
    /// without rebooting the pipeline. See `CommandExecutorHolder`.
    private var executor: CommandExecutorHolder?
    private var userMuted = false
    private var didStart = false

    // The notch island (3B-2). Owned here; driven on every state change. Always
    // present — the island IS the product's presence, so it's never user-hideable.
    private var island: NotchIslandPanel?
    // Held during the reveal beat: while `true` (and state is `.hot`) the island
    // shows the finalized transcript instead of "Listening…".
    private var revealing = false

    init() {
        var loaded = SettingsStore().load()
        // First run only: pick a sensible default target by detection instead of
        // a dumb hardcoded Terminal. Once onboarding is done the saved choice is
        // sticky — never re-detect and override the user. (design §5.7)
        if !loaded.onboardingCompleted {
            loaded.preferredTarget = Self.smartDefaultTarget()
        }
        self.settings = loaded
    }

    /// Detect the default target for a fresh install: if exactly one editor is
    /// installed, has the Claude Code extension, and is actively in use
    /// (lockfile or running), default to it; otherwise Terminal. (design §5.7)
    static func smartDefaultTarget() -> LaunchTarget {
        let integration = EditorIntegration.claudeCode
        let candidates = EditorAvailability().readyEditors(integration: integration)
        guard !candidates.isEmpty else { return .terminal(.terminalApp) }

        var active = DefaultTargetResolver.activeEditors(
            fromIdeNames: IdeLockfileReader().activeIdeNames(), among: candidates)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        active.formUnion(candidates.filter { running.contains($0.bundleID) })

        return DefaultTargetResolver.resolve(candidates: candidates, active: active)
    }

    /// The concrete launcher for a terminal kind. Single source of truth so the
    /// executor and the availability filter agree. `nonisolated` because the
    /// executor's `launcherFor` closure runs on the audio queue (never main).
    nonisolated static func launcher(for kind: TerminalKind) -> TerminalLauncher {
        switch kind {
        case .terminalApp: return TerminalAppLauncher()
        case .iterm2:      return ITerm2Launcher()
        case .ghostty:     return GhosttyLauncher()
        }
    }

    /// Installed terminal apps (Terminal is always present; iTerm2/Ghostty only
    /// if their bundle is found) — so we never offer one the user can't launch.
    var availableTerminals: [TerminalKind] {
        TerminalKind.allCases.filter { Self.launcher(for: $0).isAvailable() }
    }

    /// Targets the user can pick in the menu: installed terminals, plus any
    /// editor that is installed and Claude-Code-ready.
    var availableTargets: [LaunchTarget] {
        let editors = EditorAvailability().readyEditors(integration: .claudeCode)
        return availableTerminals.map { .terminal($0) }
            + EditorKind.allCases.filter { editors.contains($0) }.map { .editor($0) }
    }

    /// Editors installed but not yet usable (Claude Code extension missing).
    /// Surfaced disabled in the picker so users see they're an option once the
    /// extension is added, rather than wondering why they're absent.
    var unavailableEditors: [EditorKind] {
        let missing = EditorAvailability().installedMissingExtension(integration: .claudeCode)
        return EditorKind.allCases.filter { missing.contains($0) }
    }

    /// Builds a `CommandExecutor` snapshotting the current `settings`. The
    /// `launcherFor` closure is stateless, so this is cheap — no model or audio
    /// work. Used at pipeline boot and to hot-swap target/folder changes.
    private func makeExecutor() -> CommandExecutor {
        CommandExecutor(settings: settings, launcherFor: { Self.launcher(for: $0) })
    }

    /// Change the default target from the menu / Settings: persist and hot-swap the
    /// live executor in place. No pipeline restart — the target only changes *where*
    /// a command launches, not the speech models, so rebooting them would be wasteful
    /// (a ~1s freeze reloading ~650MB on the main actor). If the pipeline hasn't
    /// started yet, `executor` is nil and `start()` builds it from the new setting.
    func setPreferredTarget(_ target: LaunchTarget) {
        guard target != settings.preferredTarget else { return }
        var s = settings
        s.preferredTarget = target
        try? SettingsStore().save(s)
        settings = s
        executor?.swap(makeExecutor())
        // Refresh the live island so the hover panel reflects the new target
        // immediately — `islandControls()` reads `settings.preferredTarget`, and
        // without this it stays stale until the next state-change re-render (same
        // pattern as `setMascot` / `setMascotColor`). This is display-only; the
        // pipeline is deliberately NOT rebooted (see above).
        updateIsland()
    }

    /// Change the notch mascot from Preferences: persist and refresh the live
    /// island so it re-renders immediately. Purely cosmetic — never reboots the
    /// audio pipeline (that would drop the mic for a visual change).
    func setMascot(id: String) {
        var s = settings
        s.mascotID = id
        try? SettingsStore().save(s)
        settings = s
        updateIsland()
    }

    /// Change the mascot body color from Preferences: persist and refresh the
    /// live island. Cosmetic only — no pipeline restart (see `setMascot`).
    func setMascotColor(hex: String) {
        var s = settings
        s.mascotColorHex = hex
        try? SettingsStore().save(s)
        settings = s
        updateIsland()
    }

    /// Toggle ambient idle mascot animations from Preferences: persist and hot-swap
    /// the live island. Cosmetic only — no pipeline restart (see `setMascot`).
    func setMascotIdleAnimations(_ on: Bool) {
        guard on != settings.mascotIdleAnimations else { return }
        var s = settings
        s.mascotIdleAnimations = on
        try? SettingsStore().save(s)
        settings = s
        updateIsland()
    }

    /// Change the default working folder from Settings: persist and hot-swap the
    /// live executor in place — same reasoning as `setPreferredTarget`. The folder
    /// only changes where a command launches, not the speech models, so no restart.
    func setProjectDirectory(_ path: String) {
        guard path != settings.projectDirectory else { return }
        var s = settings
        s.projectDirectory = path
        try? SettingsStore().save(s)
        settings = s
        executor?.swap(makeExecutor())
    }

    /// Builds a `WakeWordEngine` from the current settings + resolved keyword file.
    /// `nonisolated` so it can run off the main actor (the KWS model load is ~19MB
    /// of ONNX — small, but no reason to load it on the UI thread). Pure inputs,
    /// no `self` state mutated, so it's concurrency-safe to call from a queue.
    nonisolated private static func makeWakeEngine(modelsDir: URL, threshold: Float,
                                                   score: Float) throws -> WakeWordEngine {
        let keywordsFile = KeywordStore().urlIfPresent
            ?? modelsDir.appendingPathComponent("keywords.txt")
        return try WakeWordEngine(
            modelDir: modelsDir.appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"),
            keywordsFile: keywordsFile,
            keywordsThreshold: threshold,
            keywordsScore: score)
    }

    /// Instance convenience: build a wake engine from the live settings. Used at
    /// pipeline boot (on main, the load is part of startup) and indirectly by the
    /// off-main rebuild path in `setWakeThreshold`.
    private func makeWakeEngine(modelsDir: URL) throws -> WakeWordEngine {
        try Self.makeWakeEngine(modelsDir: modelsDir,
                                threshold: settings.wakeKeywordsThreshold,
                                score: settings.wakeKeywordsScore)
    }

    /// Change wake sensitivity from Settings. Unlike target/folder (which only
    /// hot-swap the executor), the threshold is baked into the sherpa spotter at
    /// construction, so a new `WakeWordEngine` is required. But it does NOT need a
    /// full pipeline restart — that would also reload the ~631MB transcriber, which
    /// the threshold doesn't touch (the old ~1s freeze). Instead rebuild only the
    /// ~19MB wake engine off the main actor and `swap` it into the live holder; the
    /// transcriber, capture, voice and executor all keep running.
    /// Lower threshold = more eager (more sensitive).
    func setWakeThreshold(_ threshold: Float) {
        guard threshold != settings.wakeKeywordsThreshold else { return }
        var s = settings
        s.wakeKeywordsThreshold = threshold
        try? SettingsStore().save(s)
        settings = s

        // Not running yet (or no models) → nothing live to swap; next start() picks
        // up the saved threshold.
        guard didStart, let holder = wake, let modelsDir = resolveModelsDir() else { return }
        let score = s.wakeKeywordsScore
        wakeRebuildQueue.async {
            // Off-main: build the new engine, then swap atomically. On failure, keep
            // the old engine — a rebuild error must not leave the app deaf.
            guard let engine = try? Self.makeWakeEngine(modelsDir: modelsDir,
                                                        threshold: threshold, score: score)
            else {
                Log.launch.error("wake rebuild failed; keeping previous sensitivity engine")
                return
            }
            holder.swap(engine)
        }
    }

    /// Re-train the wake word from Settings: persist the freshly enrolled keyword
    /// lines + tuned threshold. A subset of `finishOnboarding` — leaves
    /// target/folder/`onboardingCompleted` untouched. Persist ONLY; the retrain
    /// window calls `resumeAfterRetrain()` on close, which reboots and picks this up
    /// (so save and cancel share one restart instead of double-booting).
    func retrainWakeWord(keywordLines: [String], threshold: Float) {
        if !keywordLines.isEmpty { try? KeywordStore().save(lines: keywordLines) }
        var s = settings
        s.wakeKeywordsThreshold = threshold
        try? SettingsStore().save(s)
        settings = s
    }

    /// Resume listening after the retrain window closes. `RetrainWindowController`
    /// suspended the pipeline so `EnrollmentRecorder` could own the mic; this boots
    /// it again, picking up a freshly saved keyword (or the prior one if cancelled).
    func resumeAfterRetrain() { restartPipeline() }

    /// Marketing version (`CFBundleShortVersionString`) for the Settings About line.
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "\u{2014}"
    }

    /// Boots the pipeline. Idempotent — safe to call from a SwiftUI `.task`.
    func start() {
        guard !didStart else { return }
        didStart = true

        // Bring up the island first so even the `.micDenied` early-out below
        // renders correctly (it maps to `.off` → hidden, ordering the panel out).
        // Reuse the existing panel if there is one (e.g. the onboarding finale set
        // it to the resident island already) — recreating it mid-hand-off causes a
        // visible flicker while the pipeline's models load synchronously.
        if island == nil {
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
        let executor = CommandExecutorHolder(makeExecutor())
        self.executor = executor

        do {
            let wake = WakeWordEngineHolder(try makeWakeEngine(modelsDir: modelsDir))
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
                    // launch there, then report the typed outcome to the UI on main.
                    // `completion` fires inline for terminal/editor, async for openApp.
                    executor.execute(cmd, prompt: prompt) { result in
                        if case .failure(let failure) = result {
                            Log.launch.error("launch failed: \(failure.localizedDescription, privacy: .public)")
                        }
                        // `prompt` is the user's words post wake-strip — the text
                        // the island hands back during the reveal beat.
                        Task { @MainActor in
                            self?.didFinish(cmd, transcript: prompt, result: result)
                        }
                    }
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
                          target: LaunchTarget, projectDirectory: String) {
        if !keywordLines.isEmpty { try? KeywordStore().save(lines: keywordLines) }
        var s = settings
        s.wakeKeywordsThreshold = threshold
        s.preferredTarget = target
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

    /// Tear down the live mic tap so onboarding's `EnrollmentRecorder` can't
    /// coexist with a second `AVAudioEngine` tap on the same hardware input.
    /// Called before the onboarding window opens (a no-op on first run, since the
    /// pipeline hasn't started). `restartPipeline()` reuses it for re-(boot).
    func suspendForOnboarding() {
        audio?.stop(); audio = nil
        wake = nil; transcriber = nil; capture = nil; voice = nil; executor = nil
        didStart = false
    }

    /// Tear down any running capture and (re)boot from the current settings —
    /// used after onboarding / re-run so we never stack a second mic tap.
    private func restartPipeline() {
        suspendForOnboarding()
        start()
    }

    var needsOnboarding: Bool { !settings.onboardingCompleted }

    /// The notch's state during onboarding (driven by the choreography):
    /// `empty` shell before training → `listening` (mascot arrives + equalizer)
    /// during training → `resting` (mascot lives in the notch) afterward.
    enum OnboardingIsland { case empty, listening, resting }
    func setOnboardingIsland(_ s: OnboardingIsland) {
        guard let island else { return }
        switch s {
        case .empty:     island.update(.onboardingPlaceholder)
        case .listening: island.update(IslandModel(state: .hot, transcript: nil))    // mascot + equalizer
        case .resting:   island.update(IslandModel(state: .armed, transcript: nil))   // mascot at rest
        }
    }

    /// Sticky user mute. Muting **releases the microphone** (engine stops, OS mic
    /// indicator goes off); unmuting re-acquires it. `setMuted` returns the mic's
    /// resulting live state, so a failed unmute restart keeps us truthfully muted
    /// rather than showing an "armed" mic the OS never re-granted. With no live
    /// pipeline (`audio == nil`) we honor the request optimistically so the next
    /// boot reflects the user's intent.
    func toggleMute() {
        let wantMuted = !userMuted
        let isLive = audio?.setMuted(wantMuted) ?? !wantMuted
        userMuted = !isLive
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
                                revealing: revealing,
                                failureMessage: machine.state == .failed ? lastFailure?.islandMessage : nil)
        // Resolve the user-selected mascot here (the single resolution point) so
        // the live notch always reflects the current `Settings`. The body color
        // stays a hex string across the app/Kit boundary; the panel (SwiftUI
        // layer) converts it to `Color` so AppController needn't import SwiftUI
        // (whose `Settings` scene type collides with our `Settings`).
        island.update(model,
                      mascot: MascotCatalog.byID(settings.mascotID),
                      mascotColorHex: settings.mascotColorHex,
                      mascotIdleAnimations: settings.mascotIdleAnimations,
                      controls: islandControls())
    }

    /// The hover-panel's actions + data, rebuilt each render so it always reflects
    /// the current target/mute state. Closures hop back to this main-actor controller.
    private func islandControls() -> IslandControls {
        // Persistent failure → either an actionable remedy (button) or a text hint.
        let failure: FailureItem? = lastFailure.map { f in
            FailureItem(message: f.errorDescription ?? "Last launch failed",
                        remedyLabel: f.settingsActionLabel,
                        remedy: f.settingsURL.map { url in { NSWorkspace.shared.open(url) } },
                        hint: f.settingsURL == nil ? f.recoverySuggestion : nil)
        }
        let recentItems = recent.entries.map {
            RecentItem(label: $0.label, failed: $0.outcome == .failed)
        }
        return IslandControls(
            isOff: machine.state == .off,
            isMuted: machine.state == .muted,
            targets: availableTargets,
            current: settings.preferredTarget,
            recent: recentItems,
            failure: failure,
            toggleMute: { [weak self] in self?.toggleMute() },
            setTarget: { [weak self] in self?.setPreferredTarget($0) },
            fixMic: { SystemSettingsLink.microphone.open() },
            openSettings: { [weak self] in self?.onOpenSettings?() },
            quit: { NSApplication.shared.terminate(nil) })
    }

    /// Hand-back beat after a launch attempt. The real launch already ran on the
    /// audio queue; this is the cosmetic reveal, now with a truthful branch: a
    /// success settles through "Launching Claude", a failure surfaces the error.
    private func didFinish(_ command: Command, transcript: String?,
                           result: Result<Void, LaunchFailure>) {
        let directory: String? = {
            switch command.kind {
            case .runCLI:
                // Editor targets open in the editor's focused window, not a fixed
                // folder — so don't claim a directory for them.
                if case .editor = command.target ?? settings.preferredTarget { return nil }
                return settings.projectDirectory
            case .openApp:  return nil
            case .runShell: return nil
            }
        }()

        let succeeded: Bool
        switch result {
        case .success:           succeeded = true;  lastFailure = nil
        case .failure(let f):    succeeded = false; lastFailure = f
        }

        // Recent is an honest outcome log — record both, marked.
        recentLog.record(label: command.label, directory: directory,
                         at: Date().timeIntervalSinceReferenceDate,
                         outcome: succeeded ? .launched : .failed)
        recent = recentLog

        // Reveal sequence: hold the transcript on the island for ~1.2s (state stays
        // `.hot`), then either launch (`→ .working`) or fail (`→ .failed`), then
        // settle back to the resting seam.
        let hasTranscript = !(transcript ?? "").isEmpty
        machine.apply(.heard(transcript ?? ""))   // records lastHeard while `.hot`
        revealing = hasTranscript
        updateIsland()                            // show transcript (or hold listening)

        Task { @MainActor in
            if hasTranscript {
                try? await Task.sleep(for: .milliseconds(1200))
            }
            self.revealing = false
            if succeeded {
                self.emit(.launching)
                try? await Task.sleep(for: .milliseconds(900))
            } else {
                self.emit(.launchFailed)
                try? await Task.sleep(for: .milliseconds(1500))   // hold the error a beat longer
            }
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
