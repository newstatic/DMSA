import SwiftUI

// MARK: - Stat Card Component

/// Stat card - used to display numerical statistics
struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    var subtitle: String? = nil
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with icon
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)

                Spacer()
            }

            Spacer()

            // Value
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Label
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(minWidth: 120, maxWidth: .infinity)
        .frame(height: 100)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Stat Card Grid

/// Stat card grid
struct StatCardGrid: View {
    let cards: [StatCardItem]
    var columns: Int = 4

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(cards) { card in
                StatCard(
                    icon: card.icon,
                    label: card.label,
                    value: card.value,
                    subtitle: card.subtitle,
                    color: card.color
                )
            }
        }
    }
}

/// Stat card data model
struct StatCardItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    var subtitle: String? = nil
    var color: Color = .accentColor
}

// MARK: - Stat Chip Component

/// Small stat chip - used for statistics in the status banner
struct StatChip: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Storage Card Component

/// Storage card - displays storage space usage
struct StorageCard: View {
    let title: String
    let icon: String
    let used: Int64
    let total: Int64
    var color: Color = .blue

    private var usedPercent: Int {
        guard total > 0 else { return 0 }
        return Int(Double(used) / Double(total) * 100)
    }

    private var usedFormatted: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }

    private var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(color)

                Spacer()

                Text("\(usedPercent)%")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(min(Double(usedPercent) / 100, 1.0)))
                }
            }
            .frame(height: 8)

            // Labels
            HStack {
                Text("\(usedFormatted) / \(totalFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var progressColor: Color {
        if usedPercent >= 90 {
            return .red
        } else if usedPercent >= 75 {
            return .orange
        } else {
            return color
        }
    }
}

// MARK: - Info Row Component

/// Info row - used to display key-value pair information
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Info Grid Component

/// Info grid - used to display multiple key-value pairs
struct InfoGrid: View {
    let items: [(label: String, value: String)]
    var columns: Int = 2

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
            ForEach(items.indices, id: \.self) { index in
                InfoRow(label: items[index].label, value: items[index].value)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
struct StatCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            Text("Stat Cards")
                .font(.headline)

            StatCardGrid(cards: [
                StatCardItem(icon: "doc.fill", label: "Processed", value: "156", subtitle: "/ 347", color: .blue),
                StatCardItem(icon: "arrow.up.arrow.down", label: "Transferred", value: "1.2 GB", color: .green),
                StatCardItem(icon: "speedometer", label: "Speed", value: "45 MB/s", color: .orange),
                StatCardItem(icon: "clock", label: "Remaining", value: "2:35", color: .purple)
            ])
            .frame(width: 550)

            Divider()

            Text("Stat Chips")
                .font(.headline)

            HStack(spacing: 16) {
                StatChip(icon: "doc", value: "1,234", label: "files")
                StatChip(icon: "externaldrive", value: "2/3", label: "disks")
                StatChip(icon: "clock", value: "5m", label: "ago")
            }

            Divider()

            Text("Storage Cards")
                .font(.headline)

            HStack(spacing: 16) {
                StorageCard(
                    title: "Local Cache",
                    icon: "internaldrive",
                    used: 3_200_000_000,
                    total: 10_000_000_000,
                    color: .blue
                )

                StorageCard(
                    title: "External Disk",
                    icon: "externaldrive",
                    used: 850_000_000_000,
                    total: 1_000_000_000_000,
                    color: .green
                )
            }
            .frame(width: 450)

            Divider()

            Text("Info Grid")
                .font(.headline)

            InfoGrid(items: [
                ("Sync Directory", "/Downloads"),
                ("Target Directory", "~/Downloads"),
                ("File Count", "1,234"),
                ("Total Size", "45.6 GB"),
                ("Last Sync", "5 min ago"),
                ("Disk Format", "APFS")
            ])
            .frame(width: 400)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .padding()
    }
}
#endif
