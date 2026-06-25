import Synchronization

#if canImport(Glibc)
import func Glibc.pthread_self
#elseif canImport(Darwin)
import func Foundation.pthread_threadid_np
#endif

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
    let mutex = _Cell(Mutex(()))
    @usableFromInline
    let state = _Cell(State())
    @usableFromInline
    let value: _Cell<Value>

    // MARK: - Init

    public init(_ value: consuming sending Value) {
        self.value = _Cell(value)
    }

    // MARK: - Public API
    
    public func lock() -> MutexGuard {
        let currentID = currentThreadID()

        let alreadyOwned: Bool = mutex._address.pointee.withLock { _ in
            state._address.pointee.ownerThreadID == currentID
        }

        if alreadyOwned {
            mutex._address.pointee.withLock { _ in
                state._address.pointee.lockCount += 1
            }
            return MutexGuard(
                mutexAddress: mutex._address,
                valueAddress: value._address,
                stateAddress: state._address
            )
        }

        waitUntilAvailable(for: currentID)
        return MutexGuard(
            mutexAddress: mutex._address,
            valueAddress: value._address,
            stateAddress: state._address
        )
    }
    
    public struct MutexGuard: ~Copyable {
        let mutexAddress: UnsafeMutablePointer<Mutex<()>>
        let valueAddress: UnsafeMutablePointer<Value>
        let stateAddress: UnsafeMutablePointer<State>

        init(
            mutexAddress: UnsafeMutablePointer<Mutex<()>>,
            valueAddress: UnsafeMutablePointer<Value>,
            stateAddress: UnsafeMutablePointer<State>
        ) {
            self.mutexAddress = mutexAddress
            self.valueAddress = valueAddress
            self.stateAddress = stateAddress
        }
        
        public var value: Value {
            borrowing _read {
                yield valueAddress.pointee
            }
            mutating _modify {
                yield &valueAddress.pointee
            }
        }
        
        public consuming func unlock() {}
        
        deinit {
            mutexAddress.pointee._unsafeLock()
            stateAddress.pointee.lockCount -= 1
            if stateAddress.pointee.lockCount == 0 {
                stateAddress.pointee.ownerThreadID = nil
            }
            mutexAddress.pointee._unsafeUnlock()
        }
    }

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
        let alreadyOwned: Bool = mutex._address.pointee.withLock { _ in
            state._address.pointee.ownerThreadID == currentID
        }

        if alreadyOwned {
            // Re-entrant acquisition: bump the count, run, then decrement.
            mutex._address.pointee.withLock { _ in state._address.pointee.lockCount += 1 }
            defer {
                mutex._address.pointee.withLock { _ in
                    state._address.pointee.lockCount -= 1
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

        let acquired: Bool = mutex._address.pointee.withLock { _ in
            if state._address.pointee.ownerThreadID == nil || state._address.pointee.ownerThreadID == currentID {
                state._address.pointee.ownerThreadID = currentID
                state._address.pointee.lockCount += 1
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
            let claimed: Bool = mutex._address.pointee.withLock { _ in
                guard state._address.pointee.ownerThreadID == nil else { return false }
                state._address.pointee.ownerThreadID = threadID
                state._address.pointee.lockCount = 1
                return true
            }
            if claimed { return }
        }
    }

    /// Decrements the lock count and clears the owner when it hits zero.
    private func release() {
        mutex._address.pointee.withLock { _ in
            state._address.pointee.lockCount -= 1
            if state._address.pointee.lockCount == 0 {
                state._address.pointee.ownerThreadID = nil
            }
        }
    }

    /// Returns a stable numeric identifier for the calling thread.
    private func currentThreadID() -> UInt64 {
        #if canImport(Glibc)
        return UInt64(pthread_self())
        #elseif canImport(Darwin)
        var tid: UInt64 = 0
        pthread_threadid_np(nil, &tid)
        return tid
        #elseif arch(wasm32)
        return 0
        #else
        #error("Unsupported platform: RecursiveMutex needs a thread identifier implementation.")
        #endif
    }
}
