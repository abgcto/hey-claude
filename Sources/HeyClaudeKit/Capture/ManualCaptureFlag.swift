import os

/// Lock-guarded bridge between the push-to-talk CGEventTap callback (which may
/// fire on any thread and must return *instantly*) and the audio serial queue
/// (which reads it once per frame). The tap only ever writes (press/release/
/// cancel); the audio `onFrame` only ever reads (`active`/`shouldCancel`).
/// `OSAllocatedUnfairLock` keeps both sides safe without hopping threads —
/// preserving the rule that all `CaptureSession` mutation stays on the audio queue.
///
/// `cancel` distinguishes the two ways a hold can end: a normal **release** emits
/// the captured clip; an **Esc cancel** discards it. The bit stays set until the
/// next `press()` clears it, and is inert while `active == false`.
public final class ManualCaptureFlag: @unchecked Sendable {
    private struct State { var active = false; var cancel = false }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    /// Push-to-talk press: begin capturing, clearing any prior cancel.
    public func press() { lock.withLock { $0 = State(active: true, cancel: false) } }

    /// Normal release: stop capturing → the audio loop emits the clip.
    public func release() { lock.withLock { $0.active = false } }

    /// Cancel (Esc): stop capturing → the audio loop discards the clip.
    public func cancel() { lock.withLock { $0 = State(active: false, cancel: true) } }

    /// Should capture be running? (read on the audio queue, once per frame)
    public var active: Bool { lock.withLock { $0.active } }

    /// When capture ends, discard instead of emit? (read on the audio queue)
    public var shouldCancel: Bool { lock.withLock { $0.cancel } }
}
