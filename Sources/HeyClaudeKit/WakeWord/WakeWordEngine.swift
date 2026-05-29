import Foundation
import CSherpaOnnx

/// Wraps the sherpa-onnx online keyword spotter for the "hey claude" wake word.
public final class WakeWordEngine {
    public enum Error: Swift.Error { case missingModelFile(String) }

    private let spotter: SherpaOnnxKeywordSpotterWrapper

    /// - Parameters:
    ///   - modelDir: directory of the KWS zipformer model (encoder/decoder/joiner + tokens.txt).
    ///   - keywordsFile: tokenized keywords file containing the "hey claude" entry.
    ///   - keywordsThreshold: per-keyword trigger gate. Lower fires more eagerly.
    ///   - keywordsScore: per-keyword boost added to keyword-path hypotheses
    ///     during the modified beam search — it keeps the keyword path alive in
    ///     the beam when acoustic evidence is weak. This is the primary lever for
    ///     spotting a hard wake word on a small model; see
    ///     internal design notes for the calibrated value.
    ///   - maxActivePaths: beam width for the keyword spotter's modified search.
    public init(modelDir: URL, keywordsFile: URL,
                keywordsThreshold: Float = 0.25,
                keywordsScore: Float = 2.0,
                maxActivePaths: Int = 4) throws {
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
            maxActivePaths: maxActivePaths,
            keywordsScore: keywordsScore,
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
        // Tail pad so the streaming zipformer (chunk-16) flushes its final
        // partial chunk. Short wake clips (~0.7s) emit too few frames otherwise:
        // 0.2s of pad gave only ~2 decode steps and never tripped the keyword;
        // 1s reliably flushes the last tokens. See docs tuning log.
        spotter.acceptWaveform(samples: [Float](repeating: 0, count: 16000), sampleRate: 16000)
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

    /// Continuous-streaming feed for the live mic loop.
    ///
    /// Feeds one frame of 16 kHz mono samples into the persistent stream and
    /// drains the decoder. Unlike `detects(in:)`, this does NOT call
    /// `inputFinished()` — the stream stays alive across calls so the next
    /// frame continues the same utterance. Returns `true` and `reset()`s the
    /// stream's decoding state on a fire (so the next call starts fresh);
    /// returns `false` otherwise, leaving the stream ready for more frames.
    public func feed(_ samples: [Float]) -> Bool {
        spotter.acceptWaveform(samples: samples, sampleRate: 16000)
        while spotter.isReady() {
            spotter.decode()
            if !spotter.getResult().keyword.isEmpty {
                spotter.reset()
                return true
            }
        }
        return false
    }
}
