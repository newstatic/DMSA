import Foundation
import SwiftUI

// MARK: - Connection State

/// XPC 连接状态
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case interrupted
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .interrupted: return "连接中断"
        case .failed(let msg): return "连接失败: \(msg)"
        }
    }
}

// MARK: - UI State

/// UI 显示状态
enum UIState: Equatable {
    case initializing
    case connecting
    case starting(progress: Double, phase: String)
    case ready
    case syncing(progress: Double, currentFile: String?)
    case evicting(progress: Double)
    case error(AppError)
    case serviceUnavailable

    var icon: String {
        switch self {
        case .initializing, .connecting:
            return "circle.dotted"
        case .starting:
            return "gear"
        case .ready:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .evicting:
            return "trash"
        case .error:
            return "exclamationmark.triangle.fill"
        case .serviceUnavailable:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .initializing, .connecting:
            return .gray
        case .starting:
            return .yellow
        case .ready:
            return .green
        case .syncing, .evicting:
            return .blue
        case .error:
            return .red
        case .serviceUnavailable:
            return .gray
        }
    }
}

// MARK: - App Component State

/// 应用组件状态 (UI 层使用)
/// 注意: 与 ServiceState.swift 中的 ComponentState 枚举不同
struct AppComponentState: Codable, Equatable {
    var name: String
    var status: String
    var lastUpdate: Date
    var errorMessage: String?

    init(name: String, status: String = "unknown", lastUpdate: Date = Date(), errorMessage: String? = nil) {
        self.name = name
        self.status = status
        self.lastUpdate = lastUpdate
        self.errorMessage = errorMessage
    }
}

// MARK: - App Error

/// 应用错误
struct AppError: Error, Equatable, Identifiable {
    let id = UUID()
    var code: Int
    var message: String
    var severity: ErrorSeverity
    var isRecoverable: Bool
    var recoveryAction: String?

    init(code: Int, message: String, severity: ErrorSeverity = .warning, isRecoverable: Bool = true, recoveryAction: String? = nil) {
        self.code = code
        self.message = message
        self.severity = severity
        self.isRecoverable = isRecoverable
        self.recoveryAction = recoveryAction
    }

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message
    }
}

/// 错误严重程度
enum ErrorSeverity: Int, Codable {
    case info = 0
    case warning = 1
    case critical = 2

    var description: String {
        switch self {
        case .info: return "信息"
        case .warning: return "警告"
        case .critical: return "严重"
        }
    }
}

// MARK: - App Statistics

/// 应用统计信息
struct AppStatistics: Equatable {
    var totalFiles: Int = 0
    var totalSize: Int64 = 0
    var localFiles: Int = 0
    var localSize: Int64 = 0
    var dirtyFiles: Int = 0
    var lastSyncTime: Date?
    var lastEvictionTime: Date?
    var syncCount: Int = 0
    var errorCount: Int = 0
    var totalFilesSynced: Int = 0
}

// MARK: - Sync Progress

/// 同步进度
struct SyncProgressInfo: Equatable {
    var syncPairId: String
    var progress: Double
    var phase: String
    var currentFile: String?
    var processedFiles: Int
    var totalFiles: Int
    var processedBytes: Int64
    var totalBytes: Int64
    var speed: Int64
    var startTime: Date?
    var estimatedTimeRemaining: TimeInterval?

    init(
        syncPairId: String = "",
        progress: Double = 0,
        phase: String = "idle",
        currentFile: String? = nil,
        processedFiles: Int = 0,
        totalFiles: Int = 0,
        processedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        speed: Int64 = 0,
        startTime: Date? = nil,
        estimatedTimeRemaining: TimeInterval? = nil
    ) {
        self.syncPairId = syncPairId
        self.progress = progress
        self.phase = phase
        self.currentFile = currentFile
        self.processedFiles = processedFiles
        self.totalFiles = totalFiles
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
        self.speed = speed
        self.startTime = startTime
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}

// MARK: - Eviction Progress

/// 淘汰进度
struct EvictionProgress: Equatable {
    var progress: Double
    var freedBytes: Int64
    var targetBytes: Int64
    var evictedFiles: Int
    var currentFile: String?

    init(progress: Double = 0, freedBytes: Int64 = 0, targetBytes: Int64 = 0, evictedFiles: Int = 0, currentFile: String? = nil) {
        self.progress = progress
        self.freedBytes = freedBytes
        self.targetBytes = targetBytes
        self.evictedFiles = evictedFiles
        self.currentFile = currentFile
    }
}

// MARK: - Index Progress

/// 索引进度
struct IndexProgress: Equatable {
    var syncPairId: String
    var phase: String
    var progress: Double
    var totalFiles: Int
    var processedFiles: Int
    var currentPath: String?

    init(syncPairId: String = "", phase: String = "indexing", progress: Double = 0, totalFiles: Int = 0, processedFiles: Int = 0, currentPath: String? = nil) {
        self.syncPairId = syncPairId
        self.phase = phase
        self.progress = progress
        self.totalFiles = totalFiles
        self.processedFiles = processedFiles
        self.currentPath = currentPath
    }
}

// MARK: - Termination Response

/// 退出确认响应
enum TerminationResponse {
    case cancel
    case waitAndQuit
    case forceQuit
}
