import Foundation

/// Orchestrates: captured utterance -> transcribe -> strip wake -> resolve via
/// the command registry -> execute, with a cooldown to suppress double-fires.
/// Dependencies are injected (closures + registry) so the live wiring and the
/// tests share one path.
public final class VoiceSession {
    /// What one fired utterance resolved to, surfaced for observability. Lets the
    /// app log exactly what was heard and how it routed — the seam needed to
    /// diagnose mis-routing (the live transcript is the only thing the unit
    /// tests and synthetic fixtures cannot reproduce).
    public struct Outcome: Sendable {
        public let transcript: String          // raw ASR text of the clip
        public let strippedCommand: String?    // after wake-prefix strip (nil = bare wake)
        public let resolved: CommandRegistry.Resolution?
    }

    // All four callbacks fire inside `handle`, which runs on the AudioCapture
    // serial queue — never the main actor. They are therefore `@Sendable`: a
    // non-Sendable closure created in a `@MainActor` scope (top-level `main`, or
    // an `@MainActor` method) inherits main-actor isolation, and macOS 26 hard-
    // traps (`_dispatch_assert_queue_fail`) the moment such a closure is invoked
    // off-main. `@Sendable` forces the call site to pass a non-isolated closure.
    private let transcribe: @Sendable ([Float]) -> String
    private let now: @Sendable () -> Double
    private let cooldownSeconds: Double
    private let registry: CommandRegistry
    private let execute: @Sendable (Command, String?) -> Void
    private let observe: (@Sendable (Outcome) -> Void)?
    private var lastFireTime: Double = -.greatestFiniteMagnitude

    public init(transcribe: @escaping @Sendable ([Float]) -> String,
                now: @escaping @Sendable () -> Double,
                cooldownSeconds: Double,
                registry: CommandRegistry,
                execute: @escaping @Sendable (Command, String?) -> Void,
                observe: (@Sendable (Outcome) -> Void)? = nil) {
        self.transcribe = transcribe
        self.now = now
        self.cooldownSeconds = cooldownSeconds
        self.registry = registry
        self.execute = execute
        self.observe = observe
    }

    /// Handle one captured post-wake utterance.
    public func handle(utterance: [Float]) {
        let t = now()
        guard t - lastFireTime >= cooldownSeconds else { return }
        lastFireTime = t
        let transcript = transcribe(utterance)
        let command = WakePrefixStripper.command(from: transcript)   // strip "hey claude"
        let resolution = registry.resolve(transcript: command)
        observe?(Outcome(transcript: transcript, strippedCommand: command, resolved: resolution))
        if let r = resolution {
            execute(r.command, r.prompt)
        }
    }
}
