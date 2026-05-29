import Foundation

/// Orchestrates: captured utterance -> transcribe -> strip wake -> route ->
/// execute, with a cooldown to suppress double-fires. Dependencies are
/// injected (closures) so the live wiring and the tests share one path.
public final class VoiceSession {
    private let transcribe: ([Float]) -> String
    private let now: () -> Double
    private let cooldownSeconds: Double
    private let execute: (Action) -> Void
    private let router = CommandRouter(defaultAction: .launchCLI(prompt: nil), phraseMap: [:])
    private var lastFireTime: Double = -.greatestFiniteMagnitude

    public init(transcribe: @escaping ([Float]) -> String,
                now: @escaping () -> Double,
                cooldownSeconds: Double,
                execute: @escaping (Action) -> Void) {
        self.transcribe = transcribe
        self.now = now
        self.cooldownSeconds = cooldownSeconds
        self.execute = execute
    }

    /// Handle one captured post-wake utterance.
    public func handle(utterance: [Float]) {
        let t = now()
        guard t - lastFireTime >= cooldownSeconds else { return }
        lastFireTime = t
        let transcript = transcribe(utterance)
        let command = WakePrefixStripper.command(from: transcript)
        execute(router.route(transcript: command))
    }
}
