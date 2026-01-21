import SwiftUI

/// Model for a single sync task progress
struct SyncTaskProgress: Identifiable {
    let id: String
    let sourcePath: String
    let destinationPath: String
    let diskName: String
    var currentFile: String
    var processedFiles: Int
    var totalFiles: Int
    var processedBytes: Int64
    var totalBytes: Int64
    var status: SyncStatus
    var speed: Int64 // bytes per second
    var startTime: Date

    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }

    var estimatedTimeRemaining: TimeInterval? {
        guard speed > 0 else { return nil }
        let remainingBytes = totalBytes - processedBytes
        return TimeInterval(remainingBytes) / TimeInterval(speed)
    }
}

/// Sync progress window view
struct SyncProgressView: View {
    @Binding var tasks: [SyncTaskProgress]
    let onCancel: (String) -> Void
    let onCancelAll: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(tasks.count > 1 ? L10n.Progress.multiTask(tasks.count) : L10n.Progress.title)
                    .font(.headline)

                Spacer()
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            // Task list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(tasks) { task in
                        SyncTaskCard(
                            task: task,
                            onCancel: { onCancel(task.id) }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Button(L10n.Progress.hideWindow) {
                    onHide()
                }

                Spacer()

                if tasks.count > 1 {
                    Button(role: .destructive) {
                        onCancelAll()
                    } label: {
                        Text(L10n.Progress.cancelAll)
                    }
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .frame(minWidth: 400, minHeight: 150)
    }
}

/// A card showing a single sync task's progress
struct SyncTaskCard: View {
    let task: SyncTaskProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)

                Text("\(task.sourcePath) → \(task.diskName)")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(L10n.Common.cancel) {
                    onCancel()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }

            // Progress bar
            ProgressBar(value: task.progress)

            // Progress details
            HStack {
                // File progress
                Text(L10n.Progress.fileProgress(current: task.processedFiles, total: task.totalFiles))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("|")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Byte progress
                Text(L10n.Progress.byteProgress(
                    current: task.processedBytes.formattedBytes,
                    total: task.totalBytes.formattedBytes
                ))
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                // Speed or status
                if task.status == .inProgress {
                    if task.speed > 0 {
                        Text(L10n.Progress.speed(task.speed.formattedBytes))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(L10n.Progress.waiting)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Current file
            if !task.currentFile.isEmpty && task.status == .inProgress {
                Text(L10n.Progress.currentFile(task.currentFile))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Time remaining
            if let remaining = task.estimatedTimeRemaining, task.status == .inProgress {
                Text(L10n.Progress.timeRemaining(formatTimeInterval(remaining)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return L10n.Time.seconds(Int(interval))
        } else if interval < 3600 {
            return L10n.Time.minutes(Int(interval / 60))
        } else {
            return L10n.Time.hours(Int(interval / 3600))
        }
    }
}

/// A custom progress bar component
struct ProgressBar: View {
    let value: Double
    var height: CGFloat = 8
    var showPercentage: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color(.separatorColor))
                        .frame(height: height)

                    // Foreground
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color.accentColor)
                        .frame(width: max(0, geometry.size.width * CGFloat(value)), height: height)
                        .animation(.easeInOut(duration: 0.2), value: value)
                }
            }
            .frame(height: height)

            if showPercentage {
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// Indeterminate progress bar for unknown duration
struct IndeterminateProgressBar: View {
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.separatorColor))
                .frame(height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * 0.3, height: 8)
                        .offset(x: isAnimating ? geometry.size.width * 0.7 : -geometry.size.width * 0.3)
                        .animation(
                            Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                )
                .clipped()
        }
        .frame(height: 8)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Window Controller

class ProgressWindowController {
    private var window: NSWindow?
    private var tasks: [SyncTaskProgress] = []

    func showWindow(with tasks: [SyncTaskProgress]) {
        self.tasks = tasks

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let progressView = SyncProgressView(
            tasks: Binding(
                get: { self.tasks },
                set: { self.tasks = $0 }
            ),
            onCancel: { taskId in
                // Handle cancel
            },
            onCancelAll: {
                // Handle cancel all
            },
            onHide: { [weak self] in
                self?.hideWindow()
            }
        )

        let hostingController = NSHostingController(rootView: progressView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.Progress.title
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 400, height: 200))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }

    func updateTask(_ task: SyncTaskProgress) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Previews

#if DEBUG
struct SyncProgressView_Previews: PreviewProvider {
    static var sampleTasks: [SyncTaskProgress] = [
        SyncTaskProgress(
            id: "1",
            sourcePath: "~/Downloads",
            destinationPath: "/Volumes/BACKUP/Downloads",
            diskName: "BACKUP",
            currentFile: "project_backup_2026.zip",
            processedFiles: 156,
            totalFiles: 347,
            processedBytes: 1_200_000_000,
            totalBytes: 2_800_000_000,
            status: .inProgress,
            speed: 45_000_000,
            startTime: Date()
        ),
        SyncTaskProgress(
            id: "2",
            sourcePath: "~/Documents",
            destinationPath: "/Volumes/BACKUP/Documents",
            diskName: "BACKUP",
            currentFile: "",
            processedFiles: 45,
            totalFiles: 198,
            processedBytes: 500_000_000,
            totalBytes: 2_100_000_000,
            status: .pending,
            speed: 0,
            startTime: Date()
        )
    ]

    static var previews: some View {
        SyncProgressView(
            tasks: .constant(sampleTasks),
            onCancel: { _ in },
            onCancelAll: { },
            onHide: { }
        )
        .frame(width: 450, height: 300)
    }
}
#endif
