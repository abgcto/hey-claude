import Foundation

/// Pure mapping from AppState (+ optional transcript) to what the island shows.
/// Keeps all "which content, which treatment" logic testable, out of the view.
public struct IslandModel: Equatable {
    public enum Shape: Equatable { case seam, expanded }
    public enum Content: Equatable { case none, listening, transcript(String), launching }

    public let shape: Shape
    public let content: Content
    public let showsSlash: Bool   // muted
    public let dimmed: Bool       // paused
    public let hidden: Bool       // off

    public init(state: AppState, transcript: String?, revealing: Bool = false) {
        switch state {
        case .off:
            shape = .seam; content = .none; showsSlash = false; dimmed = false; hidden = true
        case .armed:
            shape = .seam; content = .none; showsSlash = false; dimmed = false; hidden = false
        case .muted:
            shape = .seam; content = .none; showsSlash = true; dimmed = false; hidden = false
        case .paused:
            shape = .expanded; content = .none; showsSlash = false; dimmed = true; hidden = false
        case .hot:
            shape = .expanded; showsSlash = false; dimmed = false; hidden = false
            if revealing, let t = transcript, !t.isEmpty { content = .transcript(t) }
            else { content = .listening }
        case .working:
            shape = .expanded; content = .launching; showsSlash = false; dimmed = false; hidden = false
        }
    }
}
