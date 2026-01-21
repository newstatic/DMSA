import SwiftUI

/// A card component showing disk information
struct DiskCard: View {
    let name: String
    let mountPath: String
    let isConnected: Bool
    let fileSystem: String?
    let usedSpace: Int64?
    let totalSpace: Int64?
    let isSelected: Bool
    let onSelect: () -> Void

    init(
        name: String,
        mountPath: String,
        isConnected: Bool,
        fileSystem: String? = nil,
        usedSpace: Int64? = nil,
        totalSpace: Int64? = nil,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {}
    ) {
        self.name = name
        self.mountPath = mountPath
        self.isConnected = isConnected
        self.fileSystem = fileSystem
        self.usedSpace = usedSpace
        self.totalSpace = totalSpace
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    /// Initialize from a DiskConfig
    init(
        disk: DiskConfig,
        usedSpace: Int64? = nil,
        totalSpace: Int64? = nil,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {}
    ) {
        self.name = disk.name
        self.mountPath = disk.mountPath
        self.isConnected = disk.isConnected
        self.fileSystem = disk.fileSystem
        self.usedSpace = usedSpace
        self.totalSpace = totalSpace
        self.isSelected = isSelected
        self.onSelect = onSelect
    }

    private var statusColor: Color {
        isConnected ? .green : .gray
    }

    private var usagePercentage: Int? {
        guard let used = usedSpace, let total = totalSpace, total > 0 else {
            return nil
        }
        return Int(Double(used) / Double(total) * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Disk icon
            Image(systemName: "externaldrive.fill")
                .font(.title2)
                .foregroundColor(statusColor)
                .frame(width: 32)

            // Disk info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    // Status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(isConnected ? L10n.Disk.connected : L10n.Disk.disconnected)
                            .font(.caption)
                            .foregroundColor(statusColor)
                    }
                }

                Text(mountPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Capacity info
                if isConnected, let used = usedSpace, let total = totalSpace, let percent = usagePercentage {
                    HStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(.separatorColor))
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(capacityColor(for: percent))
                                    .frame(width: geometry.size.width * CGFloat(percent) / 100, height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text(L10n.Disk.capacity(used: used.formattedBytes, total: total.formattedBytes, percent: percent))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                    .padding(.top, 2)
                }

                // File system info
                if let fs = fileSystem, fs != "auto" {
                    Text(L10n.Disk.format(fs))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isConnected ? L10n.Disk.connected : L10n.Disk.disconnected)")
        .accessibilityHint(mountPath)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func capacityColor(for percent: Int) -> Color {
        if percent > 90 {
            return .red
        } else if percent > 75 {
            return .orange
        } else {
            return .accentColor
        }
    }
}

/// A compact disk status indicator for menus
struct DiskStatusBadge: View {
    let name: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.body)

            Spacer()

            Text(isConnected ? L10n.Disk.connected : L10n.Disk.disconnected)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isConnected ? L10n.Disk.connected : L10n.Disk.disconnected)")
    }
}

// MARK: - Previews

#if DEBUG
struct DiskCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            DiskCard(
                name: "BACKUP",
                mountPath: "/Volumes/BACKUP",
                isConnected: true,
                fileSystem: "APFS",
                usedSpace: 450_000_000_000,
                totalSpace: 1_000_000_000_000,
                isSelected: true
            )

            DiskCard(
                name: "PORTABLE",
                mountPath: "/Volumes/PORTABLE",
                isConnected: false,
                fileSystem: "exFAT",
                isSelected: false
            )

            Divider()

            DiskStatusBadge(name: "BACKUP", isConnected: true)
            DiskStatusBadge(name: "PORTABLE", isConnected: false)
        }
        .padding()
        .frame(width: 350)
    }
}
#endif
