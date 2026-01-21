import SwiftUI

/// An editable list of string patterns (for exclude/include patterns)
struct PatternListEditor: View {
    let title: String?
    @Binding var patterns: [String]
    let placeholder: String
    let onAdd: ((String) -> Void)?
    let onRemove: ((Int) -> Void)?

    @State private var newPattern: String = ""
    @State private var isAdding: Bool = false

    init(
        title: String? = nil,
        patterns: Binding<[String]>,
        placeholder: String = "*.tmp",
        onAdd: ((String) -> Void)? = nil,
        onRemove: ((Int) -> Void)? = nil
    ) {
        self.title = title
        self._patterns = patterns
        self.placeholder = placeholder
        self.onAdd = onAdd
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
            }

            // Pattern list
            VStack(spacing: 0) {
                ForEach(Array(patterns.enumerated()), id: \.offset) { index, pattern in
                    PatternRow(
                        pattern: pattern,
                        onRemove: {
                            removePattern(at: index)
                        }
                    )

                    if index < patterns.count - 1 {
                        Divider()
                    }
                }

                if patterns.isEmpty {
                    Text(L10n.Common.unknown)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
            }
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )

            // Add pattern section
            if isAdding {
                HStack(spacing: 8) {
                    TextField(placeholder, text: $newPattern)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addPattern()
                        }

                    Button(L10n.Common.add) {
                        addPattern()
                    }
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button(L10n.Common.cancel) {
                        cancelAdding()
                    }
                }
            } else {
                Button {
                    isAdding = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(L10n.Settings.Filters.addPattern)
                    }
                }
                .buttonStyle(.link)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Pattern list")
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if !patterns.contains(trimmed) {
            patterns.append(trimmed)
            onAdd?(trimmed)
        }

        newPattern = ""
        isAdding = false
    }

    private func cancelAdding() {
        newPattern = ""
        isAdding = false
    }

    private func removePattern(at index: Int) {
        guard index >= 0 && index < patterns.count else { return }
        patterns.remove(at: index)
        onRemove?(index)
    }
}

/// A single pattern row
private struct PatternRow: View {
    let pattern: String
    let onRemove: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(pattern)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if isHovering {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovering ? Color(.selectedContentBackgroundColor).opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pattern)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-click to remove")
    }
}

/// A compact inline pattern editor
struct InlinePatternEditor: View {
    @Binding var patterns: [String]
    let placeholder: String

    @State private var editText: String = ""

    init(patterns: Binding<[String]>, placeholder: String = "pattern1, pattern2, ...") {
        self._patterns = patterns
        self.placeholder = placeholder
        self._editText = State(initialValue: patterns.wrappedValue.joined(separator: ", "))
    }

    var body: some View {
        TextField(placeholder, text: $editText)
            .textFieldStyle(.roundedBorder)
            .onChange(of: editText) { newValue in
                patterns = newValue
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            .accessibilityLabel("Pattern list")
            .accessibilityHint("Enter patterns separated by commas")
    }
}

// MARK: - Previews

#if DEBUG
struct PatternListEditor_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            PatternListEditor(
                title: "Exclude Patterns",
                patterns: .constant([
                    ".DS_Store",
                    ".git",
                    "node_modules",
                    "*.tmp",
                    "*.log"
                ]),
                placeholder: "Enter pattern..."
            )

            Divider()

            PatternListEditor(
                title: "Empty List",
                patterns: .constant([]),
                placeholder: "*.tmp"
            )

            Divider()

            InlinePatternEditor(
                patterns: .constant(["*.tmp", "*.log"]),
                placeholder: "pattern1, pattern2"
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
