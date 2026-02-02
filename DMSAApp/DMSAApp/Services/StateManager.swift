import Foundation
import Combine
import SwiftUI

/// App state manager
/// Manages App global state, bridges ServiceClient notifications to UI
/// v4.8: Merged AppUIState functionality, now the sole state manager
@MainActor
final class StateManager: ObservableObject {

    // MARK: - Singleton

    static let shared = StateManager()

    // MARK: - Connection State

    @Published private(set) var connectionState: ConnectionState = .disconnected

    // MARK: - Service State

    @Published var serviceState: ServiceState = .starting
    @Published var componentStates: [String: ComponentState] = [:]

    // MARK: - UI State

    @Published private(set) var uiState: UIState = .initializing

    // MARK: - Sync UI State (formerly AppUIState)

    @Published var syncStatus: SyncUIStatus = .ready
    @Published var conflictCount: Int = 0
    @Published var lastSyncTime: Date?
    @Published var connectedDiskCount: Int = 0
    @Published var totalDiskCount: Int = 0

    // MARK: - Sync Progress Details

    @Published var currentSyncFile: String?
    @Published var syncSpeed: Int64 = 0
    @Published var processedFiles: Int = 0
    @Published var processedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var totalFilesCount: Int = 0
    @Published var syncProgressValue: Double = 0

    // MARK: - Data State

    @Published var syncPairs: [SyncPairConfig] = []
    @Published var disks: [DiskConfig] = []

    // MARK: - Progress State

    @Published var indexProgress: IndexProgress?
    @Published var syncProgress: SyncProgressInfo?
    @Published var evictionProgress: EvictionProgress?

    // MARK: - Error State

    @Published var lastError: AppError?
    @Published var pendingConflicts: Int = 0

    // MARK: - Statistics

    @Published var statistics: AppStatistics = AppStatistics()

    // MARK: - Recent Activities

    @Published var recentActivities: [ActivityRecord] = []

    // MARK: - Sync UI State Enum

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

    // MARK: - Computed Properties

    var isReady: Bool {
        let connected = connectionState.isConnected
        let normal = serviceState.isNormal
        let result = connected && normal
        // Only log on state change to avoid excessive logs
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

    // MARK: - Private Properties

    private let serviceClient = ServiceClient.shared
    private var cancellables = Set<AnyCancellable>()
    private var stateRefreshTimer: Timer?
    private let stateRefreshInterval: TimeInterval = 30 // 30s refresh interval

    // MARK: - Initialization

    private init() {
        setupNotificationObservers()
        // Register as ServiceClient notification delegate
        ServiceClient.shared.progressDelegate = self
    }

    deinit {
        stateRefreshTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Connect to Service and sync state
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

    /// Disconnect
    func disconnect() {
        stateRefreshTimer?.invalidate()
        serviceClient.disconnect()
        updateConnectionState(.disconnected)
        updateUIState(.serviceUnavailable)
    }

    /// Sync full state
    func syncFullState() async {
        guard connectionState.isConnected else { return }

        do {
            // 1. First get full service state (including ServiceState)
            if let fullState = try await serviceClient.getFullState() {
                self.serviceState = fullState.globalState
                updateSyncStatusFromServiceState(fullState.globalState)
                Logger.shared.info("Syncing ServiceState: \(fullState.globalState.name)")
            }

            // 2. Get config
            let config = try await serviceClient.getConfig()
            self.disks = config.disks
            self.syncPairs = config.syncPairs
            self.totalDiskCount = config.disks.count
            self.connectedDiskCount = config.disks.filter { $0.isConnected }.count

            // 3. Get sync status (only update when service ready and not syncing)
            let allStatus = try await serviceClient.getAllSyncStatus()
            if let status = allStatus.first, serviceState.isNormal, syncStatus != .syncing {
                updateSyncStatusFromInfo(status)
            }

            // Get index stats and update
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
                    Logger.shared.warning("Failed to get index stats: \(syncPair.id) - \(error)")
                }
            }

            // Update statistics (with debug logging)
            statistics.totalFiles = totalFiles
            statistics.totalSize = totalSize
            statistics.dirtyFiles = dirtyFiles
            statistics.localFiles = localFiles
            Logger.shared.debug("[StateManager] statistics updated: totalFiles=\(totalFiles), totalSize=\(totalSize)")

            // 4. Get recent activities
            if let activities = try? await serviceClient.getRecentActivities() {
                self.recentActivities = activities
            }

            // Update UI state (only when service is ready and not syncing)
            if case .syncing = uiState {
                // Keep sync state
            } else if syncStatus == .syncing {
                // Keep sync state (controlled by XPC callbacks)
            } else if serviceState.isNormal {
                updateUIState(.ready)
            }

            Logger.shared.debug("State sync complete")
        } catch {
            Logger.shared.error("State sync failed: \(error)")
            lastError = AppError(
                code: 1001,
                message: "State sync failed: \(error.localizedDescription)",
                severity: .warning,
                isRecoverable: true
            )
        }
    }

