import SwiftUI

/// A slider row with title, value display, and optional description
struct SliderRow: View {
    let title: String
    let description: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let unit: String?
    let formatter: ((Double) -> String)?

    init(
        title: String,
        description: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        unit: String? = nil,
        formatter: ((Double) -> String)? = nil
    ) {
        self.title = title
        self.description = description
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.formatter = formatter
    }

    private var displayValue: String {
        if let formatter = formatter {
            return formatter(value)
        }
        let formatted = step != nil && step! >= 1 ? String(Int(value)) : String(format: "%.1f", value)
        if let unit = unit {
            return "\(formatted) \(unit)"
        }
        return formatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text(displayValue)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if let description = description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let step = step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }

            HStack {
                Text(formatBound(range.lowerBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatBound(range.upperBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(displayValue)
        .accessibilityAdjustableAction { direction in
            let stepValue = step ?? (range.upperBound - range.lowerBound) / 10
            switch direction {
            case .increment:
                value = min(range.upperBound, value + stepValue)
            case .decrement:
                value = max(range.lowerBound, value - stepValue)
            @unknown default:
                break
            }
        }
    }

    private func formatBound(_ bound: Double) -> String {
        if let formatter = formatter {
            return formatter(bound)
        }
        let formatted = step != nil && step! >= 1 ? String(Int(bound)) : String(format: "%.1f", bound)
        if let unit = unit {
            return "\(formatted) \(unit)"
        }
        return formatted
    }
}

/// A number input row with stepper
struct NumberInputRow: View {
    let title: String
    let description: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String?

    init(
        title: String,
        description: String? = nil,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unit: String? = nil
    ) {
        self.title = title
        self.description = description
        self._value = value
        self.range = range
        self.unit = unit
    }

    private var displayValue: String {
        if let unit = unit {
            return "\(value) \(unit)"
        }
        return String(value)
    }

    var body: some View {
        SettingRow(title: title, description: description) {
            HStack(spacing: 8) {
                TextField("", value: $value, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)

                if let unit = unit {
                    Text(unit)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Stepper("", value: $value, in: range)
                    .labelsHidden()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(displayValue)
    }
}

// MARK: - Previews

#if DEBUG
struct SliderRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            SliderRow(
                title: "Maximum Cache Size",
                description: "Maximum space for local cache",
                value: .constant(10),
                range: 1...100,
                step: 1,
                unit: "GB"
            )

            SliderRow(
                title: "Debounce Delay",
                value: .constant(5),
                range: 1...30,
                step: 1,
                unit: "seconds"
            )

            Divider()

            NumberInputRow(
                title: "Batch Size",
                description: "Number of files per batch",
                value: .constant(100),
                range: 10...1000,
                unit: "files"
            )

            NumberInputRow(
                title: "Retry Count",
                value: .constant(3),
                range: 0...10,
                unit: "times"
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
