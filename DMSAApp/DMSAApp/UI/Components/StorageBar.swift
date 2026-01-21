import SwiftUI

/// A progress bar showing storage usage with color coding
struct StorageBar: View {
    let used: Int64
    let total: Int64
    let showLabels: Bool
    let height: CGFloat

    init(
        used: Int64,
        total: Int64,
        showLabels: Bool = true,
        height: CGFloat = 8
    ) {
        self.used = used
        self.total = total
        self.showLabels = showLabels
        self.height = height
    }

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(used) / Double(total))
    }

    private var percentInt: Int {
        Int(percentage * 100)
    }

    private var barColor: Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.75 {
            return .orange
        } else {
            return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color(.separatorColor))
                        .frame(height: height)

                    // Filled portion
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(barColor)
                        .frame(width: max(0, geometry.size.width * CGFloat(percentage)), height: height)
                        .animation(.easeInOut(duration: 0.3), value: percentage)
                }
            }
            .frame(height: height)

            // Labels
            if showLabels {
                HStack {
                    Text(used.formattedBytes)
                        .font(.caption)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(percentInt)%")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(total.formattedBytes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage usage")
        .accessibilityValue("\(percentInt) percent, \(used.formattedBytes) of \(total.formattedBytes)")
    }
}

/// A storage bar with title and description
struct StorageBarSection: View {
    let title: String
    let description: String?
    let used: Int64
    let total: Int64

    init(
        title: String,
        description: String? = nil,
        used: Int64,
        total: Int64
    ) {
        self.title = title
        self.description = description
        self.used = used
        self.total = total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            StorageBar(used: used, total: total)
        }
        .padding(.vertical, 4)
    }
}

/// A compact storage indicator for menus/lists
struct StorageIndicator: View {
    let used: Int64
    let total: Int64
    let compact: Bool

    init(used: Int64, total: Int64, compact: Bool = false) {
        self.used = used
        self.total = total
        self.compact = compact
    }

    private var percentage: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(used) / Double(total))
    }

    private var percentInt: Int {
        Int(percentage * 100)
    }

    private var indicatorColor: Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.75 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Pie chart indicator
            ZStack {
                Circle()
                    .stroke(Color(.separatorColor), lineWidth: 2)
                    .frame(width: 16, height: 16)

                Circle()
                    .trim(from: 0, to: CGFloat(percentage))
                    .stroke(indicatorColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
            }

            if compact {
                Text("\(percentInt)%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text(L10n.Disk.capacity(used: used.formattedBytes, total: total.formattedBytes, percent: percentInt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Storage: \(percentInt) percent used")
    }
}

// MARK: - Previews

#if DEBUG
struct StorageBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            StorageBar(
                used: 3_200_000_000,
                total: 10_000_000_000
            )

            StorageBar(
                used: 8_500_000_000,
                total: 10_000_000_000
            )

            StorageBar(
                used: 9_500_000_000,
                total: 10_000_000_000
            )

            Divider()

            StorageBarSection(
                title: "Local Cache",
                description: "~/Library/Application Support/DMSA/LocalCache",
                used: 3_200_000_000,
                total: 10_000_000_000
            )

            Divider()

            HStack(spacing: 20) {
                StorageIndicator(used: 450_000_000_000, total: 1_000_000_000_000)
                StorageIndicator(used: 450_000_000_000, total: 1_000_000_000_000, compact: true)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
