import SwiftUI

/// Advanced settings view
struct AdvancedSettingsView: View {
    @Binding var config: AppConfig
    let configManager: ConfigManager

    @State private var showResetConfirmation: Bool = false
    @State private var showClearAllConfirmation: Bool = false

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

            SectionDivider(title: L10n.Settings.Advanced.rsyncOptions)

            // rsync options
            VStack(alignment: .leading, spacing: 8) {
                CheckboxRow(
                    title: L10n.Settings.Advanced.rsyncArchive,
                    isChecked: .constant(true) // Always on
                )
                .disabled(true)

                CheckboxRow(
                    title: L10n.Settings.Advanced.rsyncDelete,
                    isChecked: .constant(true) // Default behavior
                )

                CheckboxRow(
                    title: L10n.Settings.Advanced.rsyncChecksum,
                    description: L10n.Settings.Advanced.rsyncChecksumHint,
                    isChecked: .constant(false)
                )

                CheckboxRow(
                    title: L10n.Settings.Advanced.rsyncPartial,
                    isChecked: .constant(true)
                )

                CheckboxRow(
                    title: L10n.Settings.Advanced.rsyncCompress,
                    description: L10n.Settings.Advanced.rsyncCompressHint,
                    isChecked: .constant(false)
                )
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

        // Clear cache
        let cachePath = "~/Library/Application Support/DMSA/LocalCache/"
        let expandedPath = (cachePath as NSString).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: expandedPath)

        // Clear database
        let dbPath = "~/Library/Application Support/DMSA/Data/"
        let expandedDbPath = (dbPath as NSString).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: expandedDbPath)

        // Clear logs
        let logDir = (config.logging.logPath as NSString).deletingLastPathComponent
        let expandedLogDir = (logDir as NSString).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: expandedLogDir)

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
