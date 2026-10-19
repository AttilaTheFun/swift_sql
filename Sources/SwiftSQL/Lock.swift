#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import WinSDK
#elseif canImport(WASILibc)
import WASILibc
#if _runtime(_multithreaded)
// wasm32-wasip1-threads: the C library's pthreads are a module of their own.
import wasi_pthread
#endif
#endif

/// A recursive lock over the platform's own (a pthread mutex, a Windows
/// critical section): `Synchronization`'s `Mutex` needs iOS 18 and is not
/// recursive. Recursive, so that a call made on the database from inside one
/// of its closures (a `transaction`'s body using the database rather than
/// the connection it was given) continues on the same thread rather than
/// waiting on itself. A single-threaded WebAssembly module has nothing to
/// guard and no mutex to guard it with.
final class RecursiveLock: @unchecked Sendable {
    #if os(Windows)
    private let section = UnsafeMutablePointer<CRITICAL_SECTION>.allocate(capacity: 1)

    init() { InitializeCriticalSection(section) }

    deinit {
        DeleteCriticalSection(section)
        section.deallocate()
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        EnterCriticalSection(section)
        defer { LeaveCriticalSection(section) }
        return try body()
    }
    #elseif os(WASI) && !_runtime(_multithreaded)
    init() {}

    func withLock<T>(_ body: () throws -> T) rethrows -> T { try body() }
    #else
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
    #endif
}
