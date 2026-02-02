import Foundation
import AppKit

/// Error handler
/// Handles error classification, auto-recovery attempts, user prompts and guidance
@MainActor
final class ErrorHandler {

    // MARK: - Singleton

    static let shared = ErrorHandler()

    // MARK: - Dependencies

    private let stateManager = StateManager.shared
    private let serviceClient = ServiceClient.shared
    private let logger = Logger.shared

    // MARK: - Retry Configuration

    private var retryCount: [Int: Int] = [:] // [errorCode: retryCount]
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 5] // Incremental delays

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Handle error
    func handle(_ error: AppError) {
        // Log the error
        logError(error)

        // Update state
        stateManager.updateError(error)

        // Handle based on severity
        switch error.severity {
        case .critical:
            handleCriticalError(error)
        case .warning:
            handleWarningError(error)
        case .info:
            // Log only, no display
            break
        }

        // Attempt auto-recovery
        if error.isRecoverable {
            attemptAutoRecovery(error)
        }
    }

    /// Create and handle AppError from ServiceError
    func handle(_ serviceError: ServiceError) {
        let appError = mapServiceError(serviceError)
        handle(appError)
    }

    /// Create and handle AppError from generic Error
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

    /// Clear error state
    func clearError() {
        stateManager.clearError()
        retryCount.removeAll()
    }

    // MARK: - Error Mapping

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
            // Infer specific error type from message content
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

        return 9999 // Unknown error
    }

    // MARK: - Error Handling

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
        // Show critical error alert
        showCriticalErrorAlert(error)
    }

    private func handleWarningError(_ error: AppError) {
        // Show warning notification
        showWarningNotification(error)
    }

    // MARK: - Auto Recovery

    private func attemptAutoRecovery(_ error: AppError) {
        let currentRetry = retryCount[error.code, default: 0]

        guard currentRetry < maxRetries else {
            logger.warning("Max retry count reached (\(maxRetries)), giving up auto-recovery: \(error.code)")
            return
        }

        retryCount[error.code] = currentRetry + 1
        let delay = retryDelays[min(currentRetry, retryDelays.count - 1)]

        logger.info("Attempting auto-recovery (attempt \(currentRetry + 1), delay \(delay)s): \(error.code)")

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await performRecoveryAction(for: error)
        }
    }

    private func performRecoveryAction(for error: AppError) async {
        do {
            switch error.code {
            // Connection error - attempt reconnect
            case ErrorCodes.connectionFailed,
                 ErrorCodes.connectionInterrupted,
                 ErrorCodes.connectionTimeout,
                 ErrorCodes.serviceUnavailable:
                try await reconnect()

            // Sync error - attempt re-sync
            case ErrorCodes.syncFailed,
                 ErrorCodes.syncTimeout:
                try await retrySync()

            // Disk disconnected - wait for reconnection
            case ErrorCodes.diskDisconnected:
                // Disk disconnection handled automatically by DiskManager
                break

            default:
                logger.debug("Error code \(error.code) has no auto-recovery logic")
            }

            // Recovery successful, clear retry count for this error
            retryCount[error.code] = nil
            logger.info("Auto-recovery successful: \(error.code)")

        } catch {
            logger.warning("Auto-recovery failed: \(error)")
        }
    }

    private func reconnect() async throws {
        logger.info("Attempting to reconnect to service...")
        serviceClient.disconnect()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        _ = try await serviceClient.connect()
        stateManager.updateConnectionState(.connected)
        stateManager.clearError()
    }

    private func retrySync() async throws {
        logger.info("Attempting to re-sync...")
        try await serviceClient.syncAll()
    }

    // MARK: - UI Prompts

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
            // User chose recovery action
            Task {
                await performRecoveryAction(for: error)
            }
        }
    }

    private func showWarningNotification(_ error: AppError) {
        // Show warning via system notification
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

// MARK: - Convenience Extensions

extension ErrorHandler {

    /// Convenience: handle connection error
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

    /// Convenience: handle sync error
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

    /// Convenience: handle config error
    func handleConfigError(_ message: String) {
        let error = AppError(
            code: ErrorCodes.configInvalid,
            message: message,
            severity: .warning,
            isRecoverable: false
        )
        handle(error)
    }

    /// Convenience: handle VFS error
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
