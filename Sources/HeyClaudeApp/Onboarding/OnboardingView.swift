import SwiftUI
import HeyClaudeKit

/// First-run flow: welcome → mic → wake training → terminal/folder → ready.
/// Minimal, pure-black, monochrome (white accent, no coral) — locked from
/// internal design notes. The real notch island reacts
/// during training (wired in AppController, P4). 600×450 landscape window.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    /// A disabled editor the user tapped to see *why* it's unavailable. Drives the
    /// name/subtitle area without changing the actual launch target. nil = normal.
    @State private var inspected: EditorKind?

    // Palette (pure black per spec; off-white ink).
    private let ink = Color(red: 0.953, green: 0.949, blue: 0.937)   // #f3f2ef
    private let inkSoft = Color(red: 0.612, green: 0.596, blue: 0.561)
    private let inkFaint = Color(red: 0.48, green: 0.47, blue: 0.445)   // ~4.8:1 on black → WCAG AA
    private let hairStrong = Color(red: 0.216, green: 0.216, blue: 0.239)

    /// General Sans, with graceful system fallback if the font isn't registered.
    /// The OTF weights ship as SEPARATE families ("General Sans Medium" /
    /// "…Semibold"), so we pick the family by name rather than via `.weight()`.
    private func gs(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let family: String
        switch weight {
        case .semibold, .bold: family = "General Sans Semibold"
        case .medium:          family = "General Sans Medium"
        default:               family = "General Sans"
        }
        return .custom(family, size: size)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                switch model.step {
                case .welcome: welcome
                case .mic:     mic
                case .train:   train
                case .setup:   setup
                case .ready:   ready
                }
            }
            .padding(.horizontal, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 520)
        .foregroundStyle(ink)
        .animation(.easeInOut(duration: 0.28), value: model.step)
    }

    // MARK: - Steps

    /// Constant inset so the primary control sits at the SAME height on every step
    /// (no vertical jump as you advance). Content is centered in the space above.
    private let footerInset: CGFloat = 36

    private func scaffold<C: View, F: View>(
        @ViewBuilder content: () -> C,
        @ViewBuilder footer: () -> F
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            content()
            Spacer(minLength: 24)
            footer().padding(.bottom, footerInset)
        }
    }

    private var welcome: some View {
        scaffold {
            VStack(spacing: 0) {
                MascotView(mascot: MascotCatalog.byID("classic")).frame(width: 66, height: 41)
                Text("Hey Claude").font(gs(28, .medium)).tracking(-0.6).padding(.top, 24)
                Text("Talk to launch Claude Code.").font(gs(14)).foregroundStyle(inkSoft).padding(.top, 11)
            }
        } footer: {
            actionButton("Get started") { model.goToMic() }
        }
    }

    private var mic: some View {
        scaffold {
            VStack(spacing: 0) {
                Image(systemName: "mic.fill").font(.system(size: 26, weight: .medium))
                    .accessibilityHidden(true)
                Text("Launch Claude with your voice").font(gs(22, .medium)).tracking(-0.4).padding(.top, 22)
                Text("Hey Claude waits quietly for the wake word, then opens Claude Code.")
                    .font(gs(14)).foregroundStyle(inkSoft).multilineTextAlignment(.center)
                    .frame(maxWidth: 300).padding(.top, 12)
            }
        } footer: {
            // Privacy reassurance (the ask state) or, once denied, the path to fix
            // it in System Settings — sits just above the constant-height button.
            //
            // No "Not now" escape: Hey Claude is a voice product — without mic it
            // can't do anything. Granting is the only forward path. Closing the
            // window leaves onboarding pending (re-prompts next launch), so a
            // dismissal defers rather than ditching into a dead, mic-denied app.
            VStack(spacing: 16) {
                if model.micDenied {
                    Text(model.statusLine.isEmpty
                         ? "Enable microphone access in System Settings \u{25B8} Privacy \u{25B8} Microphone."
                         : model.statusLine)
                        .font(gs(12)).foregroundStyle(inkSoft)
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                    actionButton("Open System Settings") { model.openMicSettings() }
                } else {
                    Text("\(Image(systemName: "lock.fill"))  Audio never leaves your Mac. It all runs on-device.")
                        .font(gs(12)).foregroundStyle(inkFaint)
                        .accessibilityLabel("Audio never leaves your Mac. It all runs on-device.")
                    actionButton("Allow microphone") { model.requestMicAndTrain() }
                }
            }
        }
    }

    private var train: some View {
        scaffold {
            Group {
                if model.enrolling {
                    VStack(spacing: 0) {
                        ProgressView().controlSize(.small).tint(ink)
                        Text(model.statusLine).font(gs(16, .medium)).padding(.top, 20)
                    }
                } else {
                    VStack(spacing: 0) {
                        Text("STEP \(min(model.capturedCount + 1, model.totalSamples)) OF \(model.totalSamples)")
                            .font(gs(10, .medium)).tracking(2).foregroundStyle(inkFaint)
                        trainingIndicator.frame(height: 28).padding(.top, 30)
                        // Fixed-height well so the prompt (phrase + hint, up to two
                        // lines) and the one-line "Got it ✓" feedback occupy the SAME
                        // space — the cluster never resizes/shifts between reps.
                        Group {
                            if model.isRecording {
                                VStack(spacing: 11) {
                                    // The exact words to read aloud + the small action label.
                                    Text("\u{201C}\(model.trainingPhrase)\u{201D}")
                                        .font(gs(22, .medium)).tracking(-0.4).multilineTextAlignment(.center)
                                    Text(model.trainingHint)
                                        .font(gs(12.5)).foregroundStyle(inkFaint)
                                }
                            } else {
                                // Brief feedback after a capture — pops in, varies per
                                // rep, success draws a checkmark.
                                FeedbackPop(text: model.statusLine, success: model.lastCaptureOK,
                                            font: gs(22, .medium), color: ink)
                            }
                        }
                        .frame(height: 88)
                        .padding(.top, 34)
                    }
                }
            }
        } footer: {
            VStack(spacing: 18) {
                HStack(spacing: 9) {
                    ForEach(0..<model.totalSamples, id: \.self) { i in
                        Circle().fill(i < model.capturedCount ? ink : hairStrong)
                            .frame(width: 7, height: 7)
                    }
                }
                .opacity(model.enrolling ? 0 : 1)
                if !model.enrolling {
                    Button("Skip for now") { model.skipTraining() }
                        .buttonStyle(.plain).font(gs(12.5, .medium)).foregroundStyle(inkFaint)
                }
            }
        }
    }

    /// Waiting for you to speak → flashing dots. Speech detected → equalizer.
    @ViewBuilder private var trainingIndicator: some View {
        if model.isSpeaking {
            Equalizer(color: ink)
        } else {
            FlashingDots(color: ink)
        }
    }

    private var setup: some View {
        scaffold {
            VStack(alignment: .leading, spacing: 28) {
                // Icon-switcher selector for where Claude Code opens.
                field("CLAUDE CODE OPENS IN") { targetPicker }
                    .padding(.bottom, 18)   // extra air before the folder chooser
                field("PROJECT FOLDER") {
                    HStack(spacing: 11) {
                        Text(model.projectDirectory).font(gs(14)).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button("Choose\u{2026}") { model.chooseFolder() }
                            .buttonStyle(.plain).font(gs(12.5, .medium)).foregroundStyle(inkSoft)
                    }
                    .padding(.vertical, 11)
                    .overlay(Rectangle().fill(hairStrong).frame(height: 1), alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            actionButton("Continue") { model.goToReady() }
        }
    }

    private var ready: some View {
        scaffold {
            VStack(spacing: 0) {
                MascotView(mascot: MascotCatalog.byID("classic")).frame(width: 66, height: 41)
                    .opacity(model.flying ? 0 : 1)   // hand off to the flying mascot
                Text("You\u{2019}re all set").font(gs(28, .medium)).tracking(-0.4).padding(.top, 22)
                Text("Say \u{201C}Hey Claude\u{201D} anytime to launch Claude Code.")
                    .font(gs(14)).foregroundStyle(inkSoft).multilineTextAlignment(.center)
                    .frame(maxWidth: 320).padding(.top, 12)
            }
        } footer: {
            actionButton("Done") { model.finish() }   // flies home, then commits + closes
        }
    }

    // MARK: - Bits

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(gs(10, .medium)).tracking(1.6).foregroundStyle(inkFaint)
            content()
        }
    }

    private func actionButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(gs(15, .medium)).foregroundStyle(.black)
                .padding(.horizontal, 28).padding(.vertical, 11)   // hugs the label
                .background(RoundedRectangle(cornerRadius: 9).fill(ink))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)   // Return advances the wizard
    }

    // MARK: - Target picker (icon switcher: app-icon row, selected grows)

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ForEach(Array(model.availableTargets.enumerated()), id: \.offset) { _, t in
                    iconButton(t)
                }
                ForEach(Array(model.unavailableEditors.enumerated()), id: \.offset) { _, e in
                    disabledIcon(e)
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.target)
            .animation(.easeOut(duration: 0.18), value: inspected)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(inspected?.rawValue ?? model.target.label)
                        .font(gs(18, .semibold)).tracking(-0.2)
                        .foregroundStyle(inspected == nil ? ink : inkSoft)
                    if inspected == nil, model.showsDetectedBadge {
                        Text("DETECTED").font(gs(9, .semibold)).tracking(1.4).foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ink))
                    }
                }
                Text(inspected == nil ? selectedSubtitle
                                      : "Needs the Claude Code extension to use it.")
                    .font(gs(12.5)).foregroundStyle(inspected == nil ? inkSoft : inkFaint)
            }
        }
    }

    /// One selectable app icon. The selected one sits in a soft rounded well and
    /// grows slightly (dock / Launchpad-style emphasis).
    private func iconButton(_ t: LaunchTarget) -> some View {
        let selected = inspected == nil && model.target == t
        return Button { model.selectTarget(t); inspected = nil } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(selected ? ink.opacity(0.08) : .clear)
                appIcon(t, size: selected ? 50 : 42)
            }
            .frame(width: 66, height: 66)
        }
        .buttonStyle(.plain)
        .help(t.label)
    }

    /// An installed editor that can't be used yet. The real icon with a warning
    /// badge on its top-right corner. Clickable: tapping it shows the reason in
    /// the text area; a dashed well marks it as "viewing".
    private func disabledIcon(_ e: EditorKind) -> some View {
        let viewing = inspected == e
        return Button { inspected = viewing ? nil : e } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(hairStrong, style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .opacity(viewing ? 1 : 0)
                appIcon(.editor(e), size: 42)
                    .opacity(viewing ? 1 : 0.6)
                    .overlay(alignment: .topTrailing) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(white: 0.42))
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(.black, lineWidth: 1.5))
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(white: 0.95))
                        }
                        .frame(width: 16, height: 16)
                        .offset(x: 6, y: -6)
                    }
            }
            .frame(width: 66, height: 66)
        }
        .buttonStyle(.plain)
        .help("\(e.rawValue) — needs the Claude Code extension")
    }

    @ViewBuilder
    private func appIcon(_ t: LaunchTarget, size: CGFloat) -> some View {
        if let icon = model.appIcon(for: t) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22).fill(ink.opacity(0.08))
                .frame(width: size, height: size)
        }
    }

    private var selectedSubtitle: String {
        switch model.target {
        case .terminal: return "Opens a fresh session in your project folder."
        case .editor:   return "Edits land right inside the editor."
        }
    }
}

