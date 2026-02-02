import Foundation
import Combine

/// Sync progress tracking (internal to Service)
class ServiceSyncProgress: ObservableObject {
    // MARK: - Phase State

    /// Current sync phase
    @Published var phase: SyncPhase = .idle

    /// Overall progress (0.0 - 1.0)
    @Published var overallProgress: Double = 0

    // MARK: - Current File Progress

    /// Path of the file currently being processed
    @Published var currentFile: String = ""

    /// Current file progress (0.0 - 1.0)
    @Published var currentFileProgress: Double = 0

    /// Current file size
    @Published var currentFileSize: Int64 = 0

    /// Current file bytes transferred
    @Published var currentFileBytesTransferred: Int64 = 0

    // MARK: - Statistics

    /// Processed file count
    @Published var processedFiles: Int = 0

    /// Total file count
    @Published var totalFiles: Int = 0

    /// Processed bytes
    @Published var processedBytes: Int64 = 0

    /// Total bytes
    @Published var totalBytes: Int64 = 0

    /// Skipped file count
    @Published var skippedFiles: Int = 0

    /// Failed file count
    @Published var failedFiles: Int = 0

    // MARK: - Speed and Time

    /// Transfer speed (bytes/s)
    @Published var bytesPerSecond: Int64 = 0

    /// Estimated time remaining
    @Published var estimatedTimeRemaining: TimeInterval?

    /// Elapsed time
    @Published var elapsedTime: TimeInterval = 0

    /// Start time
    var startTime: Date?

    // MARK: - Checksum Progress

    /// Checksum progress (0.0 - 1.0)
    @Published var checksumProgress: Double?

    /// Current checksum phase description
    @Published var checksumPhase: String?

    /// Checksummed file count
    @Published var checksummedFiles: Int = 0

    /// Total files to checksum
    @Published var totalFilesToChecksum: Int = 0

    // MARK: - Verification Progress

    /// Verification progress (0.0 - 1.0)
    @Published var verificationProgress: Double?

    /// Verified file count
    @Published var verifiedFiles: Int = 0

    /// Verification failure count
    @Published var verificationFailures: Int = 0

    // MARK: - Error Info

    /// Last error message
    @Published var lastError: String?

    /// Error details list
    @Published var errors: [SyncError] = []

    /// Error message (compatibility property)
    var errorMessage: String? {
        get { lastError }
        set { lastError = newValue }
    }

    // MARK: - Error Record

    struct SyncError: Identifiable {
        let id = UUID()
        let timestamp: Date
        let file: String
        let message: String
        let isRecoverable: Bool
    }

    // MARK: - Computed Properties

    /// File progress description
    var fileProgressDescription: String {
        "\(processedFiles)/\(totalFiles) files"
    }

    /// Bytes progress description
    var bytesProgressDescription: String {
        let processed = ByteCountFormatter.string(fromByteCount: processedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(processed)/\(total)"
    }

    /// Speed description
    var speedDescription: String {
        if bytesPerSecond > 0 {
            return ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .file) + "/s"
        }
        return "--"
    }

    /// Time remaining description
    var timeRemainingDescription: String {
        guard let remaining = estimatedTimeRemaining, remaining > 0 else {
            return "--"
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: remaining) ?? "--"
    }

