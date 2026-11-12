import Foundation

/// One Spotlight query run to completion (or until cancelled / timed out) off the main thread.
///
/// `NSMetadataQuery` posts its notifications on `operationQueue`, so a private serial queue gives it
/// a home that never touches the main thread. Every exit path goes through `finish()`, which stops
/// the query on that queue, reads what was gathered and resumes the caller exactly once.
final class SpotlightSearch: @unchecked Sendable {
    struct Hit: Sendable {
        let path: String
        let name: String
        let isFolder: Bool
        let lastUsed: Date?
    }

    private let query = NSMetadataQuery()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "Samune.Spotlight"
        return queue
    }()
    private let cap: Int
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[Hit], Never>?
    private var finishing = false
    private var observers: [NSObjectProtocol] = []

    private init(predicate: NSPredicate, scopes: [Any], cap: Int) {
        self.cap = cap
        query.predicate = predicate
        query.searchScopes = scopes
        query.operationQueue = queue
        // Prefetched with the results: reading them one by one costs ~0.3 ms per item (last used date).
        query.valueListAttributes = [NSMetadataItemFSNameKey, NSMetadataItemContentTypeKey,
                                     NSMetadataItemLastUsedDateKey]
    }

    /// Runs the query. Returns at most `cap` hits, whatever was gathered after `timeout` seconds,
    /// or nothing as soon as the calling task is cancelled.
    static func run(predicate: NSPredicate, scopes: [Any], timeout: TimeInterval, cap: Int) async -> [Hit] {
        let search = SpotlightSearch(predicate: predicate, scopes: scopes, cap: cap)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                search.start(continuation, timeout: timeout)
            }
        } onCancel: {
            search.finish(discard: true)
        }
    }

    private func start(_ continuation: CheckedContinuation<[Hit], Never>, timeout: TimeInterval) {
        lock.lock()
        if finishing {
            // Cancelled before it started.
            lock.unlock()
            continuation.resume(returning: [])
            return
        }
        self.continuation = continuation
        lock.unlock()

        // Everything touching the query happens on its serial queue. If `finish` got there first,
        // its operation already ran and this one does nothing.
        queue.addOperation { [self] in
            lock.lock()
            let cancelled = finishing
            lock.unlock()
            guard !cancelled else { return }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query,
                                   queue: queue) { [weak self] _ in
                    self?.finish(discard: false)
                },
                center.addObserver(forName: .NSMetadataQueryGatheringProgress, object: query,
                                   queue: queue) { [weak self] _ in
                    guard let self, self.query.resultCount >= self.cap else { return }
                    self.finish(discard: false)
                },
            ]
            if !query.start() { finish(discard: false) }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(discard: false)
        }
    }

    /// Stops the query and resumes the caller once. `discard` skips reading results (cancellation).
    private func finish(discard: Bool) {
        lock.lock()
        if finishing {
            lock.unlock()
            return
        }
        finishing = true
        lock.unlock()

        queue.addOperation { [self] in
            query.disableUpdates()
            query.stop()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            let hits = discard ? [] : collect()
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: hits)
        }
    }

    private func collect() -> [Hit] {
        let count = min(query.resultCount, cap)
        var hits: [Hit] = []
        hits.reserveCapacity(count)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }
            let name = query.value(ofAttribute: NSMetadataItemFSNameKey, forResultAt: index) as? String
                ?? (path as NSString).lastPathComponent
            let type = query.value(ofAttribute: NSMetadataItemContentTypeKey, forResultAt: index) as? String
            let lastUsed = query.value(ofAttribute: NSMetadataItemLastUsedDateKey, forResultAt: index) as? Date
            hits.append(Hit(path: path, name: name, isFolder: type == "public.folder", lastUsed: lastUsed))
        }
        return hits
    }
}
