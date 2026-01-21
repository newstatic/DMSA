import SwiftUI

/// A section header with title and optional action button
struct SectionHeader: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

/// A divider with optional section title
struct SectionDivider: View {
    let title: String?

    init(title: String? = nil) {
        self.title = title
    }

    var body: some View {
        VStack(spacing: 8) {
            Divider()

            if let title = title {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Previews

#if DEBUG
struct SectionHeader_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "General Settings")

            SectionHeader(
                title: "Configured Disks",
                actionTitle: "Add",
                action: { }
            )

            SectionDivider()

            SectionDivider(title: "Advanced Options")
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
