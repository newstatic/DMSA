import Foundation
import Cocoa
import SwiftUI

/// Alert type
enum AlertType: String {
    case diskConnected = "disk_connected"
    case diskDisconnected = "disk_disconnected"
    case syncStarted = "sync_started"
    case syncCompleted = "sync_completed"
    case syncFailed = "sync_failed"
    case cacheWarning = "cache_warning"
    case error = "error"
    case info = "info"

    var icon: NSImage? {
        switch self {
        case .diskConnected:
            return NSImage(systemSymbolName: "externaldrive.badge.checkmark", accessibilityDescription: nil)
        case .diskDisconnected:
            return NSImage(systemSymbolName: "externaldrive.badge.minus", accessibilityDescription: nil)
        case .syncStarted:
            return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        case .syncCompleted:
            return NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        case .syncFailed, .error:
            return NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        case .cacheWarning:
            return NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)
        case .info:
            return NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: nil)
        }
    }

    var alertStyle: NSAlert.Style {
        switch self {
        case .syncFailed, .error:
            return .critical
        case .cacheWarning:
            return .warning
        default:
            return .informational
        }
    }
}

/// Alert manager - uses in-app dialogs instead of system notifications
/// v4.6: communicates with DMSAService via XPC
@MainActor
final class AlertManager {
    static let shared = AlertManager()

    private var alertQueue: [(type: AlertType, title: String, body: String, userInfo: [String: String])] = []
    private var isShowingAlert = false
    private let queue = DispatchQueue(label: "com.dmsa.alertManager")

    // Cached notification config
    private var cachedNotificationConfig: NotificationConfig?
    private var lastConfigFetch: Date?
    private let configCacheTimeout: TimeInterval = 60 // 1 minute cache

    private init() {}

    // MARK: - Config Cache

    /// Get notification config (with cache)
    private func getNotificationConfig() async -> NotificationConfig {
        // Check if cache is valid
        if let cached = cachedNotificationConfig,
           let lastFetch = lastConfigFetch,
           Date().timeIntervalSince(lastFetch) < configCacheTimeout {
            return cached
        }

        // Fetch config from service
        do {
            let config = try await ServiceClient.shared.getNotificationConfig()
            cachedNotificationConfig = config
            lastConfigFetch = Date()
            return config
        } catch {
            Logger.shared.error("Failed to get notification config: \(error)")
            return cachedNotificationConfig ?? NotificationConfig()
        }
    }

    /// Invalidate config cache
    func invalidateConfigCache() {
        cachedNotificationConfig = nil
        lastConfigFetch = nil
    }

    // MARK: - Send Alert

    func send(
        type: AlertType,
        title: String,
        body: String,
        userInfo: [String: Any] = [:]
    ) {
        // Convert userInfo to [String: String]
        var stringUserInfo: [String: String] = [:]
        for (key, value) in userInfo {
            stringUserInfo[key] = String(describing: value)
        }

        // Save notification record to service (async)
        Task {
            let actionType = NotificationRecord.determineActionType(type: type.rawValue, userInfo: stringUserInfo)
            let record = NotificationRecord(
                type: type.rawValue,
                title: title,
                body: body,
                userInfo: stringUserInfo,
                actionType: actionType
            )
            try? await ServiceClient.shared.saveNotificationRecord(record)
        }

        // Async check config and show alert
        Task {
            let config = await getNotificationConfig()
            guard shouldShowAlert(type: type, config: config) else {
                Logger.shared.debug("Alert disabled by config: \(type.rawValue)")
                return
            }

            // Add to queue and show
            queue.async { [weak self] in
                self?.alertQueue.append((type, title, body, stringUserInfo))
                self?.processQueue()
            }
        }
    }

    private func shouldShowAlert(type: AlertType, config: NotificationConfig) -> Bool {
        guard config.enabled else { return false }

        switch type {
        case .diskConnected:
            return config.showOnDiskConnect
        case .diskDisconnected:
            return config.showOnDiskDisconnect
        case .syncStarted:
            return config.showOnSyncStart
        case .syncCompleted:
            return config.showOnSyncComplete
        case .syncFailed, .error:
            return config.showOnSyncError
        case .cacheWarning:
            return true // Cache warnings always shown
        case .info:
            return true
        }
    }

