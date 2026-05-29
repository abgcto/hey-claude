import CSherpaOnnx

/// Hey Claude — on-device, voice-activated launcher for Claude Code.
/// Unofficial community project. Not affiliated with Anthropic.
public enum HeyClaudeKit {
    public static let version = "0.1.0-spike"

    /// Returns true if the sherpa-onnx C symbols link and load.
    ///
    /// Constructing the trivial `SherpaOnnxFeatureConfig` C struct via the
    /// vendored wrapper proves the static library is linked and importable.
    public static func sherpaLinks() -> Bool {
        let feat = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        return feat.sample_rate == 16000
    }
}
