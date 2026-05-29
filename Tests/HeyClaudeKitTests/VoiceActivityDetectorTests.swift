import XCTest
@testable import HeyClaudeKit

final class VoiceActivityDetectorTests: XCTestCase {
    func test_silenceHasNoSpeech() {
        let vad = VoiceActivityDetector(energyThreshold: 0.01)
        let silence = [Float](repeating: 0, count: 16000)
        XCTAssertFalse(vad.containsSpeech(silence))
    }

    func test_loudBufferHasSpeech() {
        let vad = VoiceActivityDetector(energyThreshold: 0.01)
        let loud = (0..<16000).map { i in sin(Float(i) * 0.1) * 0.5 }
        XCTAssertTrue(vad.containsSpeech(loud))
    }

    func test_endpointAfterTrailingSilence() {
        let vad = VoiceActivityDetector(energyThreshold: 0.01, frameMs: 20, hangoverMs: 600)
        let sr = 16000, frame = 320          // 20ms @ 16k
        var buf = [Float]()
        buf += (0..<(frame*10)).map { sin(Float($0) * 0.1) * 0.5 }   // 200ms speech
        buf += [Float](repeating: 0, count: frame*40)                 // 800ms silence > hangover
        XCTAssertTrue(vad.hasEndpointed(buf, sampleRate: sr))
    }
}
