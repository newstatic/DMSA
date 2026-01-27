import Foundation
import AppKit

/// 错误处理器
/// 负责错误分类、自动恢复尝试、用户提示与引导
@MainActor
final class ErrorHandler {

    // MARK: - Singleton

    static let shared = ErrorHandler()

    // MARK: - 依赖

    private let stateManager = StateManager.shared
    private let serviceClient = ServiceClient.shared
    private let logger = Logger.shared

    // MARK: - 重试配置

    private var retryCount: [Int: Int] = [:] // [errorCode: retryCount]
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 5] // 递增延迟

    // MARK: - 初始化

    private init() {}

    // MARK: - 公共方法

    /// 处理错误
    func handle(_ error: AppError) {
        // 记录日志
        logError(error)

        // 更新状态
        stateManager.updateError(error)

        // 根据严重程度处理
        switch error.severity {
        case .critical:
            handleCriticalError(error)
        case .warning:
            handleWarningError(error)
        case .info:
            // 仅记录，不显示
            break
        }

        // 尝试自动恢复
        if error.isRecoverable {
            attemptAutoRecovery(error)
        }
    }

    /// 从 ServiceError 创建并处理 AppError
    func handle(_ serviceError: ServiceError) {
        let appError = mapServiceError(serviceError)
        handle(appError)
    }

    /// 从通用 Error 创建并处理 AppError
    func handle(_ error: Error, context: String? = nil) {
        if let serviceError = error as? ServiceError {
            handle(serviceError)
        } else if let appError = error as? AppError {
            handle(appError)
        } else {
            let appError = AppError(
                code: 9999,
                message: context.map { "[\($0)] \(error.localizedDescription)" } ?? error.localizedDescription,
                severity: .warning,
                isRecoverable: false
            )
            handle(appError)
        }
    }

    /// 清除错误状态
    func clearError() {
        stateManager.clearError()
        retryCount.removeAll()
    }

    // MARK: - 错误映射

    private func mapServiceError(_ error: ServiceError) -> AppError {
        switch error {
        case .connectionFailed(let message):
            return AppError(
                code: ErrorCodes.connectionFailed,
                message: message,
                severity: .critical,
                isRecoverable: true,
                recoveryAction: "recovery.reconnect".localized
            )

        case .operationFailed(let message):
            // 根据消息内容判断具体错误类型
            let code = inferErrorCode(from: message)
            return AppError(
                code: code,
                message: message,
                severity: ErrorCodes.isCritical(code) ? .critical : .warning,
                isRecoverable: ErrorCodes.isRecoverable(code)
            )

        case .timeout:
            return AppError(
                code: ErrorCodes.connectionTimeout,
                message: ErrorCodes.defaultMessage(for: ErrorCodes.connectionTimeout),
                severity: .warning,
                isRecoverable: true,
                recoveryAction: "recovery.retry".localized
            )

        case .notConnected:
            return AppError(
                code: ErrorCodes.serviceUnavailable,
                message: ErrorCodes.defaultMessage(for: ErrorCodes.serviceUnavailable),
                severity: .critical,
                isRecoverable: true,
                recoveryAction: "recovery.reconnect".localized
            )
        }
    }

    private func inferErrorCode(from message: String) -> Int {
        let lowercased = message.lowercased()

        if lowercased.contains("mount") || lowercased.contains("挂载") {
            return ErrorCodes.vfsMountFailed
        } else if lowercased.contains("unmount") || lowercased.contains("卸载") {
            return ErrorCodes.vfsUnmountFailed
        } else if lowercased.contains("sync") || lowercased.contains("同步") {
            return ErrorCodes.syncFailed
        } else if lowercased.contains("config") || lowercased.contains("配置") {
            return ErrorCodes.configInvalid
        } else if lowercased.contains("disk") || lowercased.contains("磁盘") {
            return ErrorCodes.diskNotFound
        } else if lowercased.contains("permission") || lowercased.contains("权限") {
            return ErrorCodes.permissionDenied
        }

        return 9999 // 未知错误
    }

    // MARK: - 错误处理

    private func logError(_ error: AppError) {
        let module = ErrorCodes.module(for: error.code)
        let severityStr: String
        switch error.severity {
        case .critical: severityStr = "CRITICAL"
        case .warning: severityStr = "WARNING"
        case .info: severityStr = "INFO"
        }

        logger.error("[\(severityStr)][\(module)] Error \(error.code): \(error.message)")
    }

    private func handleCriticalError(_ error: AppError) {
        // 显示严重错误弹窗
        showCriticalErrorAlert(error)
    }

    private func handleWarningError(_ error: AppError) {
        // 显示警告通知
        showWarningNotification(error)
    }

    // MARK: - 自动恢复

    private func attemptAutoRecovery(_ error: AppError) {
        let currentRetry = retryCount[error.code, default: 0]

        guard currentRetry < maxRetries else {
            logger.warning("已达到最大重试次数 (\(maxRetries))，放弃自动恢复: \(error.code)")
            return
        }

        retryCount[error.code] = currentRetry + 1
        let delay = retryDelays[min(currentRetry, retryDelays.count - 1)]

        logger.info("尝试自动恢复 (第 \(currentRetry + 1) 次，延迟 \(delay) 秒): \(error.code)")

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await performRecoveryAction(for: error)
        }
    }

    private func performRecoveryAction(for error: AppError) async {
        do {
            switch error.code {
            // 连接错误 - 尝试重连
            case ErrorCodes.connectionFailed,
                 ErrorCodes.connectionInterrupted,
                 ErrorCodes.connectionTimeout,
                 ErrorCodes.serviceUnavailable:
                try await reconnect()

            // 同步错误 - 尝试重新同步
            case ErrorCodes.syncFailed,
                 ErrorCodes.syncTimeout:
                try await retrySync()

            // 磁盘断开 - 等待重新连接
            case ErrorCodes.diskDisconnected:
                // 磁盘断开由 DiskManager 自动处理
                break

            default:
                logger.debug("错误码 \(error.code) 没有自动恢复逻辑")
            }

            // 恢复成功，清除该错误的重试计数
            retryCount[error.code] = nil
            logger.info("自动恢复成功: \(error.code)")

        } catch {
            logger.warning("自动恢复失败: \(error)")
        }
    }

    private func reconnect() async throws {
        logger.info("尝试重新连接到服务...")
        serviceClient.disconnect()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        _ = try await serviceClient.connect()
        stateManager.updateConnectionState(.connected)
        stateManager.clearError()
    }

    private func retrySync() async throws {
        logger.info("尝试重新同步...")
        try await serviceClient.syncAll()
    }

    // MARK: - UI 提示

    private func showCriticalErrorAlert(_ error: AppError) {
        let alert = NSAlert()
        alert.messageText = "error.critical.title".localized
        alert.informativeText = error.message
        alert.alertStyle = .critical

        if let recoveryAction = error.recoveryAction {
            alert.addButton(withTitle: recoveryAction)
            alert.addButton(withTitle: "alert.dismiss".localized)
        } else {
            alert.addButton(withTitle: "alert.ok".localized)
        }

        let response = alert.runModal()

        if response == .alertFirstButtonReturn, error.recoveryAction != nil {
            // 用户选择了恢复操作
            Task {
                await performRecoveryAction(for: error)
            }
        }
    }

    private func showWarningNotification(_ error: AppError) {
        // 使用系统通知显示警告
        let content = UNMutableNotificationContent()
        content.title = "warning".localized
        content.body = error.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "error-\(error.code)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 便捷扩展

extension ErrorHandler {

    /// 快捷方法：处理连接错误
    func handleConnectionError(_ message: String) {
        let error = AppError(
            code: ErrorCodes.connectionFailed,
            message: message,
            severity: .critical,
            isRecoverable: true,
            recoveryAction: "recovery.reconnect".localized
        )
        handle(error)
    }

    /// 快捷方法：处理同步错误
    func handleSyncError(_ message: String, syncPairId: String? = nil) {
        let fullMessage = syncPairId.map { "[\($0)] \(message)" } ?? message
        let error = AppError(
            code: ErrorCodes.syncFailed,
            message: fullMessage,
            severity: .warning,
            isRecoverable: true
        )
        handle(error)
    }

    /// 快捷方法：处理配置错误
    func handleConfigError(_ message: String) {
        let error = AppError(
            code: ErrorCodes.configInvalid,
            message: message,
            severity: .warning,
            isRecoverable: false
        )
        handle(error)
    }

    /// 快捷方法：处理 VFS 错误
    func handleVFSError(_ message: String) {
        let error = AppError(
            code: ErrorCodes.vfsMountFailed,
            message: message,
            severity: .critical,
            isRecoverable: false
        )
        handle(error)
    }
}

// MARK: - UNUserNotificationCenter Import

import UserNotifications
