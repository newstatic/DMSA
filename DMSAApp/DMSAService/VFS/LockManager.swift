import Foundation

// Note: SyncLockDirection is defined in DMSAShared/Models/FileEntry.swift

/// 同步锁管理器
/// 管理文件的同步锁定状态，确保同步期间的数据一致性
/// 策略: 悲观锁 + 读取不阻塞
/// - 读取: 允许，直接从源文件读取
/// - 写入: 阻塞，等待同步完成或超时
/// - 删除: 阻塞，等待同步完成或超时
final class LockManager {

    static let shared = LockManager()

    /// 锁定信息
    struct LockInfo {
        let virtualPath: String
        let lockTime: Date
        let direction: SyncLockDirection
        let sourcePath: String  // 同步源路径，供读取使用
    }

    /// 等待结果
    enum WaitResult {
        case success      // 锁已释放
        case timeout      // 等待超时
        case cancelled    // 等待被取消
    }

    // 当前锁定的文件
    private var locks: [String: LockInfo] = [:]

    // 等待锁释放的 continuation
    private var waitingOperations: [String: [CheckedContinuation<WaitResult, Never>]] = [:]

    // 线程安全队列
    private let lockQueue = DispatchQueue(label: "com.dmsa.lockManager", attributes: .concurrent)

    // Logger
    private let logger = Logger.forService("LockManager")

    // 锁超时时间
    private let lockTimeout: TimeInterval = 300  // 5 minutes
    private let writeWaitTimeout: TimeInterval = 30  // 30 seconds

    private init() {
        // 启动锁超时检查定时器
        startTimeoutChecker()
    }

    // MARK: - Public Methods

    /// 获取同步锁
    func acquireLock(_ virtualPath: String, direction: SyncLockDirection, sourcePath: String) -> Bool {
        return lockQueue.sync(flags: .barrier) {
            // 检查是否已被锁定
            guard locks[virtualPath] == nil else {
                logger.warn("文件已被锁定: \(virtualPath)")
                return false
            }

            // 创建锁信息
            locks[virtualPath] = LockInfo(
                virtualPath: virtualPath,
                lockTime: Date(),
                direction: direction,
                sourcePath: sourcePath
            )

            logger.debug("获取同步锁: \(virtualPath), 方向: \(direction)")
            return true
        }
    }

    /// 释放同步锁
    func releaseLock(_ virtualPath: String) {
        lockQueue.sync(flags: .barrier) {
            guard locks[virtualPath] != nil else {
                return
            }

            locks[virtualPath] = nil

            // 唤醒所有等待的操作
            if let continuations = waitingOperations[virtualPath] {
                for continuation in continuations {
                    continuation.resume(returning: .success)
                }
                waitingOperations[virtualPath] = nil
            }

            logger.debug("释放同步锁: \(virtualPath)")
        }
    }

    /// 批量获取锁
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

            logger.debug("批量获取锁: \(lockedPaths.count)/\(paths.count) 个")
            return lockedPaths
        }
    }

    /// 批量释放锁
    func releaseLocks(_ paths: [String]) {
        lockQueue.sync(flags: .barrier) {
            for path in paths {
                guard locks[path] != nil else { continue }
                locks[path] = nil

                // 唤醒等待的操作
                if let continuations = waitingOperations[path] {
                    for continuation in continuations {
                        continuation.resume(returning: .success)
                    }
                    waitingOperations[path] = nil
                }
            }
            logger.debug("批量释放锁: \(paths.count) 个")
        }
    }

    /// 检查文件是否被锁定
    func isLocked(_ virtualPath: String) -> Bool {
        return lockQueue.sync {
            return locks[virtualPath] != nil
        }
    }

    /// 获取锁定文件的源路径（用于读取）
    func getSourcePath(_ virtualPath: String) -> String? {
        return lockQueue.sync {
            return locks[virtualPath]?.sourcePath
        }
    }

    /// 获取锁信息
    func getLockInfo(_ virtualPath: String) -> LockInfo? {
        return lockQueue.sync {
            return locks[virtualPath]
        }
    }

    /// 等待锁释放
    func waitForUnlock(_ virtualPath: String, timeout: TimeInterval? = nil) async -> WaitResult {
        let timeoutValue = timeout ?? writeWaitTimeout

        // 先检查是否已经解锁
        let isCurrentlyLocked = lockQueue.sync { locks[virtualPath] != nil }
        if !isCurrentlyLocked {
            return .success
        }

        // 使用 Task 组实现超时
        return await withTaskGroup(of: WaitResult.self) { group in
            // 等待锁释放的任务
            group.addTask {
                await withCheckedContinuation { continuation in
                    self.lockQueue.sync(flags: .barrier) {
                        // 再次检查，可能在等待期间已解锁
                        if self.locks[virtualPath] == nil {
                            continuation.resume(returning: .success)
                            return
                        }

                        // 添加到等待列表
                        if self.waitingOperations[virtualPath] == nil {
                            self.waitingOperations[virtualPath] = []
                        }
                        self.waitingOperations[virtualPath]?.append(continuation)
                    }
                }
            }

            // 超时任务
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutValue * 1_000_000_000))
                return .timeout
            }

            // 返回第一个完成的结果
            let result = await group.next()!
            group.cancelAll()

            // 如果超时，从等待列表中移除
            if result == .timeout {
                lockQueue.sync(flags: .barrier) {
                    waitingOperations[virtualPath]?.removeAll { _ in true }
                }
            }

            return result
        }
    }

    /// 获取所有锁定的文件路径
    func getLockedPaths() -> [String] {
        return lockQueue.sync {
            return Array(locks.keys)
        }
    }

    /// 获取锁定文件数量
    var lockedCount: Int {
        return lockQueue.sync { locks.count }
    }

    // MARK: - Private Methods

    /// 启动锁超时检查定时器
    private func startTimeoutChecker() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkTimeouts()
        }
    }

    /// 检查并处理超时的锁
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
                logger.warn("锁超时自动释放: \(path)")
                locks[path] = nil

                // 唤醒等待的操作
                if let continuations = waitingOperations[path] {
                    for continuation in continuations {
                        continuation.resume(returning: .success)
                    }
                    waitingOperations[path] = nil
                }
            }
        }
    }

    /// 强制释放所有锁（用于应用退出时）
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
            logger.info("已释放所有同步锁")
        }
    }
}
