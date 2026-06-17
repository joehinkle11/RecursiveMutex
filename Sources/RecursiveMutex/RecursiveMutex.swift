import Synchronization
import func Foundation.pthread_threadid_np

/// A recursive mutual exclusion lock that allows the same thread to acquire
/// the lock multiple times without deadlocking.
///
/// Built on top of Swift's `Mutex` type (Swift 5.10+, SE-0433).
///
/// Usage:
/// ```swift
/// let lock = RecursiveMutex()
///
/// lock.withLock {
///     // first acquisition
///     lock.withLock {
///         // same thread can re-enter safely
///     }
/// }
/// ```
@_staticExclusiveOnly
@frozen
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct RecursiveMutex<Value>: @unchecked Sendable, ~Copyable where Value : ~Copyable {

    // MARK: - Private state
    @frozen
    @usableFromInline
    struct State: ~Copyable {
        var ownerThreadID: UInt64? = nil
        var lockCount: Int = 0
    }

    @usableFromInline
    let mutex = Mutex(State())
    @usableFromInline
    var value: _Cell<Value>

    // MARK: - Init

    public init(_ value: consuming sending Value) {
        self.value = _Cell(value)
    }

    // MARK: - Public API

    /// Acquires the lock, runs `body`, then releases the lock.
    /// The calling thread may call this recursively without deadlocking.
    @discardableResult
    public func withLock<T: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending T
    ) throws(E) -> sending T {
        let currentID = currentThreadID()

        // Fast path: already the owner — just increment depth.
        // We must read ownerThreadID without blocking ourselves, so we
        // peek inside the mutex. If we already own it we increment
        // the count; if we don't own it we block until it's free.
        let alreadyOwned: Bool = mutex.withLock { state in
            state.ownerThreadID == currentID
        }

        if alreadyOwned {
            // Re-entrant acquisition: bump the count, run, then decrement.
            mutex.withLock { state in state.lockCount += 1 }
            defer {
                mutex.withLock { state in
                    state.lockCount -= 1
                    // ownerThreadID stays set; outer lock() call will clear it.
                }
            }
            return try unsafe body(&value._address.pointee)
        }

        // First acquisition on this thread: block until we get the logical lock.
        // We spin/wait by repeatedly trying to set ourselves as owner.
        // Because `Mutex.withLock` is non-recursive we use a separate
        // condition-variable–style loop via a Mutex<Bool> sentinel.
        waitUntilAvailable(for: currentID)

        defer { release() }
        
        return try unsafe body(&value._address.pointee)
    }

    /// Attempts to acquire the lock without blocking.
    /// Returns `true` and executes `body` if the lock was acquired,
    /// otherwise returns `false` immediately.
    @discardableResult
    public func tryWithLock<T, E: Error>(
        _ body: () throws(E) -> T
    ) throws(E) -> sending T? {
        let currentID = currentThreadID()

        let acquired: Bool = mutex.withLock { state in
            if state.ownerThreadID == nil || state.ownerThreadID == currentID {
                state.ownerThreadID = currentID
                state.lockCount += 1
                return true
            }
            return false
        }

        guard acquired else { return nil }
        defer { release() }
        return try body()
    }

    // MARK: - Private helpers

    /// Spins (yielding the thread) until ownership can be claimed.
    private func waitUntilAvailable(for threadID: UInt64) {
        while true {
            let claimed: Bool = mutex.withLock { state in
                guard state.ownerThreadID == nil else { return false }
                state.ownerThreadID = threadID
                state.lockCount = 1
                return true
            }
            if claimed { return }
        }
    }

    /// Decrements the lock count and clears the owner when it hits zero.
    private func release() {
        mutex.withLock { state in
            state.lockCount -= 1
            if state.lockCount == 0 {
                state.ownerThreadID = nil
            }
        }
    }

    /// Returns a stable numeric identifier for the calling thread.
    private func currentThreadID() -> UInt64 {
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        return tid
    }
}

