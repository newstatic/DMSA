import SwiftUI

// MARK: - Conflict Card Component

/// 冲突文件卡片 - 用于冲突解决页面
struct ConflictCard: View {
    let conflict: ConflictItem
    let onResolve: (ConflictResolution) -> Void
    var onShowMore: (() -> Void)? = nil

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // File info header
            HStack(spacing: 12) {
                FileTypeIcon(fileName: conflict.fileName, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.fileName)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(conflict.relativePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()
            }

            // Version comparison
            HStack(spacing: 16) {
                VersionCard(
                    title: "conflict.local".localized,
                    icon: "laptopcomputer",
                    color: .blue,
                    size: conflict.localSize,
                    modifiedTime: conflict.localModified
                )

                // Arrow
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))

                VersionCard(
                    title: "conflict.external".localized,
                    icon: "externaldrive",
                    color: .orange,
                    size: conflict.externalSize,
                    modifiedTime: conflict.externalModified
                )
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    onResolve(.keepLocal)
                } label: {
                    Text("conflict.keepLocal".localized)
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Button {
                    onResolve(.keepExternal)
                } label: {
                    Text("conflict.keepExternal".localized)
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Button {
                    onResolve(.keepBoth)
                } label: {
                    Text("conflict.keepBoth".localized)
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Spacer()

                // More menu
                Menu {
                    Button {
                        onShowMore?()
                    } label: {
                        Label("conflict.revealLocal".localized, systemImage: "folder")
                    }

                    Button {
                        onShowMore?()
                    } label: {
                        Label("conflict.revealExternal".localized, systemImage: "folder")
                    }

                    Divider()

                    Button {
                        onShowMore?()
                    } label: {
                        Label("conflict.showDiff".localized, systemImage: "doc.text.magnifyingglass")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Version Card Component

/// 版本对比卡片 - 显示本地或外部版本信息
struct VersionCard: View {
    let title: String
    let icon: String
    let color: Color
    let size: Int64
    let modifiedTime: Date

    private var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: modifiedTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 4)

            // Size
            Text(sizeFormatted)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            // Modified time
            Text(timeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.quaternaryLabelColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Conflict Item
// 注意: ConflictResolution 使用 DMSAShared/Models/Sync/ConflictInfo.swift 中的定义

struct ConflictItem: Identifiable {
    let id = UUID()
    let fileName: String
    let relativePath: String
    let localSize: Int64
    let localModified: Date
    let externalSize: Int64
    let externalModified: Date

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }
}

// MARK: - Conflict List Header

/// 冲突列表头部
struct ConflictListHeader: View {
    let conflictCount: Int
    let onResolveAll: (ConflictResolution) -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("conflicts.title".localized)
                    .font(.title)
                    .fontWeight(.bold)

                Text(String(format: "conflicts.subtitle".localized, conflictCount))
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Batch resolve menu
            Menu {
                Button {
                    onResolveAll(.keepLocal)
                } label: {
                    Label("conflicts.resolveAllLocal".localized, systemImage: "laptopcomputer")
                }

                Button {
                    onResolveAll(.keepExternal)
                } label: {
                    Label("conflicts.resolveAllExternal".localized, systemImage: "externaldrive")
                }

                Button {
                    onResolveAll(.keepBoth)
                } label: {
                    Label("conflicts.resolveAllBoth".localized, systemImage: "doc.on.doc")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text("conflicts.resolveAll".localized)
                }
                .font(.subheadline)
            }
            .menuStyle(.borderedButton)
            .disabled(conflictCount == 0)
        }
    }
}

// MARK: - Empty Conflicts View

/// 无冲突状态视图
struct EmptyConflictsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("conflicts.empty.title".localized)
                .font(.title2)
                .fontWeight(.semibold)

            Text("conflicts.empty.message".localized)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }
}

// MARK: - Previews

#if DEBUG
struct ConflictCard_Previews: PreviewProvider {
    static var sampleConflict = ConflictItem(
        fileName: "project_backup.zip",
        relativePath: "Projects/2026/",
        localSize: 125_000_000,
        localModified: Date().addingTimeInterval(-3600),
        externalSize: 128_500_000,
        externalModified: Date().addingTimeInterval(-7200)
    )

    static var previews: some View {
        VStack(spacing: 24) {
            Text("Conflict Card")
                .font(.headline)

            ConflictCard(
                conflict: sampleConflict,
                onResolve: { _ in }
            )
            .frame(width: 500)

            Divider()

            Text("Version Cards")
                .font(.headline)

            HStack(spacing: 16) {
                VersionCard(
                    title: "Local",
                    icon: "laptopcomputer",
                    color: .blue,
                    size: 125_000_000,
                    modifiedTime: Date().addingTimeInterval(-3600)
                )

                VersionCard(
                    title: "External",
                    icon: "externaldrive",
                    color: .orange,
                    size: 128_500_000,
                    modifiedTime: Date().addingTimeInterval(-7200)
                )
            }
            .frame(width: 400)

            Divider()

            Text("Conflict List Header")
                .font(.headline)

            ConflictListHeader(
                conflictCount: 5,
                onResolveAll: { _ in }
            )
            .frame(width: 500)

            Divider()

            Text("Empty State")
                .font(.headline)

            EmptyConflictsView()
                .frame(width: 400, height: 250)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
        }
        .padding()
    }
}
#endif
