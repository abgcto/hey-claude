import Foundation
import HeyClaudeKit

/// A thread-safe mutable box around `WakeWordEngine`, mirroring
/// `CommandExecutorHolder`.
///
/// Why this exists: the wake engine is captured in `AppController.start()`'s
/// audio-queue `onFrame` closure, which calls `feed(_:)` on every frame. Changing
/// wake sensitivity needs a *new* engine (the threshold is baked into the sherpa
/// spotter at construction — there's no setter), but rebooting the whole pipeline
/// to get one also reloads the ~631MB ASR transcriber, which the threshold doesn't
/// touch — the ~1s freeze. The holder lets the main actor swap in a freshly-built
/// 19MB wake engine while audio keeps running and the transcriber stays put.
///
/// `@unchecked Sendable`: the only mutable state (`engine`) is guarded by `lock`,
/// held *only* across the reference read/write — never across `feed`, which runs
/// on the audio queue (CLAUDE.md concurrency rule: keep audio work off-main).
/// `feed` is called only from the serial audio queue; `swap` from the main actor
/// or the wake-rebuild queue. Two engines may briefly coexist across a swap (old
/// finishes its in-flight frame, new takes the next) — safe, they're distinct
/// objects with independent streams.
final class WakeWordEngineHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: WakeWordEngine

    init(_ engine: WakeWordEngine) { self.engine = engine }

    /// Feed one frame of 16 kHz mono samples; returns whether the keyword fired.
    /// Snapshots the engine under the lock, then feeds lock-free so a concurrent
    /// `swap` never blocks the audio queue.
    func feed(_ samples: [Float]) -> Bool {
        lock.lock()
        let current = engine
        lock.unlock()
        return current.feed(samples)
    }

    /// Replace the live engine (e.g. after wake sensitivity changed).
    func swap(_ new: WakeWordEngine) {
        lock.lock()
        engine = new
        lock.unlock()
    }
}