    /// Save state to cache (for background switching)
    func saveToCache() {
        UserDefaults.standard.set(statistics.lastSyncTime?.timeIntervalSince1970, forKey: "lastSyncTime")
        UserDefaults.standard.set(pendingConflicts, forKey: "pendingConflicts")
        UserDefaults.standard.set(conflictCount, forKey: "conflictCount")
        Logger.shared.debug("State saved to cache")
    }

    /// Restore state from cache
    func restoreFromCache() {
        if let lastSyncTimestamp = UserDefaults.standard.object(forKey: "lastSyncTime") as? TimeInterval {
            statistics.lastSyncTime = Date(timeIntervalSince1970: lastSyncTimestamp)
            lastSyncTime = statistics.lastSyncTime
        }
        pendingConflicts = UserDefaults.standard.integer(forKey: "pendingConflicts")
        conflictCount = UserDefaults.standard.integer(forKey: "conflictCount")
        Logger.shared.debug("State restored from cache")
    }

    // MARK: - State Update Methods

    func updateConnectionState(_ state: ConnectionState) {
        connectionState = state
        Logger.shared.debug("Connection state updated: \(state.description)")

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
        Logger.shared.debug("UI state updated: \(state)")

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

        // If status changed, post notification to update menu bar
        if previousStatus != syncStatus {
            Logger.shared.debug("syncStatus changed: \(previousStatus.text) -> \(syncStatus.text)")
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
        }
    }

    func updateSyncProgress(_ progress: SyncProgressInfo) {
        syncProgress = progress
        updateUIState(.syncing(progress: progress.progress, currentFile: progress.currentFile))

        // Update progress details
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

    /// Update UI state based on ServiceState
    func updateSyncStatusFromServiceState(_ state: ServiceState) {
        // If currently syncing, do not override state
        if syncStatus == .syncing {
            Logger.shared.debug("Currently syncing, skipping ServiceState update")
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
        Logger.shared.debug("syncStatus updated to: \(syncStatus.text)")

        // Post notification to update menu bar
        NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
    }

    // MARK: - Private Methods

    private func setupNotificationObservers() {
        // Listen for XPC state change notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAServiceStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let newServiceState = userInfo["serviceState"] as? ServiceState else { return }

            self?.serviceState = newServiceState
            self?.updateSyncStatusFromServiceState(newServiceState)
            Logger.shared.info("[StateManager] Received state change: \(newServiceState.name)")
        }

        // Listen for disk change notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSADiskChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let diskName = userInfo["diskName"] as? String,
                  let isConnected = userInfo["isConnected"] as? Bool else { return }

            Logger.shared.info("[StateManager] Disk changed: \(diskName) -> \(isConnected ? "connected" : "disconnected")")

            // Refresh full state to get latest disk connection status
            Task { @MainActor in
                await self?.syncFullState()
            }
        }

        // Listen for activity update notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAActivitiesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let activities = userInfo["activities"] as? [ActivityRecord] else { return }
            self?.recentActivities = activities
        }

        // Listen for component error notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DMSAComponentError"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let component = userInfo["component"] as? String,
                  let message = userInfo["message"] as? String,
                  let isCritical = userInfo["isCritical"] as? Bool else { return }

            Logger.shared.warning("[StateManager] Component error: \(component) - \(message)")

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

        // Listen for index progress notifications
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

        // Listen for conflict detection notifications
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

            Logger.shared.warning("[StateManager] Detected \(conflicts.count)  conflicts")
        }

        Logger.shared.debug("StateManager notification listeners configured (XPC callbacks)")
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
                message: "Sync error",
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
        // Use bytes for more accurate progress
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

        // Logging and notifications
        if oldStatus != newStatus {
            Logger.shared.debug("[StateManager] syncStatus changed: \(oldStatus.text) -> \(newStatus.text)")
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

        // Post notification to update UI
        if oldStatus != syncStatus {
            NotificationCenter.default.post(name: .syncStatusDidChange, object: nil)
        }
    }

    func serviceDidBecomeReady() {
        syncStatus = .ready
    }

    func configDidUpdate() {
        Logger.shared.debug("Config updated, refreshing state")
        Task {
            await syncFullState()
        }
    }
}

// MARK: - SyncStatusInfo Extension

extension SyncStatusInfo {
    var progress: Double {
        // SyncStatusInfo has no totalFiles property, use alternative calculation
        return 0
    }
}
