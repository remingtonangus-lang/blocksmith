import Foundation

// Stand-in for Darwin's `os` module on Android/Linux: os_unfair_lock over a pthread mutex (zero bytes are a valid
// default mutex in glibc and bionic, matching os_unfair_lock()'s all-zero initial state).
public struct os_unfair_lock {
    @usableFromInline var mutex = pthread_mutex_t()
    public init() {}
}
public typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock>

@inlinable public func os_unfair_lock_lock(_ l: UnsafeMutablePointer<os_unfair_lock>) {
    UnsafeMutableRawPointer(l).withMemoryRebound(to: pthread_mutex_t.self, capacity: 1) { _ = pthread_mutex_lock($0) }
}
@inlinable public func os_unfair_lock_unlock(_ l: UnsafeMutablePointer<os_unfair_lock>) {
    UnsafeMutableRawPointer(l).withMemoryRebound(to: pthread_mutex_t.self, capacity: 1) { _ = pthread_mutex_unlock($0) }
}
@inlinable public func os_unfair_lock_trylock(_ l: UnsafeMutablePointer<os_unfair_lock>) -> Bool {
    UnsafeMutableRawPointer(l).withMemoryRebound(to: pthread_mutex_t.self, capacity: 1) { pthread_mutex_trylock($0) == 0 }
}
