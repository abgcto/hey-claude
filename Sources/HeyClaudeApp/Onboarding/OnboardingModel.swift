import AppKit
import AVFoundation
import Observation
import SwiftUI
import HeyClaudeKit

/// Drives the first-run onboarding flow and runs wake-word enrollment.
/// UI-agnostic state holder: views render `step` + progress; this owns the mic
/// recording, plausibility gating, enrollment, and persistence handoff to
/// `AppController`. Model work (decode / fire-test) runs off the main actor.
@MainActor
@Observable
final class OnboardingModel {
    enum Step { case welcome, mic, train, setup, ready }

    /// `fullSetup` = first-run wizard. `retrainOnly` = just re-record the wake word
    /// from Settings: start at training, and on completion save the new keyword and
    /// close (no setup/ready steps, no mascot finale).
    enum Mode { case fullSetup, retrainOnly }
    let mode: Mode

    /// Set by the retrain window layer: called when retraining ends (saved or
    /// skipped) so the window closes and the pipeline resumes. Unused in fullSetup.
    var onRetrainComplete: (() -> Void)?

    private(set) var step: Step = .welcome
    private(set) var micGranted = false
    private(set) var micDenied = false       // permission previously denied/restricted
    private(set) var capturedCount = 0          // good samples so far (0...3)
    let totalSamples = 3
    private(set) var isRecording = false
    private(set) var isSpeaking = false      // true once speech is detected (→ equalizer)
    private(set) var statusLine = ""
    private(set) var lastCaptureOK = true    // last capture good (→ draw checkmark)
    private(set) var enrolling = false
    private(set) var enrollResult: WakeEnrollment.Result?

    /// Where Claude Code opens. Seeded from the smart default (the editor in use
    /// if detected, else Terminal); the setup step pre-selects it but lets the
    /// user choose any available target.
    var target: LaunchTarget
    var projectDirectory: String

    /// The auto-detected default captured at setup start — used to show the
    /// "Detected" badge only while the selection is still the smart pick.
    let detectedDefault: LaunchTarget

    /// Every target the user can choose at setup: installed terminals + ready
    /// editors. The detected default (`target`) is pre-selected among them.
    var availableTargets: [LaunchTarget] { controller.availableTargets }

    /// Editors installed but missing the Claude Code extension — listed disabled.
    var unavailableEditors: [EditorKind] { controller.unavailableEditors }

    /// Choose a target in the setup step.
    func selectTarget(_ t: LaunchTarget) { target = t }

    /// The real macOS app icon for a target, cached. nil if the app isn't found.
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    func appIcon(for t: LaunchTarget) -> NSImage? {
        let id = t.bundleID
        if let cached = iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = icon
        return icon
    }

    /// Show "Detected" only when the current pick is the auto-found editor.
    var showsDetectedBadge: Bool {
        guard target == detectedDefault, case .editor = target else { return false }
        return true
    }

    /// Set by the window layer: runs the finale (close the window at once, fly the
    /// mascot home, then commit on landing). nil → commit immediately.
    var onDone: (() -> Void)?

    private unowned let controller: AppController
    private var samples: [WakeEnrollment.Sample] = []
    private var recorder: EnrollmentRecorder?
    private var attempts = 0
    private let maxAttempts = 8

    init(controller: AppController, mode: Mode = .fullSetup) {
        self.controller = controller
        self.mode = mode
        let detected = controller.settings.preferredTarget
        self.detectedDefault = detected
        self.target = detected
        self.projectDirectory = controller.settings.projectDirectory
    }

