import Foundation
import AppKit

/// macFUSE manager
/// Handles macFUSE installation detection, version validation, and installation guidance
///
/// Usage:
/// 1. Call checkFUSEAvailability() at startup
/// 2. If not installed, call showInstallationGuide()
/// 3. If version mismatch, call showUpdateGuide()
final class FUSEManager {

    // MARK: - Singleton

    static let shared = FUSEManager()

    // MARK: - Constants

    /// macFUSE Framework path
    private let macFUSEFrameworkPath = "/Library/Frameworks/macFUSE.framework"

    /// macFUSE minimum supported version
    private let minimumVersion = "4.0.0"

    /// Recommended version
    private let recommendedVersion = "5.1.3"

    /// macFUSE download URL
    private let downloadURL = URL(string: "https://macfuse.github.io/")!

    /// macFUSE GitHub Releases
    private let releasesURL = URL(string: "https://github.com/macfuse/macfuse/releases")!

    // MARK: - Status

    /// FUSE availability status
    enum FUSEStatus {
        case available(version: String)
        case notInstalled
        case versionTooOld(installed: String, required: String)
        case frameworkMissing
        case loadError(Error)
    }

    private(set) var currentStatus: FUSEStatus = .notInstalled

    // MARK: - Initialization

    private init() {}

    // MARK: - Detection Methods

    /// Check macFUSE availability
    /// - Returns: Current FUSE status
    @discardableResult
    func checkFUSEAvailability() -> FUSEStatus {
        Logger.shared.info("FUSEManager: Checking macFUSE availability")

        // 1. Check if Framework exists
        let fm = FileManager.default
        guard fm.fileExists(atPath: macFUSEFrameworkPath) else {
            Logger.shared.warning("FUSEManager: macFUSE.framework not found")
            currentStatus = .notInstalled
            return currentStatus
        }

        // 2. Check Framework structure integrity (Objective-C version uses GMUserFileSystem.h)
        let requiredFiles = [
            "\(macFUSEFrameworkPath)/Versions/A/macFUSE",
            "\(macFUSEFrameworkPath)/Headers/GMUserFileSystem.h"
        ]

        for file in requiredFiles {
            if !fm.fileExists(atPath: file) {
                Logger.shared.warning("FUSEManager: Missing required file: \(file)")
                currentStatus = .frameworkMissing
                return currentStatus
            }
        }

        // 3. Read version info
        guard let version = getInstalledVersion() else {
            Logger.shared.warning("FUSEManager: Unable to read macFUSE version")
            currentStatus = .frameworkMissing
            return currentStatus
        }

        // 4. Version comparison
        if compareVersions(version, minimumVersion) < 0 {
            Logger.shared.warning("FUSEManager: macFUSE version too old (\(version) < \(minimumVersion))")
            currentStatus = .versionTooOld(installed: version, required: minimumVersion)
            return currentStatus
        }

        // 5. Check API availability
        if !checkAPIAvailability() {
            Logger.shared.error("FUSEManager: macFUSE API unavailable")
            currentStatus = .frameworkMissing
            return currentStatus
        }

        Logger.shared.info("FUSEManager: macFUSE available (version: \(version))")
        currentStatus = .available(version: version)
        return currentStatus
    }

    /// Get installed macFUSE version
    private func getInstalledVersion() -> String? {
        let infoPlistPath = "\(macFUSEFrameworkPath)/Versions/A/Resources/Info.plist"

        guard let plist = NSDictionary(contentsOfFile: infoPlistPath) else {
            return nil
        }

        return plist["CFBundleShortVersionString"] as? String
            ?? plist["CFBundleVersion"] as? String
    }

