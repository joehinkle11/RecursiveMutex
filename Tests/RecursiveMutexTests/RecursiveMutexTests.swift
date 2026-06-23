import Testing
import Foundation
@testable import RecursiveMutex

// MARK: - Value mutation

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func intValueStartsAtInitial() {
    let lock = RecursiveMutex(7)
    let result = lock.withLock { n -> Int in n }
    #expect(result == 7)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func mutationPersistsBetweenAcquisitions() {
    let lock = RecursiveMutex(0)
    lock.withLock { n in n = 10 }
    lock.withLock { n in n += 5 }
    let result = lock.withLock { n -> Int in n }
    #expect(result == 15)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func innerWriteVisibleToOuterAfterReturn() {
    let lock = RecursiveMutex(0)
    var outerSaw = -1

    lock.withLock { n in
        lock.withLock { n in n = 42 }
        outerSaw = n    // inner write must be visible here
    }

    #expect(outerSaw == 42)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func arrayValueAccumulatesAcrossLevels() {
    let lock = RecursiveMutex([Int]())

    func push(_ v: Int, depth: Int) {
        lock.withLock { arr in
            arr.append(v)
            if depth > 0 { push(v * 10, depth: depth - 1) }
        }
    }

    push(1, depth: 2)
    let result = lock.withLock { arr -> [Int] in arr }
    #expect(result == [1, 10, 100])
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func stringValueBuildsCorrectly() {
    let lock = RecursiveMutex("")

    lock.withLock { s in
        s += "a"
        lock.withLock { s in
            s += "b"
            lock.withLock { s in s += "c" }
        }
        s += "d"
    }

    let result = lock.withLock { s -> String in s }
    #expect(result == "abcd")
}

// MARK: - Return values

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func withLockReturnsBodyResult() {
    let lock = RecursiveMutex(0)
    let r = lock.withLock { n -> String in
        n = 1
        return "ok"
    }
    #expect(r == "ok")
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func nestedWithLockReturnsInnerResult() {
    let lock = RecursiveMutex(0)
    let r = lock.withLock { _ in
        lock.withLock { _ -> Int in 99 }
    }
    #expect(r == 99)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func returnValueThreadedThroughThreeLevels() {
    let lock = RecursiveMutex(0)
    let r = lock.withLock { _ in
        lock.withLock { _ in
            lock.withLock { _ -> String in "deep" }
        }
    }
    #expect(r == "deep")
}

// MARK: - Bool toggling

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func boolTogglesCorrectlyAtEachDepth() {
    let lock = RecursiveMutex(false)
    var log: [Bool] = []

    func toggle(depth: Int) {
        lock.withLock { flag in
            flag = !flag
            log.append(flag)
            if depth > 0 { toggle(depth: depth - 1) }
        }
    }

    toggle(depth: 4)  // 5 toggles starting from false
    #expect(log == [true, false, true, false, true])
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func boolFinalStateMatchesToggleCount() {
    // Odd number of toggles → ends true; even → ends false.
    for depth in 0..<6 {
        let lock = RecursiveMutex(false)
        func toggle(d: Int) {
            lock.withLock { flag in
                flag = !flag
                if d > 0 { toggle(d: d - 1) }
            }
        }
        toggle(d: depth)
        let result = lock.withLock { f -> Bool in f }
        #expect(result == ((depth + 1) % 2 == 1))
    }
}

// MARK: - Reuse after release

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func lockAcquirableOneHundredTimesSequentially() {
    let lock = RecursiveMutex(0)
    for i in 0..<100 {
        lock.withLock { n in n = i }
    }
    let result = lock.withLock { n -> Int in n }
    #expect(result == 99)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func alternatingNestedAndFlatAcquisitions() {
    let lock = RecursiveMutex(0)

    // Interleave flat and nested acquisitions to stress depth tracking.
    lock.withLock { n in n += 1 }
    lock.withLock { n in
        n += 1
        lock.withLock { n in n += 1 }
    }
    lock.withLock { n in n += 1 }

    let result = lock.withLock { n -> Int in n }
    #expect(result == 4)
}

// MARK: - Error propagation

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func throwPropagatesFromFlatLock() {
    struct E: Error {}
    let lock = RecursiveMutex(0)
    #expect(throws: E.self) {
        try lock.withLock { _ in throw E() }
    }
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func throwPropagatesFromInnerNestedLock() {
    struct E: Error {}
    let lock = RecursiveMutex(0)
    var outerReached = false

    #expect(throws: E.self) {
        try lock.withLock { _ in
            outerReached = true
            try lock.withLock { _ in
                try lock.withLock { _ in throw E() }
            }
        }
    }
    #expect(outerReached)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func lockUsableAfterFlatThrow() {
    struct E: Error {}
    let lock = RecursiveMutex(0)
    try? lock.withLock { _ in throw E() }
    lock.withLock { n in n = 1 }
    let result = lock.withLock { n -> Int in n }
    #expect(result == 1)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func lockUsableAfterNestedThrow() {
    struct E: Error {}
    let lock = RecursiveMutex(0)

    try? lock.withLock { _ in
        try lock.withLock { _ in
            try lock.withLock { _ in throw E() }
        }
    }

    var ran = false
    lock.withLock { _ in ran = true }
    #expect(ran)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func partialMutationBeforeThrowIsContained() {
    // The lock must be re-acquirable regardless of what state value is in.
    struct E: Error {}
    let lock = RecursiveMutex([Int]())

    try? lock.withLock { arr in
        arr.append(1)           // partial mutation
        try lock.withLock { arr in
            arr.append(2)
            throw E()           // throw mid-nest
        }
    }

    // Just confirm no deadlock — value state is implementation-defined on throw.
    var reacquired = false
    lock.withLock { _ in reacquired = true }
    #expect(reacquired)
}

// MARK: - Concurrency

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func concurrentFlatIncrementsAreExact() async {
    let lock = RecursiveMutex(0)
    let tasks = 10
    let iters = 500

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<tasks {
            group.addTask {
                for _ in 0..<iters {
                    lock.withLock { n in n += 1 }
                }
            }
        }
    }

    let result = lock.withLock { n -> Int in n }
    #expect(result == tasks * iters)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func concurrentRecursiveIncrementsAreExact() async {
    let lock = RecursiveMutex(0)
    let tasks = 8
    let depth = 3   // each task adds depth+1 = 4

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<tasks {
            group.addTask {
                func inc(d: Int) {
                    lock.withLock { n in
                        n += 1
                        if d > 0 { inc(d: d - 1) }
                    }
                }
                inc(d: depth)
            }
        }
    }

    let result = lock.withLock { n -> Int in n }
    #expect(result == tasks * (depth + 1))
}