    private func processQueue() {
        queue.async { [weak self] in
            guard let self = self, !self.isShowingAlert, !self.alertQueue.isEmpty else { return }

            self.isShowingAlert = true
            let item = self.alertQueue.removeFirst()

            DispatchQueue.main.async {
                self.showAlert(type: item.type, title: item.title, body: item.body, userInfo: item.userInfo)
            }
        }
    }

    private func showAlert(type: AlertType, title: String, body: String, userInfo: [String: String]) {
        // Activate app
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = type.alertStyle

        if let icon = type.icon {
            // Tint the icon
            let tintedIcon = icon.copy() as! NSImage
            tintedIcon.isTemplate = true

            // Set color based on type
            let color: NSColor
            switch type {
            case .syncCompleted, .diskConnected:
                color = .systemGreen
            case .syncFailed, .error:
                color = .systemRed
            case .cacheWarning:
                color = .systemOrange
            case .syncStarted:
                color = .systemBlue
            default:
                color = .systemBlue
            }

            // Create tinted icon
            let coloredImage = NSImage(size: tintedIcon.size, flipped: false) { rect in
                tintedIcon.draw(in: rect)
                color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            alert.icon = coloredImage
        }

        alert.addButton(withTitle: "common.ok".localized)

        // Add extra buttons based on type
        switch type {
        case .syncFailed, .error:
            alert.addButton(withTitle: "alert.viewLogs".localized)
        case .syncCompleted:
            alert.addButton(withTitle: "alert.viewHistory".localized)
        default:
            break
        }

        let response = alert.runModal()

        // Handle button response
        if response == .alertSecondButtonReturn {
            handleSecondaryAction(type: type)
        }

        // Done processing, continue queue
        queue.async { [weak self] in
            self?.isShowingAlert = false
            self?.processQueue()
        }
    }

    private func handleSecondaryAction(type: AlertType) {
        switch type {
        case .syncFailed, .error:
            // Open logs
            let logPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DMSA/app.log")
            NSWorkspace.shared.open(logPath)

        case .syncCompleted:
            // Open history
            NotificationCenter.default.post(
                name: .selectMainTab,
                object: nil,
                userInfo: ["tab": MainView.MainTab.logs]
            )

        default:
            break
        }
    }

    // MARK: - Convenience Methods

    func alertDiskConnected(diskName: String) {
        send(
            type: .diskConnected,
            title: "alert.diskConnected.title".localized,
            body: String(format: "alert.diskConnected.body".localized, diskName),
            userInfo: ["diskName": diskName]
        )
    }

    func alertDiskDisconnected(diskName: String) {
        send(
            type: .diskDisconnected,
            title: "alert.diskDisconnected.title".localized,
            body: String(format: "alert.diskDisconnected.body".localized, diskName),
            userInfo: ["diskName": diskName]
        )
    }

    func alertSyncStarted(pairName: String) {
        send(
            type: .syncStarted,
            title: "alert.syncStarted.title".localized,
            body: String(format: "alert.syncStarted.body".localized, pairName),
            userInfo: ["pairName": pairName]
        )
    }

    func alertSyncCompleted(filesCount: Int, totalSize: Int64, duration: TimeInterval) {
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        let durationStr = String(format: "%.1f", duration)

        send(
            type: .syncCompleted,
            title: "alert.syncCompleted.title".localized,
            body: String(format: "alert.syncCompleted.body".localized, filesCount, sizeStr, durationStr),
            userInfo: [
                "filesCount": filesCount,
                "totalSize": totalSize,
                "duration": duration
            ]
        )
    }

    func alertSyncFailed(error: String) {
        send(
            type: .syncFailed,
            title: "alert.syncFailed.title".localized,
            body: error,
            userInfo: ["error": error]
        )
    }

    func alertCacheWarning(usedSize: Int64, maxSize: Int64) {
        let usedStr = ByteCountFormatter.string(fromByteCount: usedSize, countStyle: .file)
        let maxStr = ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
        let percentage = Int(Double(usedSize) / Double(maxSize) * 100)

        send(
            type: .cacheWarning,
            title: "alert.cacheWarning.title".localized,
            body: String(format: "alert.cacheWarning.body".localized, usedStr, maxStr, percentage),
            userInfo: [
                "usedSize": usedSize,
                "maxSize": maxSize,
                "percentage": percentage
            ]
        )
    }

    func alertError(title: String, message: String) {
        send(
            type: .error,
            title: title,
            body: message
        )
    }

    func alertInfo(title: String, message: String) {
        send(
            type: .info,
            title: title,
            body: message
        )
    }
}
