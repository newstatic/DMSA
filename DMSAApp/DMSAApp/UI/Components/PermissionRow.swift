import SwiftUI

/// A reusable permission row component for settings
struct PermissionRow: View {
    let title: String
    let hint: String
    let isChecking: Bool
    let isGranted: Bool
    let buttonText: String
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isChecking {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            } else {
                PermissionStatusBadge(isGranted: isGranted)
            }

            Button(buttonText, action: action)
                .controlSize(.small)
        }
    }
}

/// A badge showing permission status
struct PermissionStatusBadge: View {
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isGranted ? .green : .red)
            Text(isGranted ? "wizard.permissions.status.granted".localized : "wizard.permissions.status.notGranted".localized)
                .font(.caption)
                .foregroundColor(isGranted ? .green : .red)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PermissionRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PermissionRow(
                title: "Full Disk Access",
                hint: "Required for accessing protected directories",
                isChecking: false,
                isGranted: true,
                buttonText: "Re-authorize"
            ) {
                print("Authorize tapped")
            }

            PermissionRow(
                title: "Notifications",
                hint: "Required for sync alerts",
                isChecking: false,
                isGranted: false,
                buttonText: "Authorize"
            ) {
                print("Authorize tapped")
            }

            PermissionRow(
                title: "Checking...",
                hint: "Checking permission status",
                isChecking: true,
                isGranted: false,
                buttonText: "Authorize"
            ) {
                print("Authorize tapped")
            }
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
