import SwiftUI

/// Cache settings view
struct CacheSettingsView: View {
    @Binding var config: AppConfig

    @State private var cacheUsed: Int64 = 0
    @State private var cacheFileCount: Int = 0
    @State private var showClearConfirmation: Bool = false

    private var cachePath: String {
        let basePath = "~/Library/Application Support/DMSA/LocalCache/"
        return (basePath as NSString).expandingTildeInPath
    }

    var body: some View {
        SettingsContentView(title: L10n.Settings.Cache.title) {
            // Cache location section
            SectionHeader(title: L10n.Settings.Cache.local)

            VStack(alignment: .leading, spacing: 8) {
                SettingRow(title: L10n.Settings.Cache.location) {
                    Button(L10n.Settings.Cache.openFolder) {
                        openCacheFolder()
                    }
                }

                Text(cachePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            SectionDivider(title: L10n.Settings.Cache.currentUsage)

            // Storage bar
            StorageBarSection(
                title: L10n.Settings.Cache.currentUsage,
                description: L10n.Settings.Cache.fileCount(cacheFileCount),
                used: cacheUsed,
                total: config.cache.maxCacheSize
            )

            // Max cache size
            SliderRow(
                title: L10n.Settings.Cache.maxSize,
                value: Binding(
                    get: { Double(config.cache.maxCacheSize) / (1024 * 1024 * 1024) },
                    set: { config.cache.maxCacheSize = Int64($0 * 1024 * 1024 * 1024) }
                ),
                range: 1...100,
                step: 1,
                unit: "GB"
            )

            // Reserve buffer
            SliderRow(
                title: L10n.Settings.Cache.reserveBuffer,
                description: L10n.Settings.Cache.reserveBufferHint,
                value: Binding(
                    get: { Double(config.cache.reserveBuffer) / (1024 * 1024) },
                    set: { config.cache.reserveBuffer = Int64($0 * 1024 * 1024) }
                ),
                range: 100...2000,
                step: 100,
                unit: "MB"
            )

            SectionDivider(title: L10n.Settings.Cache.evictionStrategy)

            // Eviction strategy
            RadioGroup(
                options: CacheConfig.EvictionStrategy.allCases,
                selection: $config.cache.evictionStrategy,
                label: { evictionLabel($0) },
                description: { evictionDescription($0) }
            )

            // Auto eviction
            ToggleRow(
                title: L10n.Settings.Cache.autoEviction,
                isOn: $config.cache.autoEvictionEnabled
            )

            if config.cache.autoEvictionEnabled {
                NumberInputRow(
                    title: L10n.Settings.Cache.checkInterval,
                    value: Binding(
                        get: { config.cache.evictionCheckInterval / 60 },
                        set: { config.cache.evictionCheckInterval = $0 * 60 }
                    ),
                    range: 1...60,
                    unit: "min"
                )
            }

            Divider()
                .padding(.vertical, 8)

            // Clear cache button
            HStack {
                Spacer()

                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Text(L10n.Settings.Cache.clearAll)
                }
                .disabled(cacheUsed == 0)
            }
        }
        .onAppear {
            calculateCacheUsage()
        }
        .alert(L10n.Settings.Cache.clearAll, isPresented: $showClearConfirmation) {
            Button(L10n.Common.cancel, role: .cancel) { }
            Button(L10n.Common.delete, role: .destructive) {
                clearCache()
            }
        } message: {
            Text(L10n.Settings.Cache.clearAllConfirm)
        }
    }

    private func evictionLabel(_ strategy: CacheConfig.EvictionStrategy) -> String {
        switch strategy {
        case .modifiedTime: return L10n.Settings.Cache.evictionModifiedTime
        case .accessTime: return L10n.Settings.Cache.evictionAccessTime
        case .sizeFirst: return L10n.Settings.Cache.evictionSizeFirst
        }
    }

    private func evictionDescription(_ strategy: CacheConfig.EvictionStrategy) -> String? {
        switch strategy {
        case .modifiedTime: return L10n.Settings.Cache.evictionModifiedTimeDesc
        case .accessTime: return L10n.Settings.Cache.evictionAccessTimeDesc
        case .sizeFirst: return L10n.Settings.Cache.evictionSizeFirstDesc
        }
    }

    private func openCacheFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: cachePath))
    }

    private func calculateCacheUsage() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let cacheURL = URL(fileURLWithPath: cachePath)

            var totalSize: Int64 = 0
            var fileCount = 0

            if let enumerator = fileManager.enumerator(
                at: cacheURL,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    do {
                        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                        if resourceValues.isRegularFile == true {
                            totalSize += Int64(resourceValues.fileSize ?? 0)
                            fileCount += 1
                        }
                    } catch {
                        // Skip files we can't access
                    }
                }
            }

            DispatchQueue.main.async {
                self.cacheUsed = totalSize
                self.cacheFileCount = fileCount
            }
        }
    }

    private func clearCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let cacheURL = URL(fileURLWithPath: cachePath)

            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: cacheURL,
                    includingPropertiesForKeys: nil
                )
                for file in contents {
                    try? fileManager.removeItem(at: file)
                }
            } catch {
                // Handle error
            }

            DispatchQueue.main.async {
                calculateCacheUsage()
            }
        }
    }
}

// Make EvictionStrategy conform to Identifiable
extension CacheConfig.EvictionStrategy: Identifiable {
    var id: String { rawValue }
}

// MARK: - Previews

#if DEBUG
struct CacheSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CacheSettingsView(config: .constant(AppConfig()))
            .frame(width: 450, height: 600)
    }
}
#endif
