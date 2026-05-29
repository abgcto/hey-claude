import Foundation

/// Orchestrates: captured utterance -> transcribe -> strip wake -> resolve via
/// the command registry -> execute, with a cooldown to suppress double-fires.
/// Dependencies are injected (closures + registry) so the live wiring and the
/// tests share one path.
public final class VoiceSession {
    private let transcribe: ([Float]) -> String
    private let now: () -> Double
    private let cooldownSeconds: Double
    private let registry: CommandRegistry
    private let execute: (Command, String?) -> Void
    private var lastFireTime: Double = -.greatestFiniteMagnitude

    public init(transcribe: @escaping ([Float]) -> String,
                now: @escaping () -> Double,
                cooldownSeconds: Double,
                registry: CommandRegistry,
                execute: @escaping (Command, String?) -> Void) {
        self.transcribe = transcribe
        self.now = now
        self.cooldownSeconds = cooldownSeconds
        self.registry = registry
        self.execute = execute
    }

    /// Handle one captured post-wake utterance.
    public func handle(utterance: [Float]) {
        let t = now()
        guard t - lastFireTime >= cooldownSeconds else { return }
        lastFireTime = t
        let transcript = transcribe(utterance)
        let command = WakePrefixStripper.command(from: transcript)   // strip "hey claude"
        if let r = registry.resolve(transcript: command) {
            execute(r.command, r.prompt)
        }
    }
}
