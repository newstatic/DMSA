import SwiftUI

/// Filter rules settings view
struct FilterSettingsView: View {
    @Binding var config: AppConfig

    @State private var selectedPreset: FilterPreset = .default

    enum FilterPreset: String, CaseIterable, Identifiable {
        case `default`
        case developer
        case media
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .default: return L10n.Settings.Filters.presetDefault
            case .developer: return L10n.Settings.Filters.presetDeveloper
            case .media: return L10n.Settings.Filters.presetMedia
            case .custom: return L10n.Settings.Filters.presetCustom
            }
        }

        var description: String {
            switch self {
            case .default: return L10n.Settings.Filters.presetDefaultDesc
            case .developer: return L10n.Settings.Filters.presetDeveloperDesc
            case .media: return L10n.Settings.Filters.presetMediaDesc
            case .custom: return L10n.Settings.Filters.presetCustomDesc
            }
        }

        var patterns: [String] {
            switch self {
            case .default:
                return [
                    ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
                    "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
                    "Thumbs.db", "desktop.ini",
                    "*.part", "*.crdownload", "*.download"
                ]
            case .developer:
                return [
                    ".DS_Store", ".Trash", ".Spotlight-V100", ".fseventsd",
                    "*.tmp", "*.temp", "*.swp", "*.swo", "*~",
                    "Thumbs.db", "desktop.ini",
                    "*.part", "*.crdownload", "*.download",
                    "node_modules", ".git", ".svn", ".hg",
                    "build", "dist", "target", ".build",
                    "*.o", "*.a", "*.so", "*.dylib",
                    "__pycache__", "*.pyc", ".venv", "venv",
                    ".idea", ".vscode", "*.xcworkspace"
                ]
            case .media:
                return [] // Include patterns instead
            case .custom:
                return []
            }
        }
    }

    var body: some View {
        SettingsContentView(title: L10n.Settings.Filters.title) {
            // Presets section
            SectionHeader(title: L10n.Settings.Filters.presets)

            HStack(spacing: 8) {
                Button(L10n.Common.export) {
                    exportFilters()
                }

                Button(L10n.Common.import) {
                    importFilters()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Preset radio buttons
            RadioGroup(
                options: FilterPreset.allCases,
                selection: $selectedPreset,
                label: { $0.title },
                description: { $0.description }
            )
            .onChange(of: selectedPreset) { newValue in
                applyPreset(newValue)
            }

            SectionDivider(title: L10n.Settings.Filters.globalExclude)

            // Global exclude patterns
            PatternListEditor(
                patterns: $config.filters.excludePatterns,
                placeholder: "*.tmp"
            )

            SectionDivider(title: L10n.Settings.Filters.fileSize)

            // Max file size
            HStack {
                CheckboxRow(
                    title: L10n.Settings.Filters.maxSize,
                    isChecked: Binding(
                        get: { config.filters.maxFileSize != nil },
                        set: { enabled in
                            if enabled {
                                config.filters.maxFileSize = 1024 * 1024 * 1024 // 1 GB
                            } else {
                                config.filters.maxFileSize = nil
                            }
                        }
                    )
                )

                if config.filters.maxFileSize != nil {
                    Picker("", selection: Binding(
                        get: { config.filters.maxFileSize ?? 0 },
                        set: { config.filters.maxFileSize = $0 }
                    )) {
                        Text("100 MB").tag(Int64(100 * 1024 * 1024))
                        Text("500 MB").tag(Int64(500 * 1024 * 1024))
                        Text("1 GB").tag(Int64(1024 * 1024 * 1024))
                        Text("5 GB").tag(Int64(5 * 1024 * 1024 * 1024))
                        Text("10 GB").tag(Int64(10 * 1024 * 1024 * 1024))
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Min file size
            HStack {
                CheckboxRow(
                    title: L10n.Settings.Filters.minSize,
                    isChecked: Binding(
                        get: { config.filters.minFileSize != nil },
                        set: { enabled in
                            if enabled {
                                config.filters.minFileSize = 1024 // 1 KB
                            } else {
                                config.filters.minFileSize = nil
                            }
                        }
                    )
                )

                if config.filters.minFileSize != nil {
                    Picker("", selection: Binding(
                        get: { config.filters.minFileSize ?? 0 },
                        set: { config.filters.minFileSize = $0 }
                    )) {
                        Text("0 B").tag(Int64(0))
                        Text("1 KB").tag(Int64(1024))
                        Text("10 KB").tag(Int64(10 * 1024))
                        Text("100 KB").tag(Int64(100 * 1024))
                        Text("1 MB").tag(Int64(1024 * 1024))
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }

            // Hidden files
            CheckboxRow(
                title: L10n.Settings.Filters.excludeHidden,
                isChecked: $config.filters.excludeHidden
            )
        }
        .onAppear {
            detectCurrentPreset()
        }
    }

    private func detectCurrentPreset() {
        // Detect which preset matches current patterns
        if config.filters.excludePatterns == FilterPreset.default.patterns {
            selectedPreset = .default
        } else if config.filters.excludePatterns == FilterPreset.developer.patterns {
            selectedPreset = .developer
        } else if config.filters.excludePatterns.isEmpty && !config.filters.includePatterns.isEmpty {
            selectedPreset = .media
        } else {
            selectedPreset = .custom
        }
    }

    private func applyPreset(_ preset: FilterPreset) {
        switch preset {
        case .default, .developer:
            config.filters.excludePatterns = preset.patterns
            config.filters.includePatterns = ["*"]
        case .media:
            config.filters.excludePatterns = []
            config.filters.includePatterns = [
                "*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.tiff", "*.heic",
                "*.mp4", "*.mov", "*.avi", "*.mkv", "*.wmv", "*.flv",
                "*.mp3", "*.wav", "*.aac", "*.flac", "*.m4a", "*.ogg"
            ]
        case .custom:
            // Don't change patterns
            break
        }
    }

    private func exportFilters() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "dmsa-filters.json"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(config.filters)
                try data.write(to: url)
            } catch {
                // Handle error
            }
        }
    }

    private func importFilters() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                config.filters = try decoder.decode(FilterConfig.self, from: data)
                detectCurrentPreset()
            } catch {
                // Handle error
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct FilterSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FilterSettingsView(config: .constant(AppConfig()))
            .frame(width: 450, height: 600)
    }
}
#endif
