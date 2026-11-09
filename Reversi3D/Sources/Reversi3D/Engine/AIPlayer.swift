import Foundation

/// Runs an engine on a queue of its own; the game asks for the result each frame.
final class AIPlayer: @unchecked Sendable {
    private let engine: Engine
    private let queue: DispatchQueue
    private let lock = NSLock()
    // Guarded by the lock.
    private var result: SearchResult?
    private var busy = false
    private var stopFlag: StopFlag?

    init(hashMegabytes: Int, label: String) {
        engine = Engine(hashMegabytes: hashMegabytes)
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    deinit {
        cancel()
    }

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return busy
    }

    func start(_ position: Position, limits: SearchLimits) {
        cancel()
        let flag = StopFlag()
        lock.lock()
        busy = true
        stopFlag = flag
        lock.unlock()
        queue.async { [self] in
            let found = engine.search(position, limits: limits, stop: flag)
            lock.lock()
            if !flag.isStopped {
                result = found
            }
            busy = false
            lock.unlock()
        }
    }

    /// Stops a search under way and waits for it to end; its result is dropped.
    func cancel() {
        lock.lock()
        let flag = stopFlag
        stopFlag = nil
        lock.unlock()
        flag?.stop()
        queue.sync {}
        lock.lock()
        busy = false
        result = nil
        lock.unlock()
    }

    /// Forgets what the engine learned in the last game.
    func newGame() {
        cancel()
        queue.sync { engine.clear() }
    }

    /// The result of the last search, once.
    func takeResult() -> SearchResult? {
        lock.lock()
        defer { lock.unlock() }
        let taken = result
        result = nil
        return taken
    }
}
