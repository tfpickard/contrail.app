import Foundation

/// A small `NSLock`-guarded box whose accessor is an ordinary synchronous closure.
/// Exists because newer SDKs mark `NSLock.lock()`/`unlock()` `noasync` specifically
/// to discourage calling them directly inside an `async` function's body -- calling
/// them from inside a plain sync closure (this type's `withLock`) sidesteps that
/// restriction without changing the actual locking behavior. Used by
/// `BLEDiscoveryController` and `MultipeerAvatarTransport`, both of which mutate
/// shared state from `async` methods and from synchronous CoreBluetooth/
/// MultipeerConnectivity delegate callbacks on the framework's own queue.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
