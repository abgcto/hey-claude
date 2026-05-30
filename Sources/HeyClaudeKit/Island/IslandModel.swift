import Foundation

/// Pure mapping from AppState (+ optional transcript) to what the island shows.
/// Keeps all "which content, which treatment" logic testable, out of the view.
public struct IslandModel: Equatable {
    public enum Shape: Equatable { case seam, expanded }
    public enum Content: Equatable { case none, listening, transcript(String), launching }

    /// The single source of truth the view switches on to render the right-of-camera
    /// content, size its right area, and pick its height. One case per approved
    /// dynamic-island state (see internal design notes).
    public enum Visual: Equatable {
        case hidden                 // off — island not drawn
        case idle                   // armed — calm dim dot
        case listening              // hot — pulsing live dot + coral equalizer
        case transcript(String)     // hot + revealing + text — taller band, "● HEARING" + line
        case launching(String)      // working — taller band, "→ LAUNCHING" + the line (may be "")
        case muted                  // mic off — slashed-mic glyph, dimmed
        case paused                 // call-guard hold — violet pause glyph + label, dimmed
    }

    public let shape: Shape
    public let content: Content
    public let visual: Visual
    public let showsSlash: Bool   // muted
    public let dimmed: Bool       // paused / muted treatment
    public let hidden: Bool       // off

    public init(state: AppState, transcript: String?, revealing: Bool = false) {
        switch state {
        case .off:
            shape = .seam; content = .none; visual = .hidden
            showsSlash = false; dimmed = false; hidden = true
        case .armed:
            shape = .seam; content = .none; visual = .idle
            showsSlash = false; dimmed = false; hidden = false
        case .muted:
            shape = .seam; content = .none; visual = .muted
            showsSlash = true; dimmed = false; hidden = false
        case .paused:
            shape = .expanded; content = .none; visual = .paused
            showsSlash = false; dimmed = true; hidden = false
        case .hot:
            showsSlash = false; dimmed = false; hidden = false
            if revealing, let t = transcript, !t.isEmpty {
                shape = .expanded; content = .transcript(t); visual = .transcript(t)
            } else {
                shape = .expanded; content = .listening; visual = .listening
            }
        case .working:
            // Launching reuses the reveal band: it carries the transcript so the
            // spoken line stays visible through the hand-off (kicker → LAUNCHING),
            // and the band never resizes between hearing and launching.
            shape = .expanded; content = .launching; visual = .launching(transcript ?? "")
            showsSlash = false; dimmed = false; hidden = false
        }
    }
}
