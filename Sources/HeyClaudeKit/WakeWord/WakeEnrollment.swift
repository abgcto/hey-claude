import Foundation

/// Pure wake-word enrollment: turn a few recordings of the user saying the wake
/// phrase into a calibrated, validated keyword file.
///
/// Why this exists: the KWS model transcribes the *same* phrase differently per
/// voice (e.g. "hey claude" → "hey cloud" → `▁HE Y ▁C LO U D`). A keyword built
/// from dictionary spelling is only a partial match → flaky wake. Enrollment
/// derives the keyword from the tokens the model *actually emits* for THIS user.
///
/// All effects (token decoding, fire-testing, file writing) are injected, so the
/// algorithm is unit-testable without models or audio.
public struct WakeEnrollment {
    /// One captured recording.
    public struct Sample: Sendable {
        public enum Kind: Sendable { case isolated, natural }
        public let audio: [Float]
        public let kind: Kind
        public init(audio: [Float], kind: Kind) { self.audio = audio; self.kind = kind }
    }

    /// The outcome of enrollment — what to persist and how confident we are.
    public struct Result: Equatable, Sendable {
        public let keywordLines: [String]   // tokenised keyword phrases, one per line
        public let threshold: Float          // tuned-down to make every sample fire
        public let allFired: Bool            // chosen config fires on ALL samples
        public let usedFallbackOnly: Bool    // couldn't derive from voice; default only
    }

    /// Decode a clip into the model's emitted tokens (e.g. `[" HE","Y"," C","LO","U","D"]`).
    public let decode: @Sendable ([Float]) -> [String]
    /// Whether `lines` at `threshold` fires the spotter on `audio`.
    public let fires: @Sendable (_ lines: [String], _ threshold: Float, _ audio: [Float]) -> Bool
    /// Dictionary-spelling fallback line, always appended for coverage.
    public let fallbackLine: String
    /// Threshold sweep, tried in order (descending); first one that fires all wins.
    public let thresholds: [Float]

    public init(decode: @escaping @Sendable ([Float]) -> [String],
                fires: @escaping @Sendable (_ lines: [String], _ threshold: Float, _ audio: [Float]) -> Bool,
                fallbackLine: String = "▁HE Y ▁C LA U DE",
                thresholds: [Float] = [0.25, 0.20, 0.15, 0.10]) {
        self.decode = decode
        self.fires = fires
        self.fallbackLine = fallbackLine
        self.thresholds = thresholds
    }

    // MARK: - Pure helpers (no effects)

    /// Map decode tokens to a sherpa keyword line: a leading-space token marks a
    /// word boundary (`▁`); others are sub-word continuations. Empty tokens drop.
    /// `[" HE","Y"," C","LO","U","D"]` → `"▁HE Y ▁C LO U D"`.
    public static func keywordLine(from tokens: [String]) -> String {
        tokens.compactMap { tok -> String? in
            let boundary = tok.hasPrefix(" ")
            let t = tok.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            return boundary ? "▁" + t : t
        }.joined(separator: " ")
    }

    /// A heuristic gate for rejecting junk captures (e.g. the model hearing "OUT"
    /// when it missed the utterance): a real "hey claude/cloud" carries the
    /// "claude" word-start C (`▁C`). Used by the recorder/UI to re-ask a slot.
    public static func isPlausibleWake(tokens: [String]) -> Bool {
        keywordLine(from: tokens).contains("▁C")
    }

    /// Distinct keyword lines derived from the isolated samples (order-preserving),
    /// dropping empties.
    static func derivedLines(isolated: [[String]]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for tokens in isolated {
            let line = keywordLine(from: tokens)
            guard !line.isEmpty, !seen.contains(line) else { continue }
            seen.insert(line); out.append(line)
        }
        return out
    }

    // MARK: - Orchestration

    /// Run enrollment over the captured samples, returning the keyword config to
    /// persist. Derives the keyword from the ISOLATED samples (clean tokens),
    /// then validates against ALL samples — the natural one is the real-world
    /// check that the keyword survives casual connected speech.
    public func enroll(samples: [Sample]) -> Result {
        let isolatedTokens = samples.filter { $0.kind == .isolated }.map { decode($0.audio) }
        let derived = Self.derivedLines(isolated: isolatedTokens)

        // Candidate = voice-derived lines + dictionary fallback (deduped).
        var lines = derived
        if !lines.contains(fallbackLine) { lines.append(fallbackLine) }

        // Find the highest threshold (least eager) where every sample fires.
        for t in thresholds {
            if samples.allSatisfy({ fires(lines, t, $0.audio) }) {
                return Result(keywordLines: lines, threshold: t,
                              allFired: true, usedFallbackOnly: derived.isEmpty)
            }
        }
        // Best effort: lowest threshold, flag that we couldn't make all fire.
        let t = thresholds.last ?? 0.10
        let allFired = samples.allSatisfy { fires(lines, t, $0.audio) }
        return Result(keywordLines: lines, threshold: t,
                      allFired: allFired, usedFallbackOnly: derived.isEmpty)
    }
}
