import Foundation
import CSherpaOnnx

/// Diagnostic helper: drives the KWS model's encoder/decoder/joiner as a plain
/// online transducer recognizer to reveal the literal tokens the model emits
/// for a given clip. Used to calibrate the wake-word keyword tokenization
/// against what the model actually hears (not dictionary BPE). Not used in the
/// detection path.
public enum KwsDebug {
    public static func decodeTokens(modelDir: URL, samples: [Float]) -> (text: String, tokens: [String]) {
        func path(_ n: String) -> String { modelDir.appendingPathComponent(n).path }
        let transducer = sherpaOnnxOnlineTransducerModelConfig(
            encoder: path("encoder-epoch-12-avg-2-chunk-16-left-64.onnx"),
            decoder: path("decoder-epoch-12-avg-2-chunk-16-left-64.onnx"),
            joiner:  path("joiner-epoch-12-avg-2-chunk-16-left-64.onnx"))
        let model = sherpaOnnxOnlineModelConfig(
            tokens: path("tokens.txt"), transducer: transducer, numThreads: 1, provider: "cpu")
        let feat = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var cfg = sherpaOnnxOnlineRecognizerConfig(
            featConfig: feat, modelConfig: model, decodingMethod: "greedy_search")
        let rec = SherpaOnnxRecognizer(config: &cfg)
        rec.acceptWaveform(samples: samples)
        rec.acceptWaveform(samples: [Float](repeating: 0, count: 4800))
        while rec.isReady() { rec.decode() }
        let r = rec.getResult()
        return (r.text, r.tokens)
    }
}
