import SwiftUI

/// A picker row with title and optional description
struct PickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let description: String?
    @Binding var selection: SelectionValue
    let content: Content

    init(
        title: String,
        description: String? = nil,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        SettingRow(title: title, description: description) {
            Picker("", selection: $selection) {
                content
            }
            .labelsHidden()
            .frame(width: 180)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description ?? "")
    }
}

/// A segmented picker row
struct SegmentedPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let description: String?
    @Binding var selection: SelectionValue
    let content: Content

    init(
        title: String,
        description: String? = nil,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Picker("", selection: $selection) {
                content
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(description ?? "")
    }
}

/// A radio button group
struct RadioGroup<SelectionValue: Hashable & Identifiable>: View {
    let title: String?
    let options: [SelectionValue]
    @Binding var selection: SelectionValue
    let labelProvider: (SelectionValue) -> String
    let descriptionProvider: ((SelectionValue) -> String?)?

    init(
        title: String? = nil,
        options: [SelectionValue],
        selection: Binding<SelectionValue>,
        label: @escaping (SelectionValue) -> String,
        description: ((SelectionValue) -> String?)? = nil
    ) {
        self.title = title
        self.options = options
        self._selection = selection
        self.labelProvider = label
        self.descriptionProvider = description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            ForEach(options) { option in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selection.id == option.id ? "circle.inset.filled" : "circle")
                        .foregroundColor(selection.id == option.id ? .accentColor : .secondary)
                        .font(.body)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(labelProvider(option))
                            .font(.body)
                            .foregroundColor(.primary)

                        if let description = descriptionProvider?(option) {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = option
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(labelProvider(option))
                .accessibilityAddTraits(selection.id == option.id ? .isSelected : [])
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#if DEBUG
struct PickerRow_Previews: PreviewProvider {
    enum Language: String, CaseIterable {
        case system, en, zhHans

        var displayName: String {
            switch self {
            case .system: return "System Default"
            case .en: return "English"
            case .zhHans: return "简体中文"
            }
        }
    }

    enum SyncDirection: String, CaseIterable, Identifiable {
        case localToExternal, externalToLocal, bidirectional

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .localToExternal: return "Local → External"
            case .externalToLocal: return "External → Local"
            case .bidirectional: return "Bidirectional"
            }
        }

        var description: String {
            switch self {
            case .localToExternal: return "Copy from local to external disk"
            case .externalToLocal: return "Copy from external disk to local"
            case .bidirectional: return "Sync in both directions"
            }
        }
    }

    static var previews: some View {
        VStack(spacing: 24) {
            PickerRow(
                title: "Language",
                description: "Select interface language",
                selection: .constant(Language.system)
            ) {
                ForEach(Language.allCases, id: \.rawValue) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }

            Divider()

            SegmentedPickerRow(
                title: "Sync Direction",
                selection: .constant(SyncDirection.localToExternal)
            ) {
                Text("→").tag(SyncDirection.localToExternal)
                Text("←").tag(SyncDirection.externalToLocal)
                Text("↔").tag(SyncDirection.bidirectional)
            }

            Divider()

            RadioGroup(
                title: "Sync Direction",
                options: SyncDirection.allCases,
                selection: .constant(SyncDirection.localToExternal),
                label: { $0.displayName },
                description: { $0.description }
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
