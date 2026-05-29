import Foundation
import CSherpaOnnx

/// Offline transcription via sherpa-onnx + NeMo Parakeet TDT.
public final class ParakeetTranscriber: SpeechTranscriber {
    public enum Error: Swift.Error { case missingModelFile(String) }

    private let recognizer: SherpaOnnxOfflineRecognizer

    public init(modelDir: URL) throws {
        func path(_ name: String) throws -> String {
            let u = modelDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: u.path) else { throw Error.missingModelFile(name) }
            return u.path
        }
        // Filenames match the parakeet-tdt-0.6b-v2-int8 release (verified
        // against the downloaded Models/ directory).
        let transducer = sherpaOnnxOfflineTransducerModelConfig(
            encoder: try path("encoder.int8.onnx"),
            decoder: try path("decoder.int8.onnx"),
            joiner:  try path("joiner.int8.onnx"))
        let model = sherpaOnnxOfflineModelConfig(
            tokens: try path("tokens.txt"),
            transducer: transducer,
            numThreads: 2,
            provider: "cpu",
            modelType: "nemo_transducer")
        let feat = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)
        var config = sherpaOnnxOfflineRecognizerConfig(featConfig: feat, modelConfig: model)
        self.recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    public func transcribe(_ samples: [Float]) throws -> String {
        let result = recognizer.decode(samples: samples, sampleRate: 16000)
        return result.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
