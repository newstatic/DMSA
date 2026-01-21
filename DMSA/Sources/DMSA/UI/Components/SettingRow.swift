import SwiftUI

/// A reusable row component for settings with title, optional description, and trailing content
struct SettingRow<Content: View>: View {
    let title: String
    let description: String?
    let content: Content

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        HStack(alignment: description != nil ? .top : .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            content
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description ?? "")
    }
}

/// A setting row with just a label (no content)
struct SettingLabelRow: View {
    let title: String
    let description: String?
    let value: String

    init(title: String, description: String? = nil, value: String) {
        self.title = title
        self.description = description
        self.value = value
    }

    var body: some View {
        SettingRow(title: title, description: description) {
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Previews

#if DEBUG
struct SettingRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SettingRow(title: "Language", description: "Select interface language") {
                Picker("", selection: .constant("en")) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                .frame(width: 150)
            }

            SettingRow(title: "Enable Feature") {
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
            }

            SettingLabelRow(
                title: "Cache Location",
                value: "~/Library/Caches/DMSA"
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
