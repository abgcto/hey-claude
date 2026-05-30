import Foundation
import HeyClaudeKit

/// A thread-safe mutable box around the value-type `CommandExecutor`.
///
/// Why this exists: `CommandExecutor` is a `struct` captured *by value* in the
/// audio-queue launch closure (see `AppController.start()`). Changing the launch
/// target or working folder only affects *where* a command opens — not the speech
/// models — so it must not reboot the pipeline (a reload of the ~650MB ASR + KWS
/// models on the main actor, the ~1s "every click lags" freeze). But you also
/// can't just reassign a captured value type: the closure keeps its stale copy.
/// The holder gives both sides one shared reference, so the main actor can
/// `swap` in a freshly-built executor and the audio queue sees it on the next fire.
///
/// `@unchecked Sendable`: the only mutable state (`executor`) is guarded by
/// `lock`, held *only* across the struct copy — never across the slow `launch()`,
/// which runs on the audio queue after the lock is released (CLAUDE.md
/// concurrency rule: launch work stays off the main actor).
final class CommandExecutorHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var executor: CommandExecutor

    init(_ executor: CommandExecutor) { self.executor = executor }

    /// Run a command on the current executor. Snapshots under the lock, then
    /// launches lock-free so a concurrent `swap` never blocks on a launch.
    func execute(_ command: Command, prompt: String?,
                 completion: @escaping @Sendable (Result<Void, LaunchFailure>) -> Void) {
        lock.lock()
        let current = executor
        lock.unlock()
        current.execute(command, prompt: prompt, completion: completion)
    }

    /// Replace the live executor (e.g. after the target or folder changed). Cheap —
    /// the new struct is built from settings, with no model or audio work.
    func swap(_ new: CommandExecutor) {
        lock.lock()
        executor = new
        lock.unlock()
    }
}
