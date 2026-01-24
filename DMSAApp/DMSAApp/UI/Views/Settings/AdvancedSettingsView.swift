import SwiftUI
import UserNotifications

/// Advanced settings view
struct AdvancedSettingsView: View {
    @Binding var config: AppConfig
    let configManager: ConfigManager

    @State private var showResetConfirmation: Bool = false
    @State private var showClearAllConfirmation: Bool = false

    // 使用 PermissionManager
    @StateObject private var permissionManager = PermissionManager.shared

    private var logPath: String {
        (config.logging.logPath as NSString).expandingTildeInPath
    }

    var body: some View {
        SettingsContentView(title: L10n.Settings.Advanced.title) {
            // Sync behavior section
            SectionHeader(title: L10n.Settings.Advanced.syncBehavior)

            NumberInputRow(
                title: L10n.Settings.Advanced.debounceDelay,
                description: L10n.Settings.Advanced.debounceDelayHint,
                value: $config.monitoring.debounceSeconds,
                range: 1...60,
                unit: "s"
            )

            NumberInputRow(
                title: L10n.Settings.Advanced.batchSize,
                value: $config.monitoring.batchSize,
                range: 10...1000,
                unit: L10n.Settings.Advanced.batchSizeUnit
            )

            SectionDivider(title: L10n.Settings.Advanced.syncOptions)

            // 同步引擎选项
            VStack(alignment: .leading, spacing: 8) {
                // 校验和
                CheckboxRow(
                    title: L10n.Settings.Advanced.enableChecksum,
                    description: L10n.Settings.Advanced.enableChecksumHint,
                    isChecked: $config.syncEngine.enableChecksum
                )

                // 校验算法选择
                if config.syncEngine.enableChecksum {
                    PickerRow(
                        title: L10n.Settings.Advanced.checksumAlgorithm,
                        selection: $config.syncEngine.checksumAlgorithm
                    ) {
                        ForEach(SyncEngineConfig.ChecksumAlgorithm.allCases, id: \.self) { algo in
                            Text(algo.displayName).tag(algo)
                        }
                    }
                    .padding(.leading, 20)
                }

                // 复制后验证
                CheckboxRow(
                    title: L10n.Settings.Advanced.verifyAfterCopy,
                    description: L10n.Settings.Advanced.verifyAfterCopyHint,
                    isChecked: $config.syncEngine.verifyAfterCopy
                )

                // 删除目标多余文件
                CheckboxRow(
                    title: L10n.Settings.Advanced.enableDelete,
                    description: L10n.Settings.Advanced.enableDeleteHint,
                    isChecked: $config.syncEngine.enableDelete
                )

                // 暂停/恢复
                CheckboxRow(
                    title: L10n.Settings.Advanced.enablePauseResume,
                    description: L10n.Settings.Advanced.enablePauseResumeHint,
                    isChecked: $config.syncEngine.enablePauseResume
                )
            }

            SectionDivider(title: L10n.Settings.Advanced.conflictResolution)

            // 冲突解决策略
            VStack(alignment: .leading, spacing: 8) {
                PickerRow(
                    title: L10n.Settings.Advanced.conflictStrategy,
                    selection: $config.syncEngine.conflictStrategy
                ) {
                    ForEach(SyncEngineConfig.SyncConflictStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }

                // 自动解决冲突
                CheckboxRow(
                    title: L10n.Settings.Advanced.autoResolveConflicts,
                    description: L10n.Settings.Advanced.autoResolveConflictsHint,
                    isChecked: $config.syncEngine.autoResolveConflicts
                )

                // 备份后缀
                HStack {
                    Text(L10n.Settings.Advanced.backupSuffix)
                        .frame(width: 120, alignment: .leading)
                    TextField("_backup", text: $config.syncEngine.backupSuffix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }

            SectionDivider(title: L10n.Settings.Advanced.logging)

            // Log level
            PickerRow(
                title: L10n.Settings.Advanced.logLevel,
                selection: $config.logging.level
            ) {
                Text(L10n.Settings.Advanced.logLevelDebug).tag(LoggingConfig.LogLevel.debug)
                Text(L10n.Settings.Advanced.logLevelInfo).tag(LoggingConfig.LogLevel.info)
                Text(L10n.Settings.Advanced.logLevelWarning).tag(LoggingConfig.LogLevel.warn)
                Text(L10n.Settings.Advanced.logLevelError).tag(LoggingConfig.LogLevel.error)
            }

            // Log size
            NumberInputRow(
                title: L10n.Settings.Advanced.logSize,
                value: Binding(
                    get: { config.logging.maxFileSize / (1024 * 1024) },
                    set: { config.logging.maxFileSize = $0 * 1024 * 1024 }
                ),
                range: 1...100,
                unit: "MB"
            )

            // Log file count
            NumberInputRow(
                title: L10n.Settings.Advanced.logCount,
                value: $config.logging.maxFiles,
                range: 1...20,
                unit: nil
            )

            // Open log folder button
            HStack {
                Spacer()

                Button(L10n.Settings.Advanced.openLogFolder) {
                    openLogFolder()
                }
            }

            SectionDivider(title: "settings.advanced.permissions".localized)

            // 权限管理
            permissionsSection

            SectionDivider(title: L10n.Settings.Advanced.data)

            // Export/Import/Reset
            HStack(spacing: 12) {
                Button(L10n.Settings.Advanced.exportConfig) {
                    exportConfig()
                }

                Button(L10n.Settings.Advanced.importConfig) {
                    importConfig()
                }

                Button(L10n.Settings.Advanced.resetAll) {
                    showResetConfirmation = true
                }
            }

            SectionDivider(title: L10n.Settings.Advanced.danger)

            // Danger zone
            VStack(alignment: .leading, spacing: 8) {
                Button(role: .destructive) {
                    showClearAllConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(L10n.Settings.Advanced.clearAllData)
                    }
                }
            }
        }
        .alert(L10n.Settings.Advanced.resetAll, isPresented: $showResetConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Common.reset, role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("This will reset all settings to their default values. This cannot be undone.")
        }
        .alert(L10n.Settings.Advanced.clearAllData, isPresented: $showClearAllConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Common.delete, role: .destructive) {
                clearAllData()
            }
        } message: {
            Text(L10n.Settings.Advanced.clearAllDataConfirm)
        }
        .task {
            await permissionManager.checkAllPermissions()
        }
    }

    // MARK: - 权限管理部分

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 完全磁盘访问权限
            PermissionRow(
                title: "settings.advanced.fullDiskAccess".localized,
                hint: "settings.advanced.fullDiskAccessHint".localized,
                isChecking: permissionManager.isChecking,
                isGranted: permissionManager.hasFullDiskAccess,
                buttonText: permissionManager.authorizeButtonText(for: .fullDiskAccess)
            ) {
                Task {
                    await permissionManager.authorize(.fullDiskAccess)
                }
            }

            Divider()

            // 通知权限
            PermissionRow(
                title: "settings.advanced.notificationPermission".localized,
                hint: "settings.advanced.notificationPermissionHint".localized,
                isChecking: permissionManager.isChecking,
                isGranted: permissionManager.hasNotificationPermission,
                buttonText: permissionManager.authorizeButtonText(for: .notifications)
            ) {
                Task {
                    await permissionManager.authorize(.notifications)
                }
            }

            Divider()

            // 刷新按钮
            HStack {
                Spacer()
                Button {
                    Task {
                        await permissionManager.refreshPermissions()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("settings.advanced.refreshPermissions".localized)
                    }
                }
                .controlSize(.small)
                .disabled(permissionManager.isChecking)
            }
        }
    }

    private func permissionStatusBadge(granted: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(granted ? "wizard.permissions.status.granted".localized : "wizard.permissions.status.notGranted".localized)
                .font(.caption)
                .foregroundColor(granted ? .green : .red)
        }
    }

    private func openLogFolder() {
        let logDir = (logPath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: logDir))
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dmsa-config.json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(config)
                try data.write(to: url)
            } catch {
                // Handle error
            }
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                config = try decoder.decode(AppConfig.self, from: data)
            } catch {
                // Handle error
            }
        }
    }

    private func resetSettings() {
        config = AppConfig()
        configManager.saveConfig()
    }

    private func clearAllData() {
        // Reset config
        config = AppConfig()

        // Clear database
        let dbPath = Constants.Paths.database.path
        try? FileManager.default.removeItem(atPath: dbPath)

        // Clear logs
        let logDir = Constants.Paths.logs.path
        try? FileManager.default.removeItem(atPath: logDir)

        // Note: Downloads_Local is user data, not cleared automatically
        // User should manage ~/Downloads_Local manually if needed

        // Save fresh config
        configManager.saveConfig()
    }
}

// MARK: - Previews

#if DEBUG
struct AdvancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettingsView(
            config: .constant(AppConfig()),
            configManager: ConfigManager.shared
        )
        .frame(width: 450, height: 700)
    }
}
#endif
