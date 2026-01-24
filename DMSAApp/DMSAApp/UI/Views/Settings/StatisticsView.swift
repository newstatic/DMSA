import SwiftUI

/// Statistics/Dashboard view showing sync statistics and history
struct StatisticsView: View {
    @Binding var config: AppConfig
    @State private var selectedTimeRange: TimeRange = .last7Days
    @State private var selectedDiskId: String? = nil
    @State private var statistics: [SyncStatistics] = []
    @State private var recentHistory: [SyncHistory] = []
    @State private var isExporting = false
    @State private var exportFormat: ExportFormat = .csv

    enum TimeRange: String, CaseIterable, Identifiable {
        case today = "today"
        case last7Days = "7days"
        case last30Days = "30days"
        case allTime = "all"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return L10n.Statistics.today
            case .last7Days: return L10n.History.last7Days
            case .last30Days: return L10n.History.last30Days
            case .allTime: return L10n.History.allTime
            }
        }

        var days: Int {
            switch self {
            case .today: return 1
            case .last7Days: return 7
            case .last30Days: return 30
            case .allTime: return 365
            }
        }
    }

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case json = "JSON"

        var id: String { rawValue }
    }

    var body: some View {
        SettingsContentView(title: L10n.Statistics.title) {
            VStack(alignment: .leading, spacing: 24) {
                // Filter controls
                filterSection

                // Summary cards
                summarySection

                // Charts section
                chartsSection

                // Export section
                exportSection
            }
        }
        .onAppear(perform: loadData)
        .onChange(of: selectedTimeRange) { _ in loadData() }
        .onChange(of: selectedDiskId) { _ in loadData() }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        HStack(spacing: 16) {
            Picker(L10n.Statistics.timeRange, selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Picker(L10n.Statistics.disk, selection: $selectedDiskId) {
                Text(L10n.History.allDisks).tag(nil as String?)
                ForEach(config.disks) { disk in
                    Text(disk.name).tag(disk.id as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Spacer()

            Button(action: loadData) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.Statistics.refresh)
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L10n.Statistics.overview)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: L10n.Statistics.totalSyncs,
                    value: "\(totalSyncs)",
                    icon: "arrow.triangle.2.circlepath",
                    color: .blue
                )

                StatCard(
                    title: L10n.Statistics.successRate,
                    value: String(format: "%.1f%%", successRate),
                    icon: "checkmark.circle.fill",
                    color: successRate >= 90 ? .green : (successRate >= 70 ? .orange : .red)
                )

                StatCard(
                    title: L10n.Statistics.totalData,
                    value: totalBytesFormatted,
                    icon: "doc.fill",
                    color: .purple
                )

                StatCard(
                    title: L10n.Statistics.avgSpeed,
                    value: averageSpeedFormatted,
                    icon: "speedometer",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Charts Section

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L10n.Statistics.trends)

            if statistics.isEmpty {
                emptyChartPlaceholder
            } else {
                HStack(spacing: 20) {
                    // Sync frequency chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Statistics.syncFrequency)
                            .font(.headline)

                        SyncFrequencyChart(data: statistics)
                            .frame(height: 150)
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(8)

                    // Data volume chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Statistics.dataVolume)
                            .font(.headline)

                        DataVolumeChart(data: statistics)
                            .frame(height: 150)
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text(L10n.Statistics.noData)
                    .foregroundColor(.secondary)
            }
            .padding(40)
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L10n.Statistics.export)

            HStack(spacing: 16) {
                Picker(L10n.Statistics.exportFormat, selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Button(action: exportData) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(L10n.Statistics.exportData)
                    }
                }
                .disabled(statistics.isEmpty && recentHistory.isEmpty)

                Spacer()
            }
        }
    }

    // MARK: - Computed Properties

    private var totalSyncs: Int {
        statistics.reduce(0) { $0 + $1.totalSyncs }
    }

    private var successfulSyncs: Int {
        statistics.reduce(0) { $0 + $1.successfulSyncs }
    }

    private var successRate: Double {
        guard totalSyncs > 0 else { return 0 }
        return Double(successfulSyncs) / Double(totalSyncs) * 100
    }

    private var totalBytes: Int64 {
        statistics.reduce(0) { $0 + $1.totalBytesTransferred }
    }

    private var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var averageSpeed: Double {
        let totalDuration = statistics.reduce(0.0) { $0 + $1.averageDuration * Double($1.totalSyncs) }
        guard totalDuration > 0 else { return 0 }
        return Double(totalBytes) / totalDuration
    }

    private var averageSpeedFormatted: String {
        let speed = averageSpeed
        if speed < 1024 {
            return String(format: "%.0f B/s", speed)
        } else if speed < 1024 * 1024 {
            return String(format: "%.1f KB/s", speed / 1024)
        } else {
            return String(format: "%.1f MB/s", speed / (1024 * 1024))
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        let db = DatabaseManager.shared

        if let diskId = selectedDiskId {
            statistics = db.getStatistics(forDiskId: diskId, days: selectedTimeRange.days)
        } else {
            // Get statistics for all disks
            var allStats: [SyncStatistics] = []
            for disk in config.disks {
                allStats.append(contentsOf: db.getStatistics(forDiskId: disk.id, days: selectedTimeRange.days))
            }
            statistics = allStats.sorted { $0.date < $1.date }
        }

        recentHistory = db.getSyncHistory(limit: 100)
    }

    // MARK: - Export

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = exportFormat == .csv ? [.commaSeparatedText] : [.json]
        panel.nameFieldStringValue = "sync_statistics.\(exportFormat.rawValue.lowercased())"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data: Data
                if exportFormat == .csv {
                    data = generateCSV()
                } else {
                    data = try generateJSON()
                }
                try data.write(to: url)
                Logger.shared.info("统计数据已导出到: \(url.path)")
            } catch {
                Logger.shared.error("导出失败: \(error.localizedDescription)")
            }
        }
    }

    private func generateCSV() -> Data {
        var csv = "Date,Disk,Total Syncs,Successful,Failed,Files Transferred,Bytes Transferred,Average Duration\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for stat in statistics {
            let line = "\(dateFormatter.string(from: stat.date)),\(stat.diskId),\(stat.totalSyncs),\(stat.successfulSyncs),\(stat.failedSyncs),\(stat.totalFilesTransferred),\(stat.totalBytesTransferred),\(stat.averageDuration)\n"
            csv += line
        }

        return csv.data(using: .utf8) ?? Data()
    }

    private func generateJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportData = StatisticsExport(
            exportDate: Date(),
            timeRange: selectedTimeRange.rawValue,
            statistics: statistics,
            history: recentHistory
        )

        return try encoder.encode(exportData)
    }
}

