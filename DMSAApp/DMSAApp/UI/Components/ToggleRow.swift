import SwiftUI

/// A toggle row with title and optional description
struct ToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    let onChange: ((Bool) -> Void)?

    init(
        title: String,
        description: String? = nil,
        isOn: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self.description = description
        self._isOn = isOn
        self.onChange = onChange
    }

    var body: some View {
        SettingRow(title: title, description: description) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn) { newValue in
                    onChange?(newValue)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? L10n.Common.enabled : L10n.Common.disabled)
        .accessibilityHint(description ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

/// A checkbox row with title and optional description
struct CheckboxRow: View {
    let title: String
    let description: String?
    @Binding var isChecked: Bool
    let onChange: ((Bool) -> Void)?

    init(
        title: String,
        description: String? = nil,
        isChecked: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self.description = description
        self._isChecked = isChecked
        self.onChange = onChange
    }

    var body: some View {
        HStack(alignment: description != nil ? .top : .center, spacing: 8) {
            Toggle("", isOn: $isChecked)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .onChange(of: isChecked) { newValue in
                    onChange?(newValue)
                }

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
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            isChecked.toggle()
            onChange?(isChecked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isChecked ? L10n.Common.enabled : L10n.Common.disabled)
        .accessibilityHint(description ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#if DEBUG
struct ToggleRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            ToggleRow(
                title: "Launch at login",
                description: "Start DMSA when you log in",
                isOn: .constant(true)
            )

            ToggleRow(
                title: "Enable notifications",
                isOn: .constant(false)
            )

            Divider()

            CheckboxRow(
                title: "Create symbolic link",
                description: "Local directory points to external disk",
                isChecked: .constant(true)
            )

            CheckboxRow(
                title: "Auto sync when connected",
                isChecked: .constant(false)
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
