import Foundation

/// Picks the default launch target for a fresh install — once. Conservative:
/// only overrides the terminal fallback when exactly one editor is clearly
/// active, so an ambiguous environment never guesses wrong.
/// See internal design notes §5.7.
public enum DefaultTargetResolver {
    /// - candidates: editors installed AND extension-ready (from `EditorAvailability`).
    /// - active: candidates the user is actively using (lockfile `ideName` match
    ///   and/or the editor app running).
    /// - fallback: terminal target when the editor signal is absent or ambiguous.
    public static func resolve(candidates: Set<EditorKind>,
                               active: Set<EditorKind>,
                               fallback: TerminalKind = .terminalApp) -> LaunchTarget {
        let activeCandidates = active.intersection(candidates)
        if activeCandidates.count == 1, let only = activeCandidates.first {
            return .editor(only)
        }
        return .terminal(fallback)
    }

    /// Maps a list of lockfile `ideName`s onto the candidate editors they denote.
    public static func activeEditors(fromIdeNames ideNames: [String],
                                     among candidates: Set<EditorKind>) -> Set<EditorKind> {
        Set(candidates.filter { editor in ideNames.contains { editor.matchesIdeName($0) } })
    }
}
