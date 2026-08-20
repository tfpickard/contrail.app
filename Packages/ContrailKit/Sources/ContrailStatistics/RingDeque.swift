/// A growable circular-buffer deque with O(1) amortized push/pop at **both** ends.
/// Swift's `Array` gives O(1) amortized `append`/`removeLast` but O(n)
/// `removeFirst`/`insert(at: 0)` — every structure in this module needs efficient
/// operations at both ends (push new samples at the back, evict aged-out samples
/// from the front, and for the monotonic min/max tracker, pop from the back too), so
/// a plain `Array` isn't sufficient. Growth doubles like `Array`'s own strategy.
struct RingDeque<Element> {
    private var storage: [Element?]
    private var headIndex = 0
    private var count = 0

    init(initialCapacity: Int = 16) {
        storage = Array(repeating: nil, count: Swift.max(initialCapacity, 1))
    }

    var isEmpty: Bool { count == 0 }
    var elementCount: Int { count }

    var first: Element? { isEmpty ? nil : storage[headIndex] }
    var last: Element? { isEmpty ? nil : storage[(headIndex + count - 1) % storage.count] }

    mutating func pushBack(_ element: Element) {
        growIfNeeded()
        storage[(headIndex + count) % storage.count] = element
        count += 1
    }

    @discardableResult
    mutating func popBack() -> Element? {
        guard count > 0 else { return nil }
        count -= 1
        let index = (headIndex + count) % storage.count
        let element = storage[index]
        storage[index] = nil
        return element
    }

    @discardableResult
    mutating func popFront() -> Element? {
        guard count > 0 else { return nil }
        let element = storage[headIndex]
        storage[headIndex] = nil
        headIndex = (headIndex + 1) % storage.count
        count -= 1
        return element
    }

    /// Index 0 is the front (oldest). O(1) — used by peak detection to scan a
    /// bounded lookback window without popping.
    subscript(index: Int) -> Element {
        precondition(index >= 0 && index < count, "RingDeque index out of range")
        return storage[(headIndex + index) % storage.count]!
    }

    private mutating func growIfNeeded() {
        guard count == storage.count else { return }
        var newStorage = [Element?](repeating: nil, count: storage.count * 2)
        for i in 0..<count {
            newStorage[i] = storage[(headIndex + i) % storage.count]
        }
        storage = newStorage
        headIndex = 0
    }
}
