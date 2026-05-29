import Foundation

/// Resolves a wake event + optional trailing transcript to an Action (spec §5).
public struct CommandRouter {
    private let defaultAction: Action
    private let phraseMap: [String: Action]   // normalized phrase -> action

    public init(defaultAction: Action, phraseMap: [String: Action]) {
        self.defaultAction = defaultAction
        self.phraseMap = Dictionary(uniqueKeysWithValues:
            phraseMap.map { (Self.normalize($0.key), $0.value) })
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// transcript == nil means VAD found no trailing speech.
    public func route(transcript: String?) -> Action {
        guard let raw = transcript else { return defaultAction }
        let text = Self.normalize(raw)
        if text.isEmpty { return defaultAction }
        if let mapped = phraseMap[text] { return mapped }
        if text == "code" { return .launchCLI(prompt: nil) }
        if text.hasPrefix("code ") {
            return .launchCLI(prompt: String(text.dropFirst("code ".count)))
        }
        return .launchCLI(prompt: text)
    }
}