/// A checkmark that draws itself (down-stroke then up-stroke) via trim.
private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// The capture confirmation — the cheer springs in and (on success) the
/// checkmark draws itself. Re-created each rep, so the animation re-fires.
private struct FeedbackPop: View {
    let text: String
    let success: Bool
    let font: Font
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    @State private var drawn = false
    var body: some View {
        HStack(spacing: 9) {
            Text(text).font(font).tracking(-0.4)
            if success {
                CheckShape()
                    .trim(from: 0, to: (reduce || drawn) ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
            }
        }
        .scaleEffect(reduce ? 1 : (shown ? 1 : 0.7))
        .opacity(shown ? 1 : 0)
        .onAppear {
            if reduce { shown = true; drawn = true; return }
            // Two beats: the text pops in first, then the checkmark draws.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.66)) { shown = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.34)) { drawn = true }
        }
    }
}

/// Three dots flashing in sequence — the "waiting to hear you" state.
private struct FlashingDots: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(color)
                    .frame(width: 8, height: 8)
                    .opacity(reduce ? 0.6 : (on ? 1 : 0.22))
                    .animation(reduce ? nil :
                        .easeInOut(duration: 0.62).repeatForever().delay(Double(i) * 0.16), value: on)
            }
        }
        .onAppear { on = true }
    }
}

/// Five bars bouncing — the "I hear you talking" state.
private struct Equalizer: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var up = false
    private let peaks: [CGFloat] = [16, 26, 20, 28, 14]
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<peaks.count, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 3.5, height: reduce ? peaks[i] * 0.6 : (up ? peaks[i] : 6))
                    .animation(reduce ? nil :
                        .easeInOut(duration: 0.42).repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.07), value: up)
            }
        }
        .frame(height: 28)
        .onAppear { up = true }
    }
}
