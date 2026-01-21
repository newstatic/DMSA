import SwiftUI

/// Error alert view
struct ErrorAlertView: View {
    let title: String
    let message: String
    let details: String?
    let suggestions: [String]
    let primaryAction: AlertAction?
    let secondaryAction: AlertAction?
    let tertiaryAction: AlertAction?

    struct AlertAction {
        let title: String
        let role: ButtonRole?
        let action: () -> Void

        init(title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.title = title
            self.role = role
            self.action = action
        }
    }

    init(
        title: String,
        message: String,
        details: String? = nil,
        suggestions: [String] = [],
        primaryAction: AlertAction? = nil,
        secondaryAction: AlertAction? = nil,
        tertiaryAction: AlertAction? = nil
    ) {
        self.title = title
        self.message = message
        self.details = details
        self.suggestions = suggestions
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.tertiaryAction = tertiaryAction
    }

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            // Title
            Text(title)
                .font(.headline)

            Divider()

            // Message
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Details
            if let details = details {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Details:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
            }

            // Suggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggestions:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    ForEach(suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(suggestion)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Actions
            HStack(spacing: 12) {
                if let tertiary = tertiaryAction {
                    Button(role: tertiary.role) {
                        tertiary.action()
                    } label: {
                        Text(tertiary.title)
                    }
                }

                Spacer()

                if let secondary = secondaryAction {
                    Button(role: secondary.role) {
                        secondary.action()
                    } label: {
                        Text(secondary.title)
                    }
                }

                if let primary = primaryAction {
                    Button(role: primary.role) {
                        primary.action()
                    } label: {
                        Text(primary.title)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// Sync error view specifically for sync failures
struct SyncErrorView: View {
    let error: SyncErrorInfo
    let onViewLog: () -> Void
    let onIgnore: () -> Void
    let onRetry: () -> Void

    struct SyncErrorInfo {
        let diskName: String
        let sourcePath: String
        let errorMessage: String
        let syncedFiles: Int
        let totalFiles: Int
        let suggestions: [String]
    }

    var body: some View {
        ErrorAlertView(
            title: L10n.Error.syncFailed,
            message: String(format: "Error: %@", error.errorMessage),
            details: "Synced: \(error.syncedFiles) / \(error.totalFiles) files",
            suggestions: error.suggestions,
            primaryAction: .init(title: L10n.Error.reconnectAndRetry, action: onRetry),
            secondaryAction: .init(title: L10n.Common.ignore, action: onIgnore),
            tertiaryAction: .init(title: L10n.Error.viewLog, action: onViewLog)
        )
    }
}

/// Inline error banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    let onAction: (() -> Void)?
    let actionTitle: String?

    init(
        message: String,
        onDismiss: @escaping () -> Void,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.message = message
        self.onDismiss = onDismiss
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            if let actionTitle = actionTitle, let onAction = onAction {
                Button(actionTitle) {
                    onAction()
                }
                .buttonStyle(.link)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Error Window Controller

class ErrorWindowController {
    private var window: NSWindow?

    func showError(
        title: String,
        message: String,
        details: String? = nil,
        suggestions: [String] = [],
        primaryAction: ErrorAlertView.AlertAction? = nil,
        secondaryAction: ErrorAlertView.AlertAction? = nil
    ) {
        let errorView = ErrorAlertView(
            title: title,
            message: message,
            details: details,
            suggestions: suggestions,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        )

        let hostingController = NSHostingController(rootView: errorView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = L10n.Error.title
        newWindow.styleMask = [.titled, .closable]
        newWindow.setContentSize(NSSize(width: 400, height: 350))
        newWindow.center()
        newWindow.level = .modalPanel
        newWindow.isReleasedWhenClosed = true

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

// MARK: - Previews

#if DEBUG
struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ErrorAlertView(
                title: "Sync Failed",
                message: "Disk BACKUP disconnected unexpectedly during sync",
                details: "89 / 156 files synced\n67 files pending",
                suggestions: [
                    "Ensure the disk connection is stable",
                    "Avoid removing the disk during sync",
                    "Use 'Safely Eject' before disconnecting"
                ],
                primaryAction: .init(title: "Reconnect and Retry", action: {}),
                secondaryAction: .init(title: "Ignore", action: {}),
                tertiaryAction: .init(title: "View Log", action: {})
            )

            ErrorBanner(
                message: "Disk BACKUP disconnected unexpectedly",
                onDismiss: {},
                actionTitle: "Reconnect",
                onAction: {}
            )
            .padding(.horizontal)
        }
    }
}
#endif
