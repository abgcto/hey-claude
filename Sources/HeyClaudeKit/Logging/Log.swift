import os

/// Structured logging seam. Launch failures route here (queryable in Console.app
/// by subsystem/category) instead of raw `stderr` writes that nobody reads.
///
/// The opt-in `HEYCLAUDE_ROUTE_LOG` transcript→routing log in `AppController` is a
/// separate concern (routing diagnosis, not errors) and stays as-is.
public enum Log {
    /// Command launch outcomes — failures logged at `.error`.
    public static let launch = Logger(subsystem: "com.heyclaude.app", category: "launch")

    /// Microphone capture lifecycle — e.g. a mute→unmute restart that fails to
    /// re-acquire the input device (would otherwise leave the app silently deaf).
    public static let audio = Logger(subsystem: "com.heyclaude.app", category: "audio")
}
