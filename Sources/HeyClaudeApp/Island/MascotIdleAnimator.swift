import SwiftUI

/// Ambient "lives in the notch" idle motion for the mascot. Split out of
/// `IslandView` (already large) so the scheduling/choreography lives in one
/// focused place. The view reads `transform` + `blinking` and applies them; the
/// driver owns the randomized timing.
///
/// Active ONLY while armed + the user's "Playful animations" preference is on +
/// system Reduce Motion is off — `IslandView` folds those into one `active` flag.

/// The animatable idle pose, layered on top of the mascot's resting transform.
struct IdleTransform: Equatable {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0      // negative = up (mascot is bottom-anchored)
    var rotation: Double = 0      // degrees, bottom-anchored

    static let identity = IdleTransform()
    /// Left↔right inverse, used to make oscillating gestures (wiggle/wobble) swing.
    var mirrored: IdleTransform {
        IdleTransform(scaleX: scaleX, scaleY: scaleY, offsetX: -offsetX, offsetY: offsetY, rotation: -rotation)
    }
}

/// One small idle gesture. Pure data: a peak pose + whether it swings through the
/// mirror. The `MascotIdleDriver` owns the actual choreography so the transform
/// stays encapsulated. Weights bias the random pick toward subtle moves.
enum MascotGesture: CaseIterable {
    case hop, peekLeft, peekRight, wiggle, tilt, stretch, nod, wobble

    /// The pose the gesture springs to before settling back to identity.
    var peak: IdleTransform {
        switch self {
        case .hop:       return IdleTransform(offsetY: -4)
        case .peekLeft:  return IdleTransform(offsetX: -3, rotation: -4)
        case .peekRight: return IdleTransform(offsetX: 3, rotation: 4)
        case .wiggle:    return IdleTransform(rotation: 6)
        case .tilt:      return IdleTransform(rotation: 9)
        case .stretch:   return IdleTransform(scaleX: 0.93, scaleY: 1.12)
        case .nod:       return IdleTransform(offsetY: 2)
        case .wobble:    return IdleTransform(offsetX: 1.5, rotation: 7)
        }
    }

    /// Swing through the mirrored pose (a shimmy) before settling.
    var oscillates: Bool {
        switch self {
        case .wiggle, .wobble: return true
        default:               return false
        }
    }

    /// Relative likelihood — subtle moves common, big ones (stretch) rare.
    var weight: Int {
        switch self {
        case .peekLeft, .peekRight, .tilt, .nod: return 3
        case .hop, .wiggle, .wobble:             return 2
        case .stretch:                           return 1
        }
    }

    /// Weighted random pick. `Int.random` is fine here (app code, not a workflow).
    static func weightedRandom() -> MascotGesture {
        let pool = allCases.flatMap { g in Array(repeating: g, count: g.weight) }
        return pool.randomElement() ?? .hop
    }
}

@MainActor
@Observable
final class MascotIdleDriver {
    /// The current idle pose (springs to a gesture peak, then back to identity).
    private(set) var transform: IdleTransform = .identity
    /// True for the ~0.12s an eye-blink is held closed.
    private(set) var blinking = false

    // Idle cadence (seconds between fires), tuned live in the notch: a lively
    // gesture every couple seconds + a near-natural blink rhythm read as "alive"
    // better than a sparse cadence did. Adjust here if it ever feels too busy.
    private let gestureInterval: ClosedRange<Double> = 2...4
    private let blinkInterval: ClosedRange<Double> = 1.5...3

    private var active = false
    private var canBlink = false
    private var gestureWork: DispatchWorkItem?
    private var blinkWork: DispatchWorkItem?
    private var reopenWork: DispatchWorkItem?

    /// Idempotent start/stop. `canBlink` is false for mascots without `"O"` eyes
    /// (they still do the transform gestures, just no blink).
    func update(active: Bool, canBlink: Bool) {
        let blinkEnabled = canBlink && !self.canBlink
        let blinkDisabled = !canBlink && self.canBlink
        self.canBlink = canBlink
        guard active != self.active else {
            // Already running: reconcile the blink loop if the mascot's blink
            // capability changed under us (e.g. switching from a no-"O"-eye mascot
            // like Happy to Classic while idle). Without this the new mascot would
            // not blink until the next armed cycle.
            if active {
                if blinkEnabled, blinkWork == nil { scheduleBlink() }
                if blinkDisabled { stopBlink() }
            }
            return
        }
        self.active = active
        if active {
            scheduleGesture()
            scheduleBlink()
        } else {
            stop()
        }
    }

    private func stopBlink() {
        blinkWork?.cancel();  blinkWork = nil
        reopenWork?.cancel(); reopenWork = nil
        blinking = false
    }

    private func stop() {
        gestureWork?.cancel();  gestureWork = nil
        blinkWork?.cancel();    blinkWork = nil
        reopenWork?.cancel();   reopenWork = nil
        blinking = false
        withAnimation(.easeOut(duration: 0.3)) { transform = .identity }
    }

    // MARK: gestures (~every 2–4s)

    private func scheduleGesture() {
        let work = DispatchWorkItem { [weak self] in self?.fireGesture() }
        gestureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: gestureInterval), execute: work)
    }

    private func fireGesture() {
        guard active else { return }
        play(MascotGesture.weightedRandom())
        scheduleGesture()
    }

    /// Spring to the gesture's peak, then settle back — swinging through the
    /// mirror first for oscillating gestures so wiggle/wobble shimmy.
    private func play(_ gesture: MascotGesture) {
        let toPeak = Animation.spring(response: 0.32, dampingFraction: 0.55)
        let settle = Animation.spring(response: 0.5, dampingFraction: 0.66)
        withAnimation(toPeak) { transform = gesture.peak }
        if gesture.oscillates {
            after(0.16) { [weak self] in
                withAnimation(toPeak) { self?.transform = gesture.peak.mirrored }
                self?.after(0.16) { withAnimation(settle) { self?.transform = .identity } }
            }
        } else {
            after(0.2) { [weak self] in withAnimation(settle) { self?.transform = .identity } }
        }
    }

    // MARK: blink (~every 1.5–3s)

    private func scheduleBlink() {
        guard canBlink else { return }
        let work = DispatchWorkItem { [weak self] in self?.fireBlink() }
        blinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: blinkInterval), execute: work)
    }

    private func fireBlink() {
        guard active, canBlink else { return }
        blinking = true
        let reopen = DispatchWorkItem { [weak self] in self?.blinking = false }
        reopenWork = reopen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: reopen)
        scheduleBlink()
    }

    /// Main-queue delay that drops if the driver stops in the meantime.
    private func after(_ delay: TimeInterval, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.active == true else { return }
            body()
        }
    }
}