@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func highContentionDoesNotDeadlock() async {
    // Stress test: many tasks hammering nested locks simultaneously.
    let lock = RecursiveMutex(0)

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<50 {
            group.addTask {
                lock.withLock { n in
                    lock.withLock { n in
                        lock.withLock { n in n += 1 }
                    }
                }
            }
        }
    }

    let result = lock.withLock { n -> Int in n }
    #expect(result == 50)
}

// MARK: - MutexGuard API

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardReadsInitialValue() {
    let lock = RecursiveMutex(42)
    let g = lock.lock()
    #expect(g.value == 42)
    g.unlock()
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardWritesAndReadsValue() {
    let lock = RecursiveMutex(0)
    do {
        var g = lock.lock()
        g.value = 7
        #expect(g.value == 7)
        g.unlock()
    }
    let result = lock.withLock { n -> Int in n }
    #expect(result == 7)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardRecursiveLockReadWrite() {
    let lock = RecursiveMutex(0)
    var g1 = lock.lock()
    g1.value = 1
    var g2 = lock.lock()
    g2.value = 2
    #expect(g2.value == 2)
    #expect(g1.value == 2)
    g2.unlock()
    #expect(g1.value == 2)
    g1.value = 3
    g1.unlock()
    let result = lock.withLock { n -> Int in n }
    #expect(result == 3)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardThreeLevelRecursive() {
    let lock = RecursiveMutex(0)
    var g1 = lock.lock()
    g1.value = 10
    var g2 = lock.lock()
    g2.value = 20
    var g3 = lock.lock()
    g3.value = 30
    #expect(g3.value == 30)
    #expect(g2.value == 30)
    #expect(g1.value == 30)
    g3.unlock()
    g2.unlock()
    g1.unlock()
    let result = lock.withLock { n -> Int in n }
    #expect(result == 30)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardNestedInWithLock() {
    let lock = RecursiveMutex(0)
    lock.withLock { n in
        n = 1
        var g = lock.lock()
        g.value = 2
        #expect(g.value == 2)
        #expect(n == 2)
        g.unlock()
        n = 3
    }
    let result = lock.withLock { n -> Int in n }
    #expect(result == 3)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func withLockNestedInGuard() {
    let lock = RecursiveMutex(0)
    var g = lock.lock()
    g.value = 5
    lock.withLock { n in
        n += 10
        #expect(n == 15)
    }
    #expect(g.value == 15)
    g.unlock()
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardAndClosureAlternatingNesting() {
    let lock = RecursiveMutex(0)
    var g1 = lock.lock()
    g1.value = 1
    lock.withLock { n in
        n = 2
        var g2 = lock.lock()
        g2.value = 3
        lock.withLock { n in
            n = 4
        }
        #expect(g2.value == 4)
        g2.unlock()
    }
    #expect(g1.value == 4)
    g1.unlock()
    let result = lock.withLock { n -> Int in n }
    #expect(result == 4)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardMultithreadedExclusion() async {
    let lock = RecursiveMutex(0)
    let tasks = 10
    let iters = 500

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<tasks {
            group.addTask {
                for _ in 0..<iters {
                    var g = lock.lock()
                    g.value = g.value + 1
                    g.unlock()
                }
            }
        }
    }

    let result = lock.withLock { n -> Int in n }
    #expect(result == tasks * iters)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardReleaseAllowsReacquisition() {
    let lock = RecursiveMutex(0)
    do {
        var g = lock.lock()
        g.value = 1
        g.unlock()
    }
    do {
        var g = lock.lock()
        #expect(g.value == 1)
        g.value += 1
        g.unlock()
    }
    let result = lock.withLock { n -> Int in n }
    #expect(result == 2)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardThrowDoesNotDeadlock() {
    struct E: Error {}
    let lock = RecursiveMutex(0)
    do {
        var g = lock.lock()
        g.value = 1
        throw E()
    } catch {}
    var ran = false
    lock.withLock { _ in ran = true }
    #expect(ran)
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@Test func guardRecursiveIncrementsAreExact() async {
    let lock = RecursiveMutex(0)
    let tasks = 8
    let depth = 3

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<tasks {
            group.addTask {
                func inc(d: Int) {
                    var g = lock.lock()
                    g.value += 1
                    if d > 0 { inc(d: d - 1) }
                    g.unlock()
                }
                inc(d: depth)
            }
        }
    }

    let result = lock.withLock { n -> Int in n }
    #expect(result == tasks * (depth + 1))
}
