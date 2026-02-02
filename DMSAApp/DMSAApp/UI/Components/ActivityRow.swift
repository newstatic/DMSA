import SwiftUI

// MARK: - Activity Row Component

/// 活动记录行 - 用于最近活动列表
struct ActivityRow: View {
    let activity: ActivityItem

    var body: some View {
        HStack(spacing: 12) {
            // Activity icon
            ActivityIcon(type: activity.type)
                .frame(width: 28, height: 28)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(activity.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time
            Text(activity.timeText)
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Activity Icon

struct ActivityIcon: View {
    let type: LegacyActivityType

    var body: some View {
        ZStack {
            Circle()
                .fill(type.color.opacity(0.15))

            Image(systemName: type.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(type.color)
        }
    }
}

// MARK: - Activity Type

enum LegacyActivityType {
    case syncCompleted
    case syncFailed
    case conflictDetected
    case diskConnected
    case diskDisconnected
    case fileUploaded
    case fileDownloaded
    case error

    var icon: String {
        switch self {
        case .syncCompleted: return "checkmark.circle.fill"
        case .syncFailed: return "xmark.circle.fill"
        case .conflictDetected: return "exclamationmark.triangle.fill"
        case .diskConnected: return "externaldrive.badge.plus"
        case .diskDisconnected: return "externaldrive.badge.minus"
        case .fileUploaded: return "arrow.up.circle.fill"
        case .fileDownloaded: return "arrow.down.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .syncCompleted, .fileUploaded, .fileDownloaded:
            return .green
        case .syncFailed, .error:
            return .red
        case .conflictDetected:
            return .orange
        case .diskConnected:
            return .blue
        case .diskDisconnected:
            return .gray
        }
    }
}

// MARK: - Activity Item

struct ActivityItem: Identifiable {
    let id = UUID()
    let type: LegacyActivityType
    let title: String
    let subtitle: String
    let timestamp: Date

    var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Activity List

/// 活动列表组件
struct ActivityList: View {
    let activities: [ActivityItem]
    var maxItems: Int = 5
    var showEmpty: Bool = true

    var body: some View {
        if activities.isEmpty && showEmpty {
            EmptyActivityView()
        } else {
            VStack(spacing: 0) {
                ForEach(activities.prefix(maxItems)) { activity in
                    ActivityRow(activity: activity)

                    if activity.id != activities.prefix(maxItems).last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Empty Activity View

struct EmptyActivityView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("activity.empty".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - File Row Component

/// 文件行 - 用于显示正在处理的文件
struct FileRow: View {
    let fileName: String
    let filePath: String
    let fileSize: Int64?
    var progress: Double? = nil
    var icon: String = "doc"

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            FileTypeIcon(fileName: fileName, size: 40)

            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(filePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            // Size and progress
            VStack(alignment: .trailing, spacing: 4) {
                if let size = fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.callout)
                        .foregroundColor(.primary)
                }

                if let progress = progress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - File Type Icon

/// 文件类型图标
struct FileTypeIcon: View {
    let fileName: String
    var size: CGFloat = 40

    private var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    private var iconName: String {
        switch fileExtension {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic": return "photo.fill"
        case "mp3", "wav", "aac", "flac", "m4a": return "music.note"
        case "mp4", "mov", "avi", "mkv", "wmv": return "film.fill"
        case "txt", "md", "rtf": return "doc.plaintext.fill"
        case "swift", "py", "js", "ts", "java", "c", "cpp", "h": return "chevron.left.forwardslash.chevron.right"
        case "html", "css", "xml", "json": return "globe"
        default: return "doc.fill"
        }
    }

    private var iconColor: Color {
        switch fileExtension {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "ppt", "pptx": return .orange
        case "zip", "rar", "7z", "tar", "gz": return .gray
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic": return .purple
        case "mp3", "wav", "aac", "flac", "m4a": return .pink
        case "mp4", "mov", "avi", "mkv", "wmv": return .indigo
        default: return .secondary
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconColor.opacity(0.15))

            Image(systemName: iconName)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(iconColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Previews

#if DEBUG
struct ActivityRow_Previews: PreviewProvider {
    static var sampleActivities: [ActivityItem] = [
        ActivityItem(type: .syncCompleted, title: "Sync completed", subtitle: "347 files synced to BACKUP", timestamp: Date().addingTimeInterval(-300)),
        ActivityItem(type: .diskConnected, title: "BACKUP connected", subtitle: "External disk mounted", timestamp: Date().addingTimeInterval(-600)),
        ActivityItem(type: .conflictDetected, title: "Conflict detected", subtitle: "project.zip has conflicting versions", timestamp: Date().addingTimeInterval(-1800)),
        ActivityItem(type: .syncFailed, title: "Sync failed", subtitle: "Permission denied: secret.key", timestamp: Date().addingTimeInterval(-3600)),
        ActivityItem(type: .diskDisconnected, title: "PORTABLE disconnected", subtitle: "External disk ejected", timestamp: Date().addingTimeInterval(-7200))
    ]

    static var previews: some View {
        VStack(spacing: 24) {
            Text("Activity List")
                .font(.headline)

            ActivityList(activities: sampleActivities)
                .frame(width: 450)

            Divider()

            Text("Empty State")
                .font(.headline)

            ActivityList(activities: [])
                .frame(width: 450)

            Divider()

            Text("File Row")
                .font(.headline)

            VStack(spacing: 8) {
                FileRow(
                    fileName: "project_backup_2026.zip",
                    filePath: "~/Downloads/Projects/",
                    fileSize: 1_200_000_000,
                    progress: 0.65
                )

                FileRow(
                    fileName: "document.pdf",
                    filePath: "~/Downloads/Documents/",
                    fileSize: 2_500_000
                )

                FileRow(
                    fileName: "photo.jpg",
                    filePath: "~/Downloads/Images/",
                    fileSize: 5_000_000
                )
            }
            .frame(width: 450)

            Divider()

            Text("File Type Icons")
                .font(.headline)

            HStack(spacing: 12) {
                FileTypeIcon(fileName: "doc.pdf")
                FileTypeIcon(fileName: "doc.docx")
                FileTypeIcon(fileName: "doc.xlsx")
                FileTypeIcon(fileName: "doc.zip")
                FileTypeIcon(fileName: "doc.jpg")
                FileTypeIcon(fileName: "doc.mp4")
                FileTypeIcon(fileName: "doc.swift")
            }
        }
        .padding()
    }
}
#endif
