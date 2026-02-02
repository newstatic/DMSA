import Foundation

/// Sync state manager - supports pause/resume sync
class SyncStateManager {

    // MARK: - State Data Structure

    /// Sync state snapshot
    struct SyncState: Codable {
        /// Sync pair ID
        let syncPairId: String

        /// Start time
        let startedAt: Date

        /// Last updated time
        var lastUpdatedAt: Date

        /// Current phase
        var phase: SyncPhase

        /// Completed action indices
        var completedActionIndices: Set<Int>

        /// Pending action indices
        var pendingActionIndices: Set<Int>

        /// Original sync plan
        var plan: SyncPlan

        /// Source directory snapshot
        var sourceSnapshot: DirectorySnapshot?

        /// Destination directory snapshot
        var destinationSnapshot: DirectorySnapshot?

        /// Processed bytes
        var processedBytes: Int64

        /// Processed files
        var processedFiles: Int

        /// Failed actions
        var failedActions: [FailedAction]

        /// Whether resumable
        var isResumable: Bool {
            !pendingActionIndices.isEmpty && phase != .completed && phase != .cancelled
        }

        /// Resume progress
        var resumeProgress: Double {
            let total = completedActionIndices.count + pendingActionIndices.count
            return total > 0 ? Double(completedActionIndices.count) / Double(total) : 0
        }
    }

    // MARK: - Properties

    /// State file directory
    private let stateDirectory: URL

    /// File manager
    private let fileManager = FileManager.default

    /// JSON encoder
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// JSON decoder
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Auto-save interval (in file count)
    var checkpointInterval: Int = 50

    /// Logger
    private let logger = Logger.forService("SyncStateManager")

    // MARK: - Initialization

    init(stateDirectory: URL? = nil) {
        if let dir = stateDirectory {
            self.stateDirectory = dir
        } else {
            // Default to Application Support directory
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.stateDirectory = appSupport.appendingPathComponent("DMSA/SyncState")
        }

        // Ensure directory exists
        try? fileManager.createDirectory(at: self.stateDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    /// Create new sync state
    func createState(for plan: SyncPlan) -> SyncState {
        let actionIndices = Set(0..<plan.actions.count)

        return SyncState(
            syncPairId: plan.syncPairId,
            startedAt: Date(),
            lastUpdatedAt: Date(),
            phase: .idle,
            completedActionIndices: [],
            pendingActionIndices: actionIndices,
            plan: plan,
            sourceSnapshot: plan.sourceSnapshot,
            destinationSnapshot: plan.destinationSnapshot,
            processedBytes: 0,
            processedFiles: 0,
            failedActions: []
        )
    }

    /// Save sync state
    func saveState(_ state: SyncState) throws {
        var mutableState = state
        mutableState.lastUpdatedAt = Date()

        let data = try encoder.encode(mutableState)
        let filePath = stateFilePath(for: state.syncPairId)

        try data.write(to: filePath, options: .atomic)

        logger.debug("Sync state saved: \(state.syncPairId)")
    }

    /// Load sync state
    func loadState(for syncPairId: String) throws -> SyncState? {
        let filePath = stateFilePath(for: syncPairId)

        guard fileManager.fileExists(atPath: filePath.path) else {
            return nil
        }

        let data = try Data(contentsOf: filePath)
        let state = try decoder.decode(SyncState.self, from: data)

        logger.debug("Sync state loaded: \(syncPairId)")
        return state
    }

    /// Clear sync state
    func clearState(for syncPairId: String) throws {
        let filePath = stateFilePath(for: syncPairId)

        if fileManager.fileExists(atPath: filePath.path) {
            try fileManager.removeItem(at: filePath)
            logger.debug("Sync state cleared: \(syncPairId)")
        }
    }

    /// Get all resumable states
    func getResumableStates() throws -> [SyncState] {
        guard fileManager.fileExists(atPath: stateDirectory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: stateDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var states: [SyncState] = []

        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let state = try decoder.decode(SyncState.self, from: data)
                if state.isResumable {
                    states.append(state)
                }
            } catch {
                logger.warning("Failed to load state file: \(file.path), error: \(error)")
            }
        }

        return states.sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    /// Clean up expired states (default 7 days)
    func cleanupExpiredStates(olderThan days: Int = 7) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        guard fileManager.fileExists(atPath: stateDirectory.path) else {
            return
        }

        let files = try fileManager.contentsOfDirectory(
            at: stateDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        for file in files {
            let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modDate = attrs.contentModificationDate, modDate < cutoffDate {
                try fileManager.removeItem(at: file)
                logger.info("Cleaned up expired state: \(file.lastPathComponent)")
            }
        }
    }

    /// Update state progress
    func updateProgress(
        state: inout SyncState,
        completedIndex: Int,
        bytes: Int64 = 0
    ) {
        state.completedActionIndices.insert(completedIndex)
        state.pendingActionIndices.remove(completedIndex)
        state.processedFiles += 1
        state.processedBytes += bytes
        state.lastUpdatedAt = Date()

        // Check if auto-save is needed
        if state.processedFiles % checkpointInterval == 0 {
            try? saveState(state)
        }
    }

    /// Mark action as failed
    func markFailed(
        state: inout SyncState,
        index: Int,
        error: Error
    ) {
        state.pendingActionIndices.remove(index)

        let action = state.plan.actions[index]
        state.failedActions.append(FailedAction(
            action: action,
            error: error.localizedDescription,
            timestamp: Date()
        ))

        state.lastUpdatedAt = Date()
    }

    /// Update phase
    func updatePhase(state: inout SyncState, phase: SyncPhase) {
        state.phase = phase
        state.lastUpdatedAt = Date()
        try? saveState(state)
    }

    /// Get pending actions
    func getPendingActions(from state: SyncState) -> [SyncAction] {
        return state.pendingActionIndices.sorted().compactMap { index in
            guard index < state.plan.actions.count else { return nil }
            return state.plan.actions[index]
        }
    }

    /// Check if there is a resumable sync
    func hasResumableSync(for syncPairId: String) -> Bool {
        guard let state = try? loadState(for: syncPairId) else {
            return false
        }
        return state.isResumable
    }

    // MARK: - Private Methods

    private func stateFilePath(for syncPairId: String) -> URL {
        let safeId = syncPairId.replacingOccurrences(of: "/", with: "_")
        return stateDirectory.appendingPathComponent("\(safeId).json")
    }
}

// MARK: - State Recovery Helper

extension SyncStateManager {

    /// Restore sync progress object from state
    func restoreProgress(from state: SyncState) -> ServiceSyncProgress {
        let progress = ServiceSyncProgress()

        progress.phase = state.phase
        progress.processedFiles = state.processedFiles
        progress.totalFiles = state.plan.actions.filter { action in
            switch action {
            case .copy, .update: return true
            default: return false
            }
        }.count
        progress.processedBytes = state.processedBytes
        progress.totalBytes = state.plan.totalBytes

        return progress
    }

    /// Generate resume summary
    func getResumeSummary(from state: SyncState) -> String {
        let completed = state.completedActionIndices.count
        let pending = state.pendingActionIndices.count
        let total = completed + pending
        let progress = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let lastUpdate = formatter.string(from: state.lastUpdatedAt)

        return """
        Sync pair: \(state.syncPairId)
        Progress: \(completed)/\(total) (\(progress)%)
        Processed: \(ByteCountFormatter.string(fromByteCount: state.processedBytes, countStyle: .file))
        Last updated: \(lastUpdate)
        Phase: \(state.phase.description)
        """
    }
}
