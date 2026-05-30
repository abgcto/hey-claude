import Foundation

/// A reference box for capturing mutable state inside `@Sendable` test closures.
/// `VoiceSession`/`CommandExecutor` callbacks are `@Sendable` (they fire on the
/// audio queue in production), so a test can't mutate a captured `var` directly.
/// The box holds the value by reference; tests drive it synchronously on one
/// thread, so `@unchecked Sendable` is accurate.
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
