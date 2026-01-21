import SwiftUI

// MARK: - Card View Modifier

/// Standard card style modifier
struct CardStyle: ViewModifier {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let padding: CGFloat

    init(isSelected: Bool = false, cornerRadius: CGFloat = 8, padding: CGFloat = 12) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 2 : 1)
            )
    }
}

// MARK: - Elevated Card Style

/// Card with shadow elevation
struct ElevatedCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat

    init(cornerRadius: CGFloat = 8, shadowRadius: CGFloat = 4) {
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
    }

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.windowBackgroundColor))
                    .shadow(color: Color.black.opacity(0.1), radius: shadowRadius, x: 0, y: 2)
            )
    }
}

// MARK: - Info Card Style

/// Card for displaying information with an icon
struct InfoCardStyle: ViewModifier {
    let icon: String
    let iconColor: Color

    init(icon: String, iconColor: Color = .accentColor) {
        self.icon = icon
        self.iconColor = iconColor
    }

    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)

            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

// MARK: - Status Card Style

/// Card that changes appearance based on status
struct StatusCardStyle: ViewModifier {
    enum Status {
        case normal
        case success
        case warning
        case error

        var backgroundColor: Color {
            switch self {
            case .normal: return Color(.controlBackgroundColor)
            case .success: return Color.green.opacity(0.1)
            case .warning: return Color.orange.opacity(0.1)
            case .error: return Color.red.opacity(0.1)
            }
        }

        var borderColor: Color {
            switch self {
            case .normal: return Color(.separatorColor)
            case .success: return Color.green.opacity(0.3)
            case .warning: return Color.orange.opacity(0.3)
            case .error: return Color.red.opacity(0.3)
            }
        }
    }

    let status: Status
    let cornerRadius: CGFloat

    init(status: Status, cornerRadius: CGFloat = 8) {
        self.status = status
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(status.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(status.borderColor, lineWidth: 1)
            )
    }
}

// MARK: - View Extensions

extension View {
    /// Apply standard card style
    func cardStyle(isSelected: Bool = false, cornerRadius: CGFloat = 8, padding: CGFloat = 12) -> some View {
        modifier(CardStyle(isSelected: isSelected, cornerRadius: cornerRadius, padding: padding))
    }

    /// Apply elevated card style with shadow
    func elevatedCardStyle(cornerRadius: CGFloat = 8, shadowRadius: CGFloat = 4) -> some View {
        modifier(ElevatedCardStyle(cornerRadius: cornerRadius, shadowRadius: shadowRadius))
    }

    /// Apply info card style with icon
    func infoCardStyle(icon: String, iconColor: Color = .accentColor) -> some View {
        modifier(InfoCardStyle(icon: icon, iconColor: iconColor))
    }

    /// Apply status-based card style
    func statusCardStyle(_ status: StatusCardStyle.Status, cornerRadius: CGFloat = 8) -> some View {
        modifier(StatusCardStyle(status: status, cornerRadius: cornerRadius))
    }
}

// MARK: - Previews

#if DEBUG
struct CardStyles_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Standard Card")
                .cardStyle()

            Text("Selected Card")
                .cardStyle(isSelected: true)

            Text("Elevated Card")
                .elevatedCardStyle()

            VStack(alignment: .leading) {
                Text("Info Card")
                    .font(.headline)
                Text("Additional information goes here")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .infoCardStyle(icon: "info.circle.fill")

            HStack {
                Text("Success")
                    .statusCardStyle(.success)

                Text("Warning")
                    .statusCardStyle(.warning)

                Text("Error")
                    .statusCardStyle(.error)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
