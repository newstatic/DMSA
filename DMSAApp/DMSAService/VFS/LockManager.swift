import Foundation

// Note: SyncLockDirection is defined in DMSAShared/Models/FileEntry.swift

/// Sync Lock Manager
/// Manages file sync lock states to ensure data consistency during sync
/// Strategy: Pessimistic locking + Non-blocking reads
/// - Read: Allowed, reads directly from source file
/// - Write: Blocked, waits for sync completion or timeout
/// - Delete: Blocked, waits for sync completion or timeout
final class LockManager {

    static let shared = LockManager()

    /// Lock information
    struct LockInfo {
        let virtualPath: String
        let lockTime: Date
        let direction: SyncLockDirection
        let sourcePath: String  // Sync source path, used for reads
    }

    /// Wait result
    enum WaitResult {
        case success      // Lock released
        case timeout      // Wait timed out
        case cancelled    // Wait cancelled
    }

    // Currently locked files
    private var locks: [String: LockInfo] = [:]

    // Continuations waiting for lock release
    private var waitingOperations: [String: [CheckedContinuation<WaitResult, Never>]] = [:]

    // Thread-safe queue
    private let lockQueue = DispatchQueue(label: "com.dmsa.lockManager", attributes: .concurrent)

    // Logger
    private let logger = Logger.forService("LockManager")

    // Lock timeout
    private let lockTimeout: TimeInterval = 300  // 5 minutes
    private let writeWaitTimeout: TimeInterval = 30  // 30 seconds

    private init() {
        // Start lock timeout checker timer
        startTimeoutChecker()
    }

    // MARK: - Public Methods

    /// Acquire sync lock
    func acquireLock(_ virtualPath: String, direction: SyncLockDirection, sourcePath: String) -> Bool {
        return lockQueue.sync(flags: .barrier) {
            // Check if already locked
            guard locks[virtualPath] == nil else {
                logger.warn("File already locked: \(virtualPath)")
                return false
            }

            // Create lock info
            locks[virtualPath] = LockInfo(
                virtualPath: virtualPath,
                lockTime: Date(),
                direction: direction,
                sourcePath: sourcePath
            )

            logger.debug("Acquired sync lock: \(virtualPath), direction: \(direction)")
            return true
        }
    }

    /// Release sync lock
    func releaseLock(_ virtualPath: String) {
        lockQueue.sync(flags: .barrier) {
            guard locks[virtualPath] != nil else {
                return
            }

            locks[virtualPath] = nil

            // Wake all waiting operations
            if let continuations = waitingOperations[virtualPath] {
                for continuation in continuations {
                    continuation.resume(returning: .success)
                }
                waitingOperations[virtualPath] = nil
            }

            logger.debug("Released sync lock: \(virtualPath)")
        }
    }

    /// Batch acquire locks
    func acquireLocks(_ paths: [String], direction: SyncLockDirection, sourcePathResolver: (String) -> String?) -> [String] {
        return lockQueue.sync(flags: .barrier) {
            var lockedPaths: [String] = []

            for path in paths {
                guard locks[path] == nil,
                      let sourcePath = sourcePathResolver(path) else {
                    continue
                }

                locks[path] = LockInfo(
                    virtualPath: path,
                    lockTime: Date(),
                    direction: direction,
                    sourcePath: sourcePath
                )
                lockedPaths.append(path)
            }

            logger.debug("Batch acquired locks: \(lockedPaths.count)/\(paths.count)")
            return lockedPaths
        }
    }

    /// Batch release locks
    func releaseLocks(_ paths: [String]) {
        lockQueue.sync(flags: .barrier) {
            for path in paths {
                guard locks[path] != nil else { continue }
                locks[path] = nil

                // Wake waiting operations
                if let continuations = waitingOperations[path] {
                    for continuation in continuations {
                        continuation.resume(returning: .success)
                    }
                    waitingOperations[path] = nil
                }
            }
            logger.debug("Batch released locks: \(paths.count)")
        }
    }

    /// Check if file is locked
    func isLocked(_ virtualPath: String) -> Bool {
        return lockQueue.sync {
            return locks[virtualPath] != nil
        }
    }

    /// Get source path for locked file (used for reads)
    func getSourcePath(_ virtualPath: String) -> String? {
        return lockQueue.sync {
            return locks[virtualPath]?.sourcePath
        }
    }

    /// Get lock info
    func getLockInfo(_ virtualPath: String) -> LockInfo? {
        return lockQueue.sync {
            return locks[virtualPath]
        }
    }

    /// Wait for lock release
    func waitForUnlock(_ virtualPath: String, timeout: TimeInterval? = nil) async -> WaitResult {
        let timeoutValue = timeout ?? writeWaitTimeout

        // Check if already unlocked
        let isCurrentlyLocked = lockQueue.sync { locks[virtualPath] != nil }
        if !isCurrentlyLocked {
            return .success
        }

        // Use TaskGroup to implement timeout
        return await withTaskGroup(of: WaitResult.self) { group in
            // Task waiting for lock release
            group.addTask {
                await withCheckedContinuation { continuation in
                    self.lockQueue.sync(flags: .barrier) {
                        // Check again, may have unlocked while waiting
                        if self.locks[virtualPath] == nil {
                            continuation.resume(returning: .success)
                            return
                        }

                        // Add to waiting list
                        if self.waitingOperations[virtualPath] == nil {
                            self.waitingOperations[virtualPath] = []
                        }
                        self.waitingOperations[virtualPath]?.append(continuation)
                    }
                }
            }

            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutValue * 1_000_000_000))
                return .timeout
            }

            // Return first completed result
            let result = await group.next()!
            group.cancelAll()

            // If timed out, remove from waiting list
            if result == .timeout {
                lockQueue.sync(flags: .barrier) {
                    waitingOperations[virtualPath]?.removeAll { _ in true }
                }
            }

            return result
        }
    }

    /// Get all locked file paths
    func getLockedPaths() -> [String] {
        return lockQueue.sync {
            return Array(locks.keys)
        }
    }

    /// Get locked file count
    var lockedCount: Int {
        return lockQueue.sync { locks.count }
    }

    // MARK: - Private Methods

    /// Start lock timeout checker timer
    private func startTimeoutChecker() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkTimeouts()
        }
    }

    /// Check and handle timed out locks
    private func checkTimeouts() {
        lockQueue.sync(flags: .barrier) {
            let now = Date()
            var expiredPaths: [String] = []

            for (path, info) in locks {
                if now.timeIntervalSince(info.lockTime) > lockTimeout {
                    expiredPaths.append(path)
                }
            }

            for path in expiredPaths {
                logger.warn("Lock timed out, auto-releasing: \(path)")
                locks[path] = nil

                // Wake waiting operations
                if let continuations = waitingOperations[path] {
                    for continuation in continuations {
                        continuation.resume(returning: .success)
                    }
                    waitingOperations[path] = nil
                }
            }
        }
    }

    /// Force release all locks (used during app exit)
    func releaseAllLocks() {
        lockQueue.sync(flags: .barrier) {
            for (path, _) in locks {
                if let continuations = waitingOperations[path] {
                    for continuation in continuations {
                        continuation.resume(returning: .cancelled)
                    }
                }
            }
            locks.removeAll()
            waitingOperations.removeAll()
            logger.info("All sync locks released")
        }
    }
}
