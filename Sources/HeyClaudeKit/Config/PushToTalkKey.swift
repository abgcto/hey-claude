import CoreGraphics

/// The hold-to-talk trigger key. A small preset set (v1 — not an arbitrary
/// recorder). Each case carries the data the CGEventTap needs to decode
/// press/release from a `.flagsChanged` event: the physical keycode of the
/// (last) modifier in the combo, plus the modifier flag(s) that must be set
/// while it is held.
///
/// Bare modifiers (single Right Option / Right Command) are the default because
/// Wispr Flow refuses to bind bare modifiers — so they are guaranteed not to
/// collide with the user's Wispr hotkey. They type nothing, so the tap never
/// consumes the event.
public enum PushToTalkKey: String, Codable, CaseIterable, Sendable {
    case rightOption        // bare ⌥ (right) — default
    case rightCommand       // bare ⌘ (right)
    case controlOption      // ⌃⌥ chord
    case optionCommand      // ⌥⌘ chord
    case fnGlobe            // fn / 🌐 (built-in keyboards only)

    /// Human label for the Settings picker.
    public var label: String {
        switch self {
        case .rightOption:   return "Right Option (⌥)"
        case .rightCommand:  return "Right Command (⌘)"
        case .controlOption: return "Control + Option (⌃⌥)"
        case .optionCommand: return "Option + Command (⌥⌘)"
        case .fnGlobe:       return "fn / Globe key"
        }
    }

    /// Physical keycode (kVK_*) of the key whose `.flagsChanged` event marks the
    /// edge. For a chord this is the *second* key pressed; for a bare modifier it
    /// is that modifier. fn is reported via `.maskSecondaryFn`, keycode 63.
    public var keycode: Int64 {
        switch self {
        case .rightOption:   return 61   // kVK_RightOption
        case .rightCommand:  return 54   // kVK_RightCommand
        case .controlOption: return 61   // ⌥ completes the ⌃⌥ chord
        case .optionCommand: return 55   // kVK_Command completes ⌥⌘
        case .fnGlobe:       return 63   // kVK_Function
        }
    }

    /// True for single-modifier triggers (no chord). Bare modifiers type nothing,
    /// so the tap passes the event through rather than consuming it.
    public var isBareModifier: Bool {
        self == .rightOption || self == .rightCommand || self == .fnGlobe
    }

    /// The primary modifier flag that must be present while held. For a chord
    /// this is the flag of the *first* key pressed; `secondaryModifierFlag` is
    /// the second. `decodeEdge` checks both are present, so the primary/secondary
    /// split only documents intent — but keep it consistent with the tests.
    public var requiredModifierFlag: CGEventFlags {
        switch self {
        case .rightOption:   return .maskAlternate
        case .rightCommand:  return .maskCommand
        case .controlOption: return .maskControl      // ⌃ first; ⌥ is the secondary
        case .optionCommand: return .maskAlternate     // ⌥ first; ⌘ is the secondary
        case .fnGlobe:       return .maskSecondaryFn
        }
    }

    /// The second flag for a chord (nil for bare modifiers).
    public var secondaryModifierFlag: CGEventFlags? {
        switch self {
        case .controlOption: return .maskAlternate
        case .optionCommand: return .maskCommand
        default:             return nil
        }
    }
}
