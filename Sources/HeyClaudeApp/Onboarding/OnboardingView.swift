import SwiftUI
import HeyClaudeKit

/// First-run flow: welcome → mic → wake training → terminal/folder → ready.
/// Minimal, pure-black, monochrome (white accent, no coral) — locked from
/// internal design notes. The real notch island reacts
/// during training (wired in AppController, P4). 600×450 landscape window.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let onClose: () -> Void

    // Palette (pure black per spec; off-white ink).
    private let ink = Color(red: 0.953, green: 0.949, blue: 0.937)   // #f3f2ef
    private let inkSoft = Color(red: 0.612, green: 0.596, blue: 0.561)
    private let inkFaint = Color(red: 0.427, green: 0.416, blue: 0.392)
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
        .frame(width: 600, height: 450)
        .foregroundStyle(ink)
        .animation(.easeInOut(duration: 0.28), value: model.step)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            MascotView().frame(width: 66, height: 41)
            Text("Hey Claude").font(gs(30, .semibold)).tracking(-0.6).padding(.top, 24)
            Text("Talk to launch Claude Code.").font(gs(14)).foregroundStyle(inkSoft).padding(.top, 11)
            Spacer()
            actionButton("Get started") { model.goToMic() }
            Spacer().frame(height: 30)
        }
    }

    private var mic: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Listening for your voice").font(gs(22, .semibold)).tracking(-0.4)
            Text("Hey Claude waits quietly for the wake word, then opens Claude Code.")
                .font(gs(14)).foregroundStyle(inkSoft).multilineTextAlignment(.center)
                .frame(maxWidth: 300).padding(.top, 12)
            if !model.micGranted && !model.statusLine.isEmpty {
                Text(model.statusLine).font(gs(12)).foregroundStyle(inkSoft)
                    .multilineTextAlignment(.center).frame(maxWidth: 320).padding(.top, 16)
            }
            Spacer()
            VStack(spacing: 12) {
                actionButton("Allow microphone") { model.requestMicAndTrain() }
                Button("Not now") { model.skip(); onClose() }
                    .buttonStyle(.plain).font(gs(12.5, .medium)).foregroundStyle(inkFaint)
            }
            Spacer().frame(height: 30)
        }
    }

    private var train: some View {
        VStack(spacing: 0) {
            Spacer()
            if model.enrolling {
                ProgressView().controlSize(.small).tint(ink)
                Text(model.statusLine).font(gs(16, .medium)).padding(.top, 20)
            } else {
                Text("STEP \(min(model.capturedCount + 1, model.totalSamples)) OF \(model.totalSamples)")
                    .font(gs(10, .medium)).tracking(2).foregroundStyle(inkFaint)
                trainingIndicator.frame(height: 28).padding(.top, 30)
                if model.isRecording {
                    // The exact words to read aloud + the small action label.
                    Text("\u{201C}\(model.trainingPhrase)\u{201D}")
                        .font(gs(22, .semibold)).tracking(-0.4).multilineTextAlignment(.center)
                        .padding(.top, 34)
                    Text(model.trainingHint)
                        .font(gs(12.5)).foregroundStyle(inkFaint).padding(.top, 11)
                } else {
                    // Brief feedback after a capture — pops in, varies per rep,
                    // success draws a checkmark.
                    FeedbackPop(text: model.statusLine, success: model.lastCaptureOK,
                                font: gs(22, .semibold), color: ink)
                        .padding(.top, 34)
                }
            }
            Spacer()
            HStack(spacing: 9) {
                ForEach(0..<model.totalSamples, id: \.self) { i in
                    Circle().fill(i < model.capturedCount ? ink : hairStrong)
                        .frame(width: 7, height: 7)
                }
            }
            .opacity(model.enrolling ? 0 : 1)
            Spacer().frame(height: 34)
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
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            field("TERMINAL") {
                HStack(spacing: 0) {
                    ForEach(TerminalKind.allCases, id: \.self) { t in
                        Button { model.terminal = t } label: {
                            Text(t.rawValue).font(gs(13.5, .medium))
                                .foregroundStyle(model.terminal == t ? ink : inkSoft)
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .background(model.terminal == t ? Color.white.opacity(0.08) : .clear)
                        }.buttonStyle(.plain)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(hairStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
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
            Spacer()
            actionButton("Continue") { model.goToReady() }.frame(maxWidth: .infinity)
            Spacer().frame(height: 30)
        }
    }

    private var ready: some View {
        VStack(spacing: 0) {
            Spacer()
            MascotView().frame(width: 66, height: 41)
            Text("You\u{2019}re all set").font(gs(23, .semibold)).tracking(-0.4).padding(.top, 22)
            Text("Say \u{201C}Hey Claude\u{201D} anytime to launch Claude Code.")
                .font(gs(14)).foregroundStyle(inkSoft).multilineTextAlignment(.center)
                .frame(maxWidth: 320).padding(.top, 12)
            Spacer()
            actionButton("Done") { model.finish(); onClose() }
            Spacer().frame(height: 30)
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
            Text(title).font(gs(13.5, .medium)).foregroundStyle(.black)
                .padding(.horizontal, 26).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 9).fill(ink))
        }
        .buttonStyle(.plain)
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
