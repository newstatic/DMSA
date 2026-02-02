import Foundation
import Combine
import SwiftUI

/// 应用状态管理器
/// 负责管理 App 全局状态，桥接 ServiceClient 通知到 UI
/// v4.8: 合并了 AppUIState 的功能，成为唯一的状态管理器
@MainActor
final class StateManager: ObservableObject {

    // MARK: - Singleton

    static let shared = StateManager()

    // MARK: - 连接状态

    @Published private(set) var connectionState: ConnectionState = .disconnected

    // MARK: - Service 状态

    @Published var serviceState: ServiceState = .starting
    @Published var componentStates: [String: ComponentState] = [:]

    // MARK: - UI 状态

    @Published private(set) var uiState: UIState = .initializing

    // MARK: - 同步 UI 状态 (原 AppUIState)

    @Published var syncStatus: SyncUIStatus = .ready
    @Published var conflictCount: Int = 0
    @Published var lastSyncTime: Date?
    @Published var connectedDiskCount: Int = 0
    @Published var totalDiskCount: Int = 0

    // MARK: - 同步进度详情

    @Published var currentSyncFile: String?
    @Published var syncSpeed: Int64 = 0
    @Published var processedFiles: Int = 0
    @Published var processedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var totalFilesCount: Int = 0
    @Published var syncProgressValue: Double = 0

    // MARK: - 数据状态

    @Published var syncPairs: [SyncPairConfig] = []
    @Published var disks: [DiskConfig] = []

    // MARK: - 进度状态

    @Published var indexProgress: IndexProgress?
    @Published var syncProgress: SyncProgressInfo?
    @Published var evictionProgress: EvictionProgress?

    // MARK: - 错误状态

    @Published var lastError: AppError?
    @Published var pendingConflicts: Int = 0

    // MARK: - 统计

    @Published var statistics: AppStatistics = AppStatistics()

    // MARK: - 最近活动

    @Published var recentActivities: [ActivityRecord] = []

    // MARK: - 同步 UI 状态枚举

    enum SyncUIStatus: Equatable {
        case ready
        case syncing
        case indexing
        case starting
        case paused
        case reconnecting
        case error(String)
        case serviceUnavailable

