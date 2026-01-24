import Foundation
import UserNotifications
import AppKit
import PermissionsKit

/// Permission types managed by the app
/// Note: Maps to both PermissionsKit types and custom types
enum DMSAPermissionType: String, CaseIterable {
    case fullDiskAccess = "fullDiskAccess"
    case notifications = "notifications"
    case accessibility = "accessibility"
}

/// Permission status
enum DMSAPermissionStatus: String {
    case granted = "granted"
    case denied = "denied"
    case notDetermined = "notDetermined"
    case unknown = "unknown"
}

/// Permission manager for handling macOS system permissions
/// Uses MacPaw/PermissionsKit for Full Disk Access detection
@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    /// Published permission states
    @Published private(set) var fullDiskAccessStatus: DMSAPermissionStatus = .unknown
    @Published private(set) var notificationStatus: DMSAPermissionStatus = .unknown
    @Published private(set) var isChecking: Bool = false

    /// Convenience computed properties
    var hasFullDiskAccess: Bool {
        fullDiskAccessStatus == .granted
    }

    var hasNotificationPermission: Bool {
        notificationStatus == .granted
    }

    /// All permissions granted
    var allPermissionsGranted: Bool {
        hasFullDiskAccess && hasNotificationPermission
    }

    private init() {}

    // MARK: - Public Methods

    /// Check all permissions and update status
    func checkAllPermissions() async {
        isChecking = true
        defer { isChecking = false }

        // Check Full Disk Access using PermissionsKit
        fullDiskAccessStatus = checkFullDiskAccess()

        // Check Notification Permission
        notificationStatus = await checkNotificationPermission()

        Logger.shared.debug("权限状态 - FDA: \(fullDiskAccessStatus.rawValue), 通知: \(notificationStatus.rawValue)")
    }

    /// Refresh permissions (same as checkAllPermissions but with explicit logging)
    func refreshPermissions() async {
        Logger.shared.info("刷新权限状态...")
        await checkAllPermissions()
    }

    // MARK: - Full Disk Access (using PermissionsKit)

    /// Check Full Disk Access permission using PermissionsKit
    private func checkFullDiskAccess() -> DMSAPermissionStatus {
        let status = PermissionsKit.authorizationStatus(for: .fullDiskAccess)

        switch status {
        case .authorized:
            Logger.shared.debug("FDA 检测成功 (PermissionsKit)")
            return .granted
        case .denied:
            Logger.shared.debug("FDA 检测失败 - 已拒绝")
            return .denied
        case .notDetermined:
            Logger.shared.debug("FDA 检测 - 未确定")
            return .notDetermined
        case .limited:
            Logger.shared.debug("FDA 检测 - 受限")
            return .granted  // Limited is effectively granted for our purposes
        @unknown default:
            Logger.shared.debug("FDA 检测 - 未知状态")
            return .unknown
        }
    }

    /// Open System Settings to Full Disk Access panel using PermissionsKit
    func openFullDiskAccessSettings() {
        // Use PermissionsKit to open the settings
        // This automatically opens to the correct Privacy panel
        PermissionsKit.requestAuthorization(for: .fullDiskAccess) { _ in
            // Note: completion won't be called for fullDiskAccess
            // because macOS doesn't provide a callback for this permission
        }

        Logger.shared.info("打开系统设置 - 完全磁盘访问权限")
    }

    // MARK: - Notification Permission

    /// Check notification permission
    private func checkNotificationPermission() async -> DMSAPermissionStatus {
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status: DMSAPermissionStatus
                switch settings.authorizationStatus {
                case .authorized:
                    status = .granted
                case .denied:
                    status = .denied
                case .notDetermined:
                    status = .notDetermined
                case .provisional:
                    status = .granted  // Provisional is effectively granted
                case .ephemeral:
                    status = .granted  // Ephemeral is effectively granted
                @unknown default:
                    status = .unknown
                }
                continuation.resume(returning: status)
            }
        }
    }

    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )

            if granted {
                notificationStatus = .granted
                Logger.shared.info("通知权限已授权")
            } else {
                notificationStatus = .denied
                Logger.shared.warn("通知权限被拒绝")
            }

            return granted
        } catch {
            Logger.shared.error("请求通知权限失败: \(error.localizedDescription)")
            notificationStatus = .denied
            return false
        }
    }

    /// Open notification settings
    func openNotificationSettings() {
        // If permission was denied, need to go to system settings
        if notificationStatus == .denied {
            if #available(macOS 13.0, *) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
            Logger.shared.info("打开系统设置 - 通知")
        } else {
            // If not determined, request permission directly
            Task {
                _ = await requestNotificationPermission()
            }
        }
    }

    // MARK: - Accessibility Permission (not available in PermissionsKit, use native API)

    /// Check accessibility permission using native API
    func checkAccessibilityPermission() -> DMSAPermissionStatus {
        let trusted = AXIsProcessTrusted()
        return trusted ? .granted : .denied
    }

    /// Request accessibility permission with prompt
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open accessibility settings
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        Logger.shared.info("打开系统设置 - 辅助功能")
    }

    // MARK: - Utility Methods

    /// Get localized status text for a permission type
    func statusText(for type: DMSAPermissionType) -> String {
        let status: DMSAPermissionStatus
        switch type {
        case .fullDiskAccess:
            status = fullDiskAccessStatus
        case .notifications:
            status = notificationStatus
        case .accessibility:
            status = checkAccessibilityPermission()
        }

        switch status {
        case .granted:
            return "wizard.permissions.status.granted".localized
        case .denied, .notDetermined:
            return "wizard.permissions.status.notGranted".localized
        case .unknown:
            return "common.unknown".localized
        }
    }

    /// Get authorization button text for a permission type
    func authorizeButtonText(for type: DMSAPermissionType) -> String {
        let status: DMSAPermissionStatus
        switch type {
        case .fullDiskAccess:
            status = fullDiskAccessStatus
        case .notifications:
            status = notificationStatus
        case .accessibility:
            status = checkAccessibilityPermission()
        }

        switch status {
        case .granted:
            return "settings.advanced.reauthorize".localized
        default:
            return "settings.advanced.authorize".localized
        }
    }

    /// Handle authorization action for a permission type
    func authorize(_ type: DMSAPermissionType) async {
        switch type {
        case .fullDiskAccess:
            openFullDiskAccessSettings()
        case .notifications:
            if notificationStatus == .notDetermined {
                _ = await requestNotificationPermission()
            } else {
                openNotificationSettings()
            }
        case .accessibility:
            _ = requestAccessibilityPermission()
        }
    }
}

// MARK: - Type Aliases for backwards compatibility

typealias PermissionType = DMSAPermissionType
typealias PermissionStatus = DMSAPermissionStatus
