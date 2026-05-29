import Foundation
import CSherpaOnnx

/// Wraps the sherpa-onnx online keyword spotter for the "hey claude" wake word.
public final class WakeWordEngine {
    public enum Error: Swift.Error { case missingModelFile(String) }

    private let spotter: SherpaOnnxKeywordSpotterWrapper

    /// - Parameters:
    ///   - modelDir: directory of the KWS zipformer model (encoder/decoder/joiner + tokens.txt).
    ///   - keywordsFile: tokenized keywords file containing the "hey claude" entry.
    ///   - keywordsThreshold: per-keyword detection threshold. Lower fires more
    ///     eagerly; see internal design notes for the calibrated value.
    public init(modelDir: URL, keywordsFile: URL, keywordsThreshold: Float = 0.25) throws {
        func path(_ name: String) throws -> String {
            let u = modelDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: u.path) else { throw Error.missingModelFile(name) }
            return u.path
        }
        // Filenames match the gigaspeech KWS release (verified against the
        // downloaded Models/ directory).
        let transducer = sherpaOnnxOnlineTransducerModelConfig(
            encoder: try path("encoder-epoch-12-avg-2-chunk-16-left-64.onnx"),
            decoder: try path("decoder-epoch-12-avg-2-chunk-16-left-64.onnx"),
            joiner:  try path("joiner-epoch-12-avg-2-chunk-16-left-64.onnx"))
        let model = sherpaOnnxOnlineModelConfig(
            tokens: try path("tokens.txt"),
            transducer: transducer,
            numThreads: 1,
            provider: "cpu")
        let feat = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var config = sherpaOnnxKeywordSpotterConfig(
            featConfig: feat,
            modelConfig: model,
            keywordsFile: keywordsFile.path,
            keywordsThreshold: keywordsThreshold)
        self.spotter = SherpaOnnxKeywordSpotterWrapper(config: &config)
    }

    /// Feeds a full buffer of 16 kHz mono samples and returns whether the keyword fired.
    ///
    /// The vendored `SherpaOnnxKeywordSpotterWrapper` owns a single internal,
    /// stateful stream (no `createStream()` and no per-call stream argument),
    /// so we drive that stream and `reset()` it before returning so the engine
    /// can be reused for a subsequent buffer.
    public func detects(in samples: [Float]) -> Bool {
        spotter.acceptWaveform(samples: samples, sampleRate: 16000)
        // Tail pad so the streaming decoder flushes the final frames.
        spotter.acceptWaveform(samples: [Float](repeating: 0, count: 3200), sampleRate: 16000)
        spotter.inputFinished()
        while spotter.isReady() {
            spotter.decode()
            if !spotter.getResult().keyword.isEmpty {
                spotter.reset()
                return true
            }
        }
        spotter.reset()
        return false
    }
}