        var icon: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .syncing: return "arrow.clockwise"
            case .indexing: return "doc.text.magnifyingglass"
            case .starting: return "gear"
            case .paused: return "pause.circle.fill"
            case .reconnecting: return "arrow.triangle.2.circlepath"
            case .error: return "exclamationmark.triangle.fill"
            case .serviceUnavailable: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .ready: return .green
            case .syncing: return .blue
            case .indexing: return .orange
            case .starting: return .yellow
            case .paused: return .orange
            case .reconnecting: return .orange
            case .error: return .red
            case .serviceUnavailable: return .gray
            }
        }

        var text: String {
            switch self {
            case .ready: return "sidebar.status.ready".localized
            case .syncing: return "sidebar.status.syncing".localized
            case .indexing: return "sidebar.status.indexing".localized
            case .starting: return "sidebar.status.starting".localized
            case .paused: return "sidebar.status.paused".localized
            case .reconnecting: return "sidebar.status.reconnecting".localized
            case .error(let msg): return msg
            case .serviceUnavailable: return "sidebar.status.unavailable".localized
            }
        }
    }

    // MARK: - 计算属性

    var isReady: Bool {
        let connected = connectionState.isConnected
        let normal = serviceState.isNormal
        let result = connected && normal
        // 仅在状态变化时记录，避免日志过多
        if result != _lastIsReadyValue {
            Logger.shared.debug("[StateManager] isReady: \(result) (connected=\(connected), serviceState=\(serviceState.name), isNormal=\(normal))")
            _lastIsReadyValue = result
        }
        return result
    }
    private var _lastIsReadyValue: Bool = false

    var canSync: Bool {
        isReady && !disks.filter { $0.isConnected }.isEmpty
    }

    var isSyncing: Bool {
        if case .syncing = uiState { return true }
        if syncStatus == .syncing { return true }
        return false
    }

    // MARK: - 私有属性

    private let serviceClient = ServiceClient.shared
    private var cancellables = Set<AnyCancellable>()
    private var stateRefreshTimer: Timer?
    private let stateRefreshInterval: TimeInterval = 30 // 30秒刷新一次

    // MARK: - 初始化

    private init() {
        setupNotificationObservers()
        // 注册为 ServiceClient 的通知代理
        ServiceClient.shared.progressDelegate = self
    }

    deinit {
        stateRefreshTimer?.invalidate()
    }

    // MARK: - 公共方法

    /// 连接到 Service 并同步状态
    func connect() async {
        updateConnectionState(.connecting)

        do {
            _ = try await serviceClient.connect()
            updateConnectionState(.connected)
            await syncFullState()
            startStateRefreshTimer()
        } catch {
            updateConnectionState(.failed(error.localizedDescription))
            updateUIState(.serviceUnavailable)
        }
    }

    /// 断开连接
    func disconnect() {
        stateRefreshTimer?.invalidate()
        serviceClient.disconnect()
        updateConnectionState(.disconnected)
        updateUIState(.serviceUnavailable)
    }

    /// 同步完整状态
    func syncFullState() async {
        guard connectionState.isConnected else { return }

        do {
            // 1. 首先获取服务完整状态 (包括 ServiceState)
            if let fullState = try await serviceClient.getFullState() {
                self.serviceState = fullState.globalState
                updateSyncStatusFromServiceState(fullState.globalState)
                Logger.shared.info("同步 ServiceState: \(fullState.globalState.name)")
            }

            // 2. 获取配置
            let config = try await serviceClient.getConfig()
            self.disks = config.disks
            self.syncPairs = config.syncPairs
            self.totalDiskCount = config.disks.count
            self.connectedDiskCount = config.disks.filter { $0.isConnected }.count

            // 3. 获取同步状态 (仅在服务就绪且当前不在同步中时才更新)
            let allStatus = try await serviceClient.getAllSyncStatus()
            if let status = allStatus.first, serviceState.isNormal, syncStatus != .syncing {
                updateSyncStatusFromInfo(status)
            }

            // 获取索引统计并更新
            var totalFiles = 0
            var totalSize: Int64 = 0
            var dirtyFiles = 0
            var localFiles = 0

            for syncPair in config.syncPairs {
                do {
                    let stats = try await serviceClient.getIndexStats(syncPairId: syncPair.id)
                    totalFiles += stats.totalFiles
                    totalSize += stats.totalSize
                    dirtyFiles += stats.dirtyCount
                    localFiles += stats.localOnlyCount + stats.bothCount
                } catch {
                    Logger.shared.warning("获取索引统计失败: \(syncPair.id) - \(error)")
                }
            }

            // 更新统计 (添加日志便于调试)
            statistics.totalFiles = totalFiles
            statistics.totalSize = totalSize
            statistics.dirtyFiles = dirtyFiles
            statistics.localFiles = localFiles
            Logger.shared.debug("[StateManager] statistics 更新: totalFiles=\(totalFiles), totalSize=\(totalSize)")

            // 4. 获取最近活动
            if let activities = try? await serviceClient.getRecentActivities() {
                self.recentActivities = activities
            }

            // 更新 UI 状态 (仅在服务就绪且非同步状态时)
            if case .syncing = uiState {
                // 保持同步状态
            } else if syncStatus == .syncing {
                // 保持同步状态 (由 XPC 回调控制)
            } else if serviceState.isNormal {
                updateUIState(.ready)
            }

            Logger.shared.debug("状态同步完成")
        } catch {
            Logger.shared.error("状态同步失败: \(error)")
            lastError = AppError(
                code: 1001,
                message: "状态同步失败: \(error.localizedDescription)",
                severity: .warning,
                isRecoverable: true
            )
        }
    }

    /// 保存状态到缓存 (用于后台切换)
    func saveToCache() {
        UserDefaults.standard.set(statistics.lastSyncTime?.timeIntervalSince1970, forKey: "lastSyncTime")
        UserDefaults.standard.set(pendingConflicts, forKey: "pendingConflicts")
        UserDefaults.standard.set(conflictCount, forKey: "conflictCount")
        Logger.shared.debug("状态已保存到缓存")
    }

    /// 从缓存恢复状态
    func restoreFromCache() {
        if let lastSyncTimestamp = UserDefaults.standard.object(forKey: "lastSyncTime") as? TimeInterval {
            statistics.lastSyncTime = Date(timeIntervalSince1970: lastSyncTimestamp)
            lastSyncTime = statistics.lastSyncTime
        }
        pendingConflicts = UserDefaults.standard.integer(forKey: "pendingConflicts")
        conflictCount = UserDefaults.standard.integer(forKey: "conflictCount")
        Logger.shared.debug("状态已从缓存恢复")
    }

    // MARK: - 状态更新方法

    func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        Logger.shared.debug("连接状态更新: \(state.description)")

        switch state {
        case .connected:
            syncStatus = .ready
        case .interrupted:
            syncStatus = .reconnecting
        case .disconnected, .failed:
            syncStatus = .serviceUnavailable
        default:
            break
        }
    }

    func updateUIState(_ state: UIState) {
        let previousStatus = syncStatus
        uiState = state
        Logger.shared.debug("UI 状态更新: \(state)")

        switch state {
        case .ready:
            syncStatus = .ready
        case .syncing(let progress, _):
            syncStatus = .syncing
            syncProgressValue = progress
        case .error(let error):
            syncStatus = .error(error.message)
        case .serviceUnavailable:
            syncStatus = .serviceUnavailable
        default:
            break
        }

        // 如果状态变化，发送通知更新菜单栏
        if previousStatus != syncStatus {
            Logger.shared.debug("syncStatus 变化: \(previousStatus.text) -> \(syncStatus.text)")
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
        }
    }

    func updateSyncProgress(_ progress: SyncProgressInfo) {
        syncProgress = progress
        updateUIState(.syncing(progress: progress.progress, currentFile: progress.currentFile))

        // 更新进度详情
        syncProgressValue = progress.progress
        processedFiles = progress.processedFiles
        totalFilesCount = progress.totalFiles
        processedBytes = progress.processedBytes
        totalBytes = progress.totalBytes
        currentSyncFile = progress.currentFile
        syncSpeed = progress.speed
    }

    func updateIndexProgress(_ progress: IndexProgress) {
        indexProgress = progress
        updateUIState(.starting(progress: progress.progress, phase: progress.phase.localizedDescription))
    }

    func updateEvictionProgress(_ progress: EvictionProgress) {
        evictionProgress = progress
        updateUIState(.evicting(progress: progress.progress))
    }

    func updateError(_ error: AppError) {
        lastError = error
        if error.severity == .critical {
            updateUIState(.error(error))
        }
    }

    func clearError() {
        lastError = nil
        if case .error = uiState {
            updateUIState(.ready)
        }
    }

    /// 根据 ServiceState 更新 UI 状态
    func updateSyncStatusFromServiceState(_ state: ServiceState) {
        // 如果当前正在同步，不要覆盖状态
        if syncStatus == .syncing {
            Logger.shared.debug("当前正在同步，跳过 ServiceState 更新")
            return
        }

        switch state {
        case .starting, .xpcReady, .vfsMounting:
            syncStatus = .starting
        case .vfsBlocked, .indexing:
            syncStatus = .indexing
        case .ready, .running:
            syncStatus = .ready
        case .shuttingDown:
            syncStatus = .serviceUnavailable
        case .error:
            syncStatus = .error("service.error".localized)
        }
        Logger.shared.debug("syncStatus 已更新为: \(syncStatus.text)")

        // 发送通知更新菜单栏
        NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
    }

    // MARK: - 私有方法

    private func setupNotificationObservers() {
        // 监听 XPC 状态变更通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAServiceStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let newServiceState = userInfo["serviceState"] as? ServiceState else { return }

            self?.serviceState = newServiceState
            self?.updateSyncStatusFromServiceState(newServiceState)
            Logger.shared.info("[StateManager] 收到状态变更: \(newServiceState.name)")
        }

        // 监听磁盘变更通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSADiskChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let diskName = userInfo["diskName"] as? String,
                  let isConnected = userInfo["isConnected"] as? Bool else { return }

            Logger.shared.info("[StateManager] 磁盘变更: \(diskName) -> \(isConnected ? "连接" : "断开")")

            // 刷新完整状态以获取最新的磁盘连接状态
            Task { @MainActor in
                await self?.syncFullState()
            }
        }

        // 监听活动更新通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAActivitiesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let activities = userInfo["activities"] as? [ActivityRecord] else { return }
            self?.recentActivities = activities
        }

        // 监听组件错误通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAComponentError"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let component = userInfo["component"] as? String,
                  let message = userInfo["message"] as? String,
                  let isCritical = userInfo["isCritical"] as? Bool else { return }

            Logger.shared.warning("[StateManager] 组件错误: \(component) - \(message)")

            if isCritical {
                let error = AppError(
                    code: 5000,
                    message: "\(component): \(message)",
                    severity: .critical,
                    isRecoverable: false
                )
                self?.lastError = error
                self?.updateUIState(.error(error))
            }
        }

        // 监听索引进度通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAIndexProgressUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let data = userInfo["data"] as? Data,
                  let progress = try? JSONDecoder().decode(IndexProgress.self, from: data) else { return }

            self?.indexProgress = progress
        }

        // 监听冲突检测通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAConflictDetected"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let data = userInfo["data"] as? Data,
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let conflicts = info["conflicts"] as? [[String: Any]] else { return }

            self?.conflictCount = conflicts.count
            self?.pendingConflicts = conflicts.filter { $0["requiresUserAction"] as? Bool == true }.count

            Logger.shared.warning("[StateManager] 检测到 \(conflicts.count) 个冲突")
        }

        Logger.shared.debug("StateManager 通知监听已设置 (XPC 回调)")
    }

    private func startStateRefreshTimer() {
        stateRefreshTimer?.invalidate()
        stateRefreshTimer = Timer.scheduledTimer(withTimeInterval: stateRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncFullState()
            }
        }
    }

    private func updateSyncStatusFromInfo(_ status: SyncStatusInfo) {
        switch status.status {
        case .pending, .completed, .cancelled:
            updateUIState(.ready)
        case .inProgress:
            let progress = SyncProgressInfo(
                syncPairId: status.syncPairId,
                progress: status.progress,
                phase: "syncing"
            )
            updateSyncProgress(progress)
        case .paused:
            syncStatus = .paused
        case .failed:
            let error = AppError(
                code: 2001,
                message: "同步错误",
                severity: .warning,
                isRecoverable: true
            )
            updateError(error)
        }
    }
}

