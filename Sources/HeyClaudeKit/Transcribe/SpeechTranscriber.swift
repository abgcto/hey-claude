/// Stage-2 transcription. Pluggable so the engine can be swapped
/// (Parakeet default; FluidAudio/WhisperKit/Apple SpeechTranscriber later).
public protocol SpeechTranscriber {
    /// Transcribes 16 kHz mono samples to lowercased, trimmed text.
    func transcribe(_ samples: [Float]) throws -> String
}
