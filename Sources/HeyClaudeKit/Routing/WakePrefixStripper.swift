import Foundation

/// Strips the leading wake phrase from a full transcript, returning only the
/// trailing command (or nil for a bare "hey claude"). The ASR renders "claude"
/// as "cloud"/"claud"/etc., so we match a small variant set. Promoted from the
/// Phase 1 spike (Sources/heyclaude-spike) into tested HeyClaudeKit code.
public enum WakePrefixStripper {
    private static let wakeMarkers: Set<String> =
        ["claude", "cloud", "claud", "clawed", "clode", "clawd", "clod"]

    public static func command(from transcript: String) -> String? {
        let lowered = transcript.lowercased()
        let cleaned = String(lowered.map {
            $0.isLetter || $0.isNumber || $0 == " " ? $0 : " "
        })
        let words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        if let idx = words.firstIndex(where: { wakeMarkers.contains($0) }) {
            let rest = words[(idx + 1)...].joined(separator: " ")
            return rest.isEmpty ? nil : rest
        }
        if words.first == "hey", words.count >= 2 {
            let rest = words.dropFirst(2).joined(separator: " ")
            return rest.isEmpty ? nil : rest
        }
        return nil
    }
}
