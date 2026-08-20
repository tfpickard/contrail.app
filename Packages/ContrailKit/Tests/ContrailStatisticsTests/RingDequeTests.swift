import Testing
@testable import ContrailStatistics

struct RingDequeTests {
    @Test func pushAndPopBackFIFOOrder() {
        var deque = RingDeque<Int>(initialCapacity: 2)
        deque.pushBack(1)
        deque.pushBack(2)
        deque.pushBack(3) // forces growth past initial capacity of 2
        #expect(deque.elementCount == 3)
        #expect(deque.popFront() == 1)
        #expect(deque.popFront() == 2)
        #expect(deque.popFront() == 3)
        #expect(deque.popFront() == nil)
    }

    @Test func popBackRemovesFromTheEnd() {
        var deque = RingDeque<Int>()
        deque.pushBack(1)
        deque.pushBack(2)
        deque.pushBack(3)
        #expect(deque.popBack() == 3)
        #expect(deque.popBack() == 2)
        #expect(deque.first == 1)
        #expect(deque.last == 1)
    }

    @Test func subscriptIndexesFromFront() {
        var deque = RingDeque<Int>()
        for i in 0..<10 { deque.pushBack(i) }
        for i in 0..<10 { #expect(deque[i] == i) }
    }

    @Test func survivesInterleavedPushPopAcrossWraparound() {
        // Exercise the circular-buffer wraparound: repeatedly push a few, pop a
        // few, so headIndex walks all the way around storage multiple times.
        var deque = RingDeque<Int>(initialCapacity: 4)
        var reference: [Int] = []
        var nextValue = 0

        for round in 0..<50 {
            let pushCount = (round % 3) + 1
            for _ in 0..<pushCount {
                deque.pushBack(nextValue)
                reference.append(nextValue)
                nextValue += 1
            }
            let popCount = round % 2 == 0 ? 1 : 2
            for _ in 0..<min(popCount, reference.count) {
                #expect(deque.popFront() == reference.removeFirst())
            }
        }
        #expect(deque.elementCount == reference.count)
        for i in 0..<reference.count { #expect(deque[i] == reference[i]) }
    }

    @Test func emptyDequeReturnsNilConsistently() {
        var deque = RingDeque<Int>()
        #expect(deque.isEmpty)
        #expect(deque.first == nil)
        #expect(deque.last == nil)
        #expect(deque.popFront() == nil)
        #expect(deque.popBack() == nil)
    }
}