// MARK: - SyncProgressDelegate

extension StateManager: SyncProgressDelegate {
    func syncProgressDidUpdate(_ progress: SyncProgressData) {
        let newStatus: SyncUIStatus
        switch progress.status {
        case .inProgress:
            newStatus = .syncing
        case .paused:
            newStatus = .paused
        case .cancelled, .completed:
            newStatus = .ready
        case .failed:
            newStatus = .error(progress.errorMessage ?? "sync.error.unknown".localized)
        default:
            newStatus = .ready
        }
        let oldStatus = syncStatus

        syncStatus = newStatus
        // 使用字节计算进度更准确
        if progress.totalBytes > 0 {
            syncProgressValue = Double(progress.processedBytes) / Double(progress.totalBytes)
        } else {
            syncProgressValue = Double(progress.processedFiles) / Double(max(1, progress.totalFiles))
        }
        processedFiles = progress.processedFiles
        totalFilesCount = progress.totalFiles
        processedBytes = progress.processedBytes
        totalBytes = progress.totalBytes
        currentSyncFile = progress.currentFile
        syncSpeed = progress.speed

        Logger.shared.debug("[StateManager] syncProgressDidUpdate: status=\(newStatus.text), progress=\(Int(syncProgressValue * 100))%, files=\(processedFiles)/\(totalFilesCount)")

        // 日志和通知
        if oldStatus != newStatus {
            Logger.shared.debug("[StateManager] syncStatus 变化: \(oldStatus.text) -> \(newStatus.text)")
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
        }
    }

    func syncStatusDidChange(syncPairId: String, status: SyncStatus, message: String?) {
        let oldStatus = syncStatus

        switch status {
        case .pending, .completed, .cancelled:
            syncStatus = .ready
            if status == .completed {
                lastSyncTime = Date()
            }
        case .inProgress:
            syncStatus = .syncing
        case .paused:
            syncStatus = .paused
        case .failed:
            syncStatus = .error(message ?? "sync.error.unknown".localized)
        }

        Logger.shared.debug("[StateManager] syncStatusDidChange: \(oldStatus.text) -> \(syncStatus.text) (SyncStatus: \(status))")

        // 发送通知更新 UI
        if oldStatus != syncStatus {
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
        }
    }

    func serviceDidBecomeReady() {
        syncStatus = .ready
    }

    func configDidUpdate() {
        Logger.shared.debug("配置已更新，刷新状态")
        Task {
            await syncFullState()
        }
    }
}

// MARK: - SyncStatusInfo 扩展

extension SyncStatusInfo {
    var progress: Double {
        // SyncStatusInfo 没有 totalFiles 属性，使用其他方式计算
        return 0
    }
}