    /// Entry point for `retrainOnly`: jump straight to training if the mic is
    /// already authorized (the common case for an existing user), otherwise route
    /// through the mic-grant step first.
    func startRetrain() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            micGranted = true
            step = .train
            beginTraining()
        } else {
            goToMic()
        }
    }

    private var kwsDir: URL? {
        controller.modelsDirectory?
            .appendingPathComponent("sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01")
    }

    // MARK: - Navigation

    func goToMic() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            // Already granted (e.g. macOS pre-prompted at launch) — skip the
            // button step entirely; go straight to training.
            micGranted = true
            step = .train
            beginTraining()
        case .denied, .restricted:
            micDenied = true
            statusLine = "Microphone access is needed — enable it in System Settings \u{25B8} Privacy \u{25B8} Microphone."
            step = .mic
        default:
            step = .mic
        }
    }

    func requestMicAndTrain() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
            step = .train
            beginTraining()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    self.micGranted = granted
                    guard granted else {
                        self.micDenied = true
                        self.statusLine = "Microphone access is needed — enable it in System Settings ▸ Privacy ▸ Microphone."
                        return
                    }
                    self.step = .train
                    self.beginTraining()
                }
            }
        case .denied, .restricted:
            // requestAccess no-ops once denied — surface a real settings affordance.
            micDenied = true
            statusLine = "Microphone access is needed — enable it in System Settings ▸ Privacy ▸ Microphone."
        @unknown default:
            micDenied = true
            statusLine = "Microphone access is needed — enable it in System Settings ▸ Privacy ▸ Microphone."
        }
    }

    /// Open System Settings ▸ Privacy ▸ Microphone so the user can grant access.
    func openMicSettings() {
        SystemSettingsLink.microphone.open()
    }

    /// Re-check on window refocus: if the user granted mic access in System
    /// Settings and came back, advance straight to training.
    func revalidateMicIfWaiting() {
        guard step == .mic,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        micDenied = false
        micGranted = true
        step = .train
        beginTraining()
    }

    // MARK: - Training

    /// The exact words to say (shown big, in quotes). The third rep gives a real
    /// example sentence rather than asking the user to improvise.
    var trainingPhrase: String {
        samples.count < 2 ? "Hey Claude" : "Hey Claude, open my project"
    }

    /// The small action label under the phrase.
    var trainingHint: String {
        switch samples.count {
        case 0:  return "Say it out loud"
        case 1:  return "Once more"
        default: return "Read it aloud, just like that"
        }
    }

    func beginTraining() {
        // Idempotent: a grant can advance us here twice (the requestAccess
        // completion and the window-refocus re-check can both land), so stop any
        // in-flight recorder before starting fresh — never stack two mic taps.
        recorder?.stop(); recorder = nil
        samples.removeAll(); capturedCount = 0; attempts = 0
        recordNext()   // notch stays the empty shell; the mascot flies home on "Done"
    }

    private func recordNext() {
        guard samples.count < totalSamples else { runEnrollment(); return }
        guard attempts < maxAttempts else {   // give up re-asking; enroll with what we have
            if samples.count >= 2 { runEnrollment() } else { statusLine = "Having trouble hearing you — you can skip for now." }
            return
        }
        attempts += 1
        statusLine = ""        // clear prior "Got it ✓"; the view shows phrase + hint
        isRecording = true
        isSpeaking = false
        let kind: WakeEnrollment.Sample.Kind = samples.count < 2 ? .isolated : .natural
        let kws = kwsDir
        let rec = EnrollmentRecorder(endpointSilenceMs: controller.settings.endpointSilenceMs)
        recorder = rec
        do {
            try rec.record(
                onSpeechStart: { Task { @MainActor in self.isSpeaking = true } },
                onClip: { clip in Task { @MainActor in self.handleClip(clip, kind: kind, kwsDir: kws) } })
        } catch {
            isRecording = false
            statusLine = "Mic error — try again"
        }
    }

    private func handleClip(_ clip: [Float], kind: WakeEnrollment.Sample.Kind, kwsDir: URL?) {
        isRecording = false
        isSpeaking = false
        // Stop explicitly before releasing — EnrollmentRecorder's self-stop is
        // [weak self] async, so if we nil the ref first it can be deallocated
        // before stop() runs, leaving AVAudioEngine running without a proper
        // teardown. The next rep then creates a fresh engine whose first
        // inputNode query triggers a repeat system mic-permission dialog.
        recorder?.stop()
        recorder = nil
        guard let kwsDir else { statusLine = "Models missing"; return }
        Task.detached {
            let tokens = KwsDebug.decodeTokens(modelDir: kwsDir, samples: clip).tokens
            let plausible = WakeEnrollment.isPlausibleWake(tokens: tokens)
            await MainActor.run {
                if plausible {
                    self.samples.append(.init(audio: clip, kind: kind))
                    self.capturedCount = self.samples.count
                    let cheers = ["Got it", "Nice", "Locked in"]
                    self.statusLine = cheers[min(self.samples.count - 1, cheers.count - 1)]
                    self.lastCaptureOK = true
                } else {
                    self.statusLine = "Didn\u{2019}t catch that — try again"
                    self.lastCaptureOK = false
                }
            }
            try? await Task.sleep(for: .milliseconds(550))   // brief beat between reps
            await MainActor.run { self.recordNext() }
        }
    }

    private func runEnrollment() {
        enrolling = true
        statusLine = "Tuning to your voice\u{2026}"
        guard let kwsDir else { enrolling = false; advanceAfterTraining(); return }
        let captured = samples
        let score = controller.settings.wakeKeywordsScore
        Task.detached {
            let enroll = WakeEnrollment(
                decode: { s in KwsDebug.decodeTokens(modelDir: kwsDir, samples: s).tokens },
                fires: { lines, threshold, audio in
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("hc-enroll-kw.txt")
                    try? (lines.joined(separator: "\n") + "\n")
                        .write(to: tmp, atomically: true, encoding: .utf8)
                    guard let e = try? WakeWordEngine(modelDir: kwsDir, keywordsFile: tmp,
                                                      keywordsThreshold: threshold, keywordsScore: score)
                    else { return false }
                    return e.detects(in: audio)
                })
            let result = enroll.enroll(samples: captured)
            await MainActor.run {
                self.enrollResult = result
                self.enrolling = false
                if self.mode == .retrainOnly {
                    self.controller.retrainWakeWord(keywordLines: result.keywordLines,
                                                    threshold: result.threshold)
                }
                self.advanceAfterTraining()
            }
        }
    }

    /// After enrollment: the full wizard moves on to setup; a retrain saves (above)
    /// then signals the window to close + resume listening.
    private func advanceAfterTraining() {
        switch mode {
        case .fullSetup:   step = .setup
        case .retrainOnly: onRetrainComplete?()
        }
    }

    // MARK: - Setup → Ready → Finish

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: projectDirectory)
        if panel.runModal() == .OK, let url = panel.url { projectDirectory = url.path }
    }

    func goToReady() { step = .ready }

    /// True from "Done" until dismissal — the Ready screen hides its mascot so the
    /// flying one is the only one (a clean hand-off).
    private(set) var flying = false

    /// Done: hand off to the window layer's finale (close window + fly + commit).
    /// With no finale hook, commit immediately.
    func finish() {
        if let onDone {
            flying = true
            onDone()
        } else {
            commitFinish()
        }
    }

    /// Persist enrollment + setup choices and boot the resident island/pipeline.
    /// Called by the finale once the mascot lands.
    func commitFinish() {
        controller.finishOnboarding(
            keywordLines: enrollResult?.keywordLines ?? [],
            threshold: enrollResult?.threshold ?? controller.settings.wakeKeywordsThreshold,
            target: target,
            projectDirectory: projectDirectory)
    }

    /// Skip the whole flow — use the bundled default keyword. Stops any in-flight
    /// enrollment recorder first so its mic tap doesn't outlive the window.
    func skip() {
        recorder?.stop()
        recorder = nil
        controller.completeOnboarding()
    }

    /// Skip only the voice training and continue to setup. Enrollment is left
    /// empty, so finishing falls back to the bundled wake word — but the user
    /// still gets to choose where Claude Code opens + the project folder.
    func skipTraining() {
        recorder?.stop()
        recorder = nil
        enrollResult = nil
        switch mode {
        case .fullSetup:   step = .setup
        case .retrainOnly: onRetrainComplete?()   // cancel — close + resume (nothing saved)
        }
    }
}
