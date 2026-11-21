import Foundation

/// Invalidates publications already queued for the UI when Stop/game changes.
final class DeliveryFence {
    private let lock = NSLock()
    private var epoch: UInt64 = 0
    func snapshot() -> UInt64 { lock.lock();defer{lock.unlock()};return epoch }
    func invalidate() {lock.lock();epoch &+= 1;lock.unlock()}
    func accepts(_ value: UInt64) -> Bool {lock.lock();defer{lock.unlock()};return epoch == value}
}
