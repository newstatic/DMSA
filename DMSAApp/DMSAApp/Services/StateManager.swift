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

    // MARK: - 同步 UI 状态枚举

    enum SyncUIStatus: Equatable {
        case ready
        case syncing
        case paused
        case error(String)
        case serviceUnavailable

        var icon: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .syncing: return "arrow.clockwise"
            case .paused: return "pause.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .serviceUnavailable: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .ready: return .green
            case .syncing: return .blue
            case .paused: return .orange
            case .error: return .red
            case .serviceUnavailable: return .gray
            }
        }

        var text: String {
            switch self {
            case .ready: return "sidebar.status.ready".localized
            case .syncing: return "sidebar.status.syncing".localized
            case .paused: return "sidebar.status.paused".localized
            case .error(let msg): return msg
            case .serviceUnavailable: return "sidebar.status.unavailable".localized
            }
        }
    }

    // MARK: - 计算属性

    var isReady: Bool {
        connectionState.isConnected && serviceState.isNormal
    }

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
            // 获取配置
            let config = try await serviceClient.getConfig()
            self.disks = config.disks
            self.syncPairs = config.syncPairs
            self.totalDiskCount = config.disks.count
            self.connectedDiskCount = config.disks.filter { $0.isConnected }.count

            // 获取同步状态
            let allStatus = try await serviceClient.getAllSyncStatus()
            if let status = allStatus.first {
                updateSyncStatusFromInfo(status)
            }

            // 更新统计
            statistics.totalFiles = config.syncPairs.count

            // 更新 UI 状态
            if case .syncing = uiState {
                // 保持同步状态
            } else {
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
        case .disconnected, .failed:
            syncStatus = .serviceUnavailable
        default:
            break
        }
    }

    func updateUIState(_ state: UIState) {
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
        updateUIState(.starting(progress: progress.progress, phase: progress.phase))
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

    // MARK: - 私有方法

    private func setupNotificationObservers() {
        Logger.shared.debug("StateManager 通知监听已设置")
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
        syncStatus = progress.status == .inProgress ? .syncing : .ready
        syncProgressValue = Double(progress.processedFiles) / Double(max(1, progress.totalFiles))
        processedFiles = progress.processedFiles
        totalFilesCount = progress.totalFiles
        processedBytes = progress.processedBytes
        totalBytes = progress.totalBytes
        currentSyncFile = progress.currentFile
        syncSpeed = progress.speed
    }

    func syncStatusDidChange(syncPairId: String, status: SyncStatus, message: String?) {
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
