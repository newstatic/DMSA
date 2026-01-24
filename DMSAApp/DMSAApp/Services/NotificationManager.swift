import Foundation
import UserNotifications
import Cocoa

/// 通知类型
enum NotificationType: String {
    case diskConnected = "disk_connected"
    case diskDisconnected = "disk_disconnected"
    case syncStarted = "sync_started"
    case syncCompleted = "sync_completed"
    case syncFailed = "sync_failed"
    case cacheWarning = "cache_warning"
    case error = "error"
}

/// 通知管理器
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var isAuthorized = false
    private let databaseManager = DatabaseManager.shared

    private override init() {
        super.init()
        center.delegate = self
        requestAuthorization()
    }

    // MARK: - 授权

    private func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            self?.isAuthorized = granted

            if granted {
                Logger.shared.info("通知权限已授权")
            } else if let error = error {
                Logger.shared.error("通知权限请求失败: \(error.localizedDescription)")
            } else {
                Logger.shared.warn("用户拒绝通知权限")
            }
        }
    }

    // MARK: - 发送通知

    func send(
        type: NotificationType,
        title: String,
        body: String,
        userInfo: [String: Any] = [:]
    ) {
        // 将 userInfo 转换为 [String: String]
        var stringUserInfo: [String: String] = [:]
        for (key, value) in userInfo {
            stringUserInfo[key] = String(describing: value)
        }

        // 保存通知记录到数据库
        let actionType = NotificationRecord.determineActionType(type: type.rawValue, userInfo: stringUserInfo)
        let record = NotificationRecord(
            type: type.rawValue,
            title: title,
            body: body,
            userInfo: stringUserInfo,
            actionType: actionType
        )
        databaseManager.saveNotificationRecord(record)

        // 检查配置是否允许此类通知
        guard shouldSendNotification(type: type) else {
            Logger.shared.debug("通知被配置禁用: \(type.rawValue)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = ConfigManager.shared.config.notifications.soundEnabled ? .default : nil
        content.categoryIdentifier = type.rawValue

        var info = userInfo
        info["type"] = type.rawValue
        info["recordId"] = record.id
        content.userInfo = info

        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // 立即发送
        )

        center.add(request) { error in
            if let error = error {
                Logger.shared.error("发送通知失败: \(error.localizedDescription)")
            } else {
                Logger.shared.debug("通知已发送: \(title)")
            }
        }
    }

    private func shouldSendNotification(type: NotificationType) -> Bool {
        let config = ConfigManager.shared.config.notifications

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
            return true // 缓存警告总是显示
        }
    }

    // MARK: - 便捷方法

    func notifyDiskConnected(diskName: String) {
        send(
            type: .diskConnected,
            title: "外置硬盘已连接",
            body: "\(diskName) 已连接，准备同步",
            userInfo: ["diskName": diskName]
        )
    }

    func notifyDiskDisconnected(diskName: String) {
        send(
            type: .diskDisconnected,
            title: "外置硬盘已断开",
            body: "\(diskName) 已安全断开",
            userInfo: ["diskName": diskName]
        )
    }

    func notifySyncStarted(pairName: String) {
        send(
            type: .syncStarted,
            title: "开始同步",
            body: "正在同步 \(pairName)",
            userInfo: ["pairName": pairName]
        )
    }

    func notifySyncCompleted(filesCount: Int, totalSize: Int64, duration: TimeInterval) {
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        let durationStr = String(format: "%.1f", duration)

        send(
            type: .syncCompleted,
            title: "同步完成",
            body: "已同步 \(filesCount) 个文件 (\(sizeStr))，耗时 \(durationStr) 秒",
            userInfo: [
                "filesCount": filesCount,
                "totalSize": totalSize,
                "duration": duration
            ]
        )
    }

    func notifySyncFailed(error: String) {
        send(
            type: .syncFailed,
            title: "同步失败",
            body: error,
            userInfo: ["error": error]
        )
    }

    func notifyCacheWarning(usedSize: Int64, maxSize: Int64) {
        let usedStr = ByteCountFormatter.string(fromByteCount: usedSize, countStyle: .file)
        let maxStr = ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
        let percentage = Int(Double(usedSize) / Double(maxSize) * 100)

        send(
            type: .cacheWarning,
            title: "本地缓存空间不足",
            body: "已使用 \(usedStr) / \(maxStr) (\(percentage)%)，正在清理旧文件",
            userInfo: [
                "usedSize": usedSize,
                "maxSize": maxSize,
                "percentage": percentage
            ]
        )
    }

    func notifyError(title: String, message: String) {
        send(
            type: .error,
            title: title,
            body: message
        )
    }

    // MARK: - 清除通知

    func clearAllNotifications() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    func clearNotifications(ofType type: NotificationType) {
        center.getDeliveredNotifications { [weak self] notifications in
            let idsToRemove = notifications
                .filter { ($0.request.content.userInfo["type"] as? String) == type.rawValue }
                .map { $0.request.identifier }

            self?.center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 应用在前台时也显示通知
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let typeString = userInfo["type"] as? String,
           let type = NotificationType(rawValue: typeString) {
            Logger.shared.info("用户点击通知: \(type.rawValue)")
            handleNotificationAction(type: type, userInfo: userInfo)
        }

        completionHandler()
    }

    private func handleNotificationAction(type: NotificationType, userInfo: [AnyHashable: Any]) {
        switch type {
        case .syncFailed, .error:
            // 打开日志
            let logPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DMSA/app.log")
            NSWorkspace.shared.open(logPath)

        case .cacheWarning:
            // 可以打开设置界面
            break

        default:
            // 打开 Downloads 目录
            let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
            NSWorkspace.shared.open(downloadsPath)
        }
    }
}
