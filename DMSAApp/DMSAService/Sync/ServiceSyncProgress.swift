import Foundation
import Combine

/// 同步进度追踪 (Service 内部使用)
class ServiceSyncProgress: ObservableObject {
    // MARK: - 阶段状态

    /// 当前同步阶段
    @Published var phase: SyncPhase = .idle

    /// 总体进度 (0.0 - 1.0)
    @Published var overallProgress: Double = 0

    // MARK: - 当前文件进度

    /// 当前正在处理的文件路径
    @Published var currentFile: String = ""

    /// 当前文件进度 (0.0 - 1.0)
    @Published var currentFileProgress: Double = 0

    /// 当前文件大小
    @Published var currentFileSize: Int64 = 0

    /// 当前文件已传输字节数
    @Published var currentFileBytesTransferred: Int64 = 0

    // MARK: - 统计数据

    /// 已处理文件数
    @Published var processedFiles: Int = 0

    /// 总文件数
    @Published var totalFiles: Int = 0

    /// 已处理字节数
    @Published var processedBytes: Int64 = 0

    /// 总字节数
    @Published var totalBytes: Int64 = 0

    /// 跳过的文件数
    @Published var skippedFiles: Int = 0

    /// 失败的文件数
    @Published var failedFiles: Int = 0

    // MARK: - 速度和时间

    /// 传输速度 (bytes/s)
    @Published var bytesPerSecond: Int64 = 0

    /// 预计剩余时间
    @Published var estimatedTimeRemaining: TimeInterval?

    /// 已用时间
    @Published var elapsedTime: TimeInterval = 0

    /// 开始时间
    var startTime: Date?

    // MARK: - 校验进度

    /// 校验进度 (0.0 - 1.0)
    @Published var checksumProgress: Double?

    /// 当前校验阶段描述
    @Published var checksumPhase: String?

    /// 已校验文件数
    @Published var checksummedFiles: Int = 0

    /// 待校验文件数
    @Published var totalFilesToChecksum: Int = 0

    // MARK: - 验证进度

    /// 验证进度 (0.0 - 1.0)
    @Published var verificationProgress: Double?

    /// 已验证文件数
    @Published var verifiedFiles: Int = 0

    /// 验证失败数
    @Published var verificationFailures: Int = 0

    // MARK: - 错误信息

    /// 最后一个错误信息
    @Published var lastError: String?

    /// 错误详情列表
    @Published var errors: [SyncError] = []

    /// 错误消息 (兼容属性)
    var errorMessage: String? {
        get { lastError }
        set { lastError = newValue }
    }

    // MARK: - 错误记录

    struct SyncError: Identifiable {
        let id = UUID()
        let timestamp: Date
        let file: String
        let message: String
        let isRecoverable: Bool
    }

    // MARK: - 计算属性

    /// 文件进度描述
    var fileProgressDescription: String {
        "\(processedFiles)/\(totalFiles) 文件"
    }

    /// 字节进度描述
    var bytesProgressDescription: String {
        let processed = ByteCountFormatter.string(fromByteCount: processedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(processed)/\(total)"
    }

    /// 速度描述
    var speedDescription: String {
        if bytesPerSecond > 0 {
            return ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .file) + "/s"
        }
        return "--"
    }

    /// 剩余时间描述
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

    /// 已用时间描述
    var elapsedTimeDescription: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: elapsedTime) ?? "0s"
    }

    /// 百分比描述
    var percentageDescription: String {
        String(format: "%.1f%%", overallProgress * 100)
    }

    // MARK: - 方法

    /// 重置进度
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

    /// 开始计时
    func start() {
        startTime = Date()
        elapsedTime = 0
    }

    /// 更新已用时间
    func updateElapsedTime() {
        if let start = startTime {
            elapsedTime = Date().timeIntervalSince(start)
        }
    }

    /// 更新当前文件进度
    func updateFileProgress(file: String, bytesTransferred: Int64, totalSize: Int64) {
        currentFile = file
        currentFileSize = totalSize
        currentFileBytesTransferred = bytesTransferred
        currentFileProgress = totalSize > 0 ? Double(bytesTransferred) / Double(totalSize) : 0
    }

    /// 完成一个文件
    func completeFile(bytes: Int64) {
        processedFiles += 1
        processedBytes += bytes
        updateOverallProgress()
        updateSpeed()
    }

    /// 跳过一个文件
    func skipFile() {
        skippedFiles += 1
        processedFiles += 1
        updateOverallProgress()
    }

    /// 文件失败
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

    /// 更新总体进度
    private func updateOverallProgress() {
        guard totalFiles > 0 else { return }

        // 基于当前阶段计算进度权重
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

        // 累积之前阶段的进度
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

    /// 更新传输速度
    private func updateSpeed() {
        guard elapsedTime > 0 else { return }

        bytesPerSecond = Int64(Double(processedBytes) / elapsedTime)

        // 计算预计剩余时间
        let remainingBytes = totalBytes - processedBytes
        if bytesPerSecond > 0 {
            estimatedTimeRemaining = TimeInterval(remainingBytes) / TimeInterval(bytesPerSecond)
        }
    }

    /// 设置阶段
    func setPhase(_ newPhase: SyncPhase) {
        phase = newPhase

        // 根据阶段重置相关进度
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

    /// 转换为可传输的 SyncProgress struct
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