    /// Elapsed time description
    var elapsedTimeDescription: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: elapsedTime) ?? "0s"
    }

    /// Percentage description
    var percentageDescription: String {
        String(format: "%.1f%%", overallProgress * 100)
    }

    // MARK: - Methods

    /// Reset progress
    func reset() {
        phase = .idle
        overallProgress = 0
        currentFile = ""
        currentFileProgress = 0
        currentFileSize = 0
        currentFileBytesTransferred = 0
        processedFiles = 0
        totalFiles = 0
        processedBytes = 0
        totalBytes = 0
        skippedFiles = 0
        failedFiles = 0
        bytesPerSecond = 0
        estimatedTimeRemaining = nil
        elapsedTime = 0
        startTime = nil
        checksumProgress = nil
        checksumPhase = nil
        checksummedFiles = 0
        totalFilesToChecksum = 0
        verificationProgress = nil
        verifiedFiles = 0
        verificationFailures = 0
        lastError = nil
        errors.removeAll()
    }

    /// Start timer
    func start() {
        startTime = Date()
        elapsedTime = 0
    }

    /// Update elapsed time
    func updateElapsedTime() {
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    /// Update current file progress
    func updateFileProgress(file: String, bytesTransferred: Int64, totalSize: Int64) {
        currentFile = file
        currentFileSize = totalSize
        currentFileBytesTransferred = bytesTransferred
        currentFileProgress = totalSize > 0 ? Double(bytesTransferred) / Double(totalSize) : 0
    }

    /// Complete a file
    func completeFile(bytes: Int64) {
        processedFiles += 1
        processedBytes += bytes
        updateOverallProgress()
        updateSpeed()
    }

    /// Skip a file
    func skipFile() {
        skippedFiles += 1
        processedFiles += 1
        updateOverallProgress()
    }

    /// File failed
    func failFile(path: String, error: String, recoverable: Bool = false) {
        failedFiles += 1
        processedFiles += 1
        lastError = error
        errors.append(SyncError(
            timestamp: Date(),
            file: path,
            message: error,
            isRecoverable: recoverable
        ))
        updateOverallProgress()
    }

    /// Update overall progress
    private func updateOverallProgress() {
        guard totalFiles > 0 else { return }

        // Calculate progress weight based on current phase
        let phaseWeight: Double
        let phaseProgress: Double

        switch phase {
        case .scanning:
            phaseWeight = 0.15
            phaseProgress = Double(processedFiles) / Double(totalFiles)
        case .calculating:
            phaseWeight = 0.05
            phaseProgress = 1.0
        case .checksumming:
            phaseWeight = 0.10
            phaseProgress = checksumProgress ?? 0
        case .syncing:
            phaseWeight = 0.60
            phaseProgress = Double(processedFiles) / Double(totalFiles)
        case .verifying:
            phaseWeight = 0.10
            phaseProgress = verificationProgress ?? 0
        default:
            phaseWeight = 0
            phaseProgress = 0
        }

        // Accumulate progress from previous phases
        var baseProgress: Double = 0
        switch phase {
        case .calculating: baseProgress = 0.15
        case .checksumming: baseProgress = 0.20
        case .syncing: baseProgress = 0.30
        case .verifying: baseProgress = 0.90
        case .completed: baseProgress = 1.0
        default: break
        }

        overallProgress = min(1.0, baseProgress + phaseWeight * phaseProgress)
    }

    /// Update transfer speed
    private func updateSpeed() {
        guard elapsedTime > 0 else { return }

        bytesPerSecond = Int64(Double(processedBytes) / elapsedTime)

        // Calculate estimated time remaining
        let remainingBytes = totalBytes - processedBytes
        if bytesPerSecond > 0 {
            estimatedTimeRemaining = TimeInterval(remainingBytes) / TimeInterval(bytesPerSecond)
        }
    }

    /// Set phase
    func setPhase(_ newPhase: SyncPhase) {
        phase = newPhase

        // Reset related progress based on phase
        switch newPhase {
        case .scanning:
            processedFiles = 0
        case .checksumming:
            checksummedFiles = 0
            checksumProgress = 0
        case .syncing:
            processedFiles = 0
            processedBytes = 0
        case .verifying:
            verifiedFiles = 0
            verificationProgress = 0
        case .completed:
            overallProgress = 1.0
        default:
            break
        }
    }

    /// Convert to transferable SyncProgress struct
    func toSyncProgress(syncPairId: String) -> SyncProgress {
        var sp = SyncProgress(syncPairId: syncPairId)
        sp.phase = phase
        sp.totalFiles = totalFiles
        sp.processedFiles = processedFiles
        sp.totalBytes = totalBytes
        sp.processedBytes = processedBytes
        sp.currentFile = currentFile
        sp.startTime = startTime
        sp.errorMessage = lastError
        sp.speed = bytesPerSecond
        return sp
    }
}
