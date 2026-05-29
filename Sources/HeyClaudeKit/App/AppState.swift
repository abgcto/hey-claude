import Foundation

/// The six perceptual buckets the icon + island + menu all render.
public enum AppState: Equatable, Sendable {
    case off        // not running / mic denied
    case armed      // idle, wake-listening (resting)
    case hot        // wake fired → capturing
    case working    // transcribing + launching
    case muted      // user-muted (sticky)
    case paused     // call-guard auto-pause (temporary)
}

/// Events the pipeline emits.
public enum AppEvent: Equatable, Sendable {
    case wakeFired
    case heard(String)        // transcript revealed (or empty for bare launch)
    case launching
    case settled              // action done → back to resting
    case muted, unmuted
    case callPaused, callResumed
    case micDenied, micGranted
}

/// Pure state machine. Mute and call-pause take precedence over the
/// listen/hot/working cycle. Not thread-safe; the AppController drives it on
/// the main actor.
public final class AppStateMachine {
    public private(set) var state: AppState = .armed
    public private(set) var lastHeard: String? = nil

    public init() {}

    public func apply(_ event: AppEvent) {
        switch event {
        case .micDenied: state = .off
        case .micGranted: if state == .off { state = .armed }
        case .muted: state = .muted
        case .unmuted: if state == .muted { state = .armed }
        case .callPaused: if state != .muted { state = .paused }
        case .callResumed: if state == .paused { state = .armed }
        case .wakeFired:
            if state == .armed { state = .hot }            // ignored while muted/paused/off
        case .heard(let text):
            if state == .hot { lastHeard = text.isEmpty ? nil : text }
        case .launching:
            if state == .hot { state = .working }
        case .settled:
            if state == .working || state == .hot { state = .armed }
        }
    }
}