    /// Check macFUSE API availability
    private func checkAPIAvailability() -> Bool {
        // Check if GMUserFileSystem class can be loaded
        let bundlePath = "\(macFUSEFrameworkPath)/Versions/A/macFUSE"

        // Try to dynamically load Framework
        guard let bundle = Bundle(path: macFUSEFrameworkPath) else {
            return false
        }

        // Check if already loaded or can be loaded
        if !bundle.isLoaded {
            do {
                try bundle.loadAndReturnError()
            } catch {
                Logger.shared.error("FUSEManager: Failed to load macFUSE: \(error)")
                return false
            }
        }

        // Check if core class exists
        guard NSClassFromString("GMUserFileSystem") != nil else {
            Logger.shared.warning("FUSEManager: GMUserFileSystem class not found")
            return false
        }

        return true
    }

    /// Version comparison
    /// - Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(parts1.count, parts2.count)

        for i in 0..<maxLength {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }

        return 0
    }

    // MARK: - Installation Guide

    /// Show installation guide dialog
    func showInstallationGuide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("fuse.install.title", comment: "")
            alert.informativeText = NSLocalizedString("fuse.install.message", comment: "")
            alert.alertStyle = .warning

            alert.addButton(withTitle: NSLocalizedString("fuse.install.download", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("common.later", comment: ""))

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.downloadURL)
            }
        }
    }

    /// Show update guide dialog
    func showUpdateGuide(installedVersion: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("fuse.update.title", comment: "")
            alert.informativeText = String(
                format: NSLocalizedString("fuse.update.message", comment: ""),
                installedVersion,
                self.recommendedVersion
            )
            alert.alertStyle = .warning

            alert.addButton(withTitle: NSLocalizedString("fuse.update.download", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("common.ignore", comment: ""))

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.releasesURL)
            }
        }
    }

    /// Show Framework missing alert
    func showFrameworkMissingAlert() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = NSLocalizedString("fuse.missing.title", comment: "")
            alert.informativeText = NSLocalizedString("fuse.missing.message", comment: "")
            alert.alertStyle = .critical

            alert.addButton(withTitle: NSLocalizedString("fuse.install.download", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("common.quit", comment: ""))

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(self.downloadURL)
            } else {
                // User chose to quit
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Convenience Methods

    /// Whether FUSE is available
    var isAvailable: Bool {
        if case .available = currentStatus {
            return true
        }
        return false
    }

    /// Get current version (if installed)
    var installedVersion: String? {
        if case .available(let version) = currentStatus {
            return version
        }
        return getInstalledVersion()
    }

    /// Handle startup FUSE check
    /// - Returns: Whether VFS startup can proceed
    func handleStartupCheck() -> Bool {
        let status = checkFUSEAvailability()

        switch status {
        case .available:
            Logger.shared.info("FUSEManager: macFUSE check passed")
            return true

        case .notInstalled:
            Logger.shared.warning("FUSEManager: macFUSE not installed, showing installation guide")
            showInstallationGuide()
            return false

        case .versionTooOld(let installed, _):
            Logger.shared.warning("FUSEManager: macFUSE version too old, showing update guide")
            showUpdateGuide(installedVersion: installed)
            return false

        case .frameworkMissing:
            Logger.shared.error("FUSEManager: macFUSE Framework incomplete")
            showFrameworkMissingAlert()
            return false

        case .loadError(let error):
            Logger.shared.error("FUSEManager: Failed to load macFUSE: \(error)")
            showFrameworkMissingAlert()
            return false
        }
    }
}

// MARK: - Localized String Extension

extension FUSEManager {
    /// Get status description
    var statusDescription: String {
        switch currentStatus {
        case .available(let version):
            return String(format: NSLocalizedString("fuse.status.available", comment: ""), version)
        case .notInstalled:
            return NSLocalizedString("fuse.status.notInstalled", comment: "")
        case .versionTooOld(let installed, let required):
            return String(format: NSLocalizedString("fuse.status.versionTooOld", comment: ""), installed, required)
        case .frameworkMissing:
            return NSLocalizedString("fuse.status.frameworkMissing", comment: "")
        case .loadError:
            return NSLocalizedString("fuse.status.loadError", comment: "")
        }
    }
}