// MARK: - Supporting Types

struct StatisticsExport: Codable {
    let exportDate: Date
    let timeRange: String
    let statistics: [SyncStatistics]
    let history: [SyncHistory]
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Charts

struct SyncFrequencyChart: View {
    let data: [SyncStatistics]

    private var maxValue: Int {
        max(data.map { $0.totalSyncs }.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, stat in
                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: 2)
                            .fill(stat.failedSyncs > 0 ? Color.orange : Color.blue)
                            .frame(height: CGFloat(stat.totalSyncs) / CGFloat(maxValue) * geometry.size.height * 0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(stat.formattedDate): \(stat.totalSyncs) \(L10n.Statistics.syncs)")
                }
            }
        }
    }
}

struct DataVolumeChart: View {
    let data: [SyncStatistics]

    private var maxValue: Int64 {
        max(data.map { $0.totalBytesTransferred }.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, stat in
                    VStack {
                        Spacer()

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple.opacity(0.8))
                            .frame(height: CGFloat(stat.totalBytesTransferred) / CGFloat(maxValue) * geometry.size.height * 0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(stat.formattedDate): \(stat.formattedBytesTransferred)")
                }
            }
        }
    }
}

// MARK: - Localization Extension

extension L10n {
    enum Statistics {
        static var title: String { "settings.statistics.title".localized }
        static var overview: String { "settings.statistics.overview".localized }
        static var trends: String { "settings.statistics.trends".localized }
        static var export: String { "settings.statistics.export".localized }
        static var timeRange: String { "settings.statistics.timeRange".localized }
        static var disk: String { "settings.statistics.disk".localized }
        static var refresh: String { "settings.statistics.refresh".localized }
        static var totalSyncs: String { "settings.statistics.totalSyncs".localized }
        static var successRate: String { "settings.statistics.successRate".localized }
        static var totalData: String { "settings.statistics.totalData".localized }
        static var avgSpeed: String { "settings.statistics.avgSpeed".localized }
        static var syncFrequency: String { "settings.statistics.syncFrequency".localized }
        static var dataVolume: String { "settings.statistics.dataVolume".localized }
        static var noData: String { "settings.statistics.noData".localized }
        static var exportFormat: String { "settings.statistics.exportFormat".localized }
        static var exportData: String { "settings.statistics.exportData".localized }
        static var today: String { "settings.statistics.today".localized }
        static var syncs: String { "settings.statistics.syncs".localized }
    }
}

// MARK: - Previews

#if DEBUG
struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView(config: .constant(AppConfig()))
            .frame(width: 500, height: 600)
    }
}
#endif
