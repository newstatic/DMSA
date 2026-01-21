import SwiftUI

/// Data recovery wizard view
struct RecoveryWizardView: View {
    let problem: RecoveryProblem
    let onExecute: (RecoveryOption) -> Void
    let onCancel: () -> Void

    @State private var selectedOption: RecoveryOption?

    struct RecoveryProblem {
        let type: ProblemType
        let localPath: String
        let diskName: String
        let backupPath: String?

        enum ProblemType {
            case symlinkDiskMissing
            case dataMismatch
            case corruptedSymlink
        }

        var description: String {
            switch type {
            case .symlinkDiskMissing:
                return L10n.Recovery.symlinkDiskMissing(path: localPath, disk: diskName)
            case .dataMismatch:
                return "Data mismatch detected between local and external storage"
            case .corruptedSymlink:
                return "Symbolic link at \(localPath) is corrupted or invalid"
            }
        }
    }

    enum RecoveryOption: String, CaseIterable, Identifiable {
        case waitForDisk
        case restoreBackup
        case createNew

        var id: String { rawValue }

        var title: String {
            switch self {
            case .waitForDisk: return L10n.Recovery.optionWait
            case .restoreBackup: return L10n.Recovery.optionRestoreBackup
            case .createNew: return L10n.Recovery.optionCreateNew
            }
        }

        func description(for problem: RecoveryProblem) -> String {
            switch self {
            case .waitForDisk:
                return L10n.Recovery.optionWaitDesc
            case .restoreBackup:
                return L10n.Recovery.optionRestoreBackupDesc(problem.backupPath ?? "backup")
            case .createNew:
                return L10n.Recovery.optionCreateNewDesc(problem.localPath)
            }
        }

        var warning: String? {
            switch self {
            case .waitForDisk: return nil
            case .restoreBackup: return L10n.Recovery.optionRestoreBackupWarning
            case .createNew: return L10n.Recovery.optionCreateNewWarning
            }
        }

        var icon: String {
            switch self {
            case .waitForDisk: return "clock"
            case .restoreBackup: return "arrow.counterclockwise"
            case .createNew: return "folder.badge.plus"
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title2)
                    .foregroundColor(.orange)

                Text(L10n.Recovery.title)
                    .font(.headline)

                Spacer()
            }

            Divider()

            // Problem description
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Recovery.description)
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(L10n.Recovery.problem)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(problem.description)
                    .font(.body)
                    .padding(10)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
            }

            Divider()

            // Recovery options
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Recovery.options)
                    .font(.subheadline)
                    .fontWeight(.medium)

                ForEach(RecoveryOption.allCases) { option in
                    RecoveryOptionRow(
                        option: option,
                        problem: problem,
                        isSelected: selectedOption == option,
                        onSelect: { selectedOption = option }
                    )
                }
            }

            Spacer()

            // Actions
            HStack {
                Button(L10n.Common.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.Recovery.execute) {
                    if let option = selectedOption {
                        onExecute(option)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedOption == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 450)
    }
}

/// Recovery option row
private struct RecoveryOptionRow: View {
    let option: RecoveryWizardView.RecoveryOption
    let problem: RecoveryWizardView.RecoveryProblem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Radio button
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .font(.body)

            // Icon
            Image(systemName: option.icon)
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(option.description(for: problem))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let warning = option.warning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(warning)
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Window Controller

class RecoveryWizardController {
    private var window: NSWindow?

    func showWizard(
        problem: RecoveryWizardView.RecoveryProblem,
        onExecute: @escaping (RecoveryWizardView.RecoveryOption) -> Void
    ) {
        let recoveryView = RecoveryWizardView(
            problem: problem,
            onExecute: { [weak self] option in
                onExecute(option)
                self?.closeWindow()
            },
            onCancel: { [weak self] in
                self?.closeWindow()
            }
        )

        let hostingController = NSHostingController(rootView: recoveryView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.Recovery.title
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 500, height: 450))
        newWindow.center()
        newWindow.level = .modalPanel
        newWindow.isReleasedWhenClosed = false

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - Previews

#if DEBUG
struct RecoveryWizard_Previews: PreviewProvider {
    static var previews: some View {
        RecoveryWizardView(
            problem: RecoveryWizardView.RecoveryProblem(
                type: .symlinkDiskMissing,
                localPath: "~/Downloads",
                diskName: "BACKUP",
                backupPath: "~/Local_Downloads"
            ),
            onExecute: { _ in },
            onCancel: { }
        )
    }
}
#endif
