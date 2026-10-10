import Foundation

/// Waits for a distributed-notification reply.
/// Replies are delivered on the main run loop, so callers must wait on a background thread
/// while the main run loop keeps running (see `main.swift`).
final class Reply: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    private var received = false

    func set(_ value: String?) {
        lock.lock()
        stored = value
        received = true
        lock.unlock()
    }

    var value: (received: Bool, value: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (received, stored)
    }

    /// Calls `post` every `interval` (at most `posts` times) until a reply arrives or `timeout` passes.
    func wait(timeout: TimeInterval, interval: TimeInterval = 1, posts: Int = .max, post: () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        var nextPost = Date()
        var sent = 0
        while !value.received, Date() < deadline {
            if Date() >= nextPost, sent < posts {
                post()
                sent += 1
                nextPost = Date().addingTimeInterval(interval)
            }
            if Thread.isMainThread {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
}
