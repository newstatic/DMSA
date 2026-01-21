import SwiftUI

// MARK: - Color Extensions

extension Color {
    // MARK: - Semantic Colors

    /// Primary background color
    static var dmBackground: Color {
        Color(.windowBackgroundColor)
    }

    /// Secondary background color (for cards, etc.)
    static var dmSecondaryBackground: Color {
        Color(.controlBackgroundColor)
    }

    /// Primary text color
    static var dmText: Color {
        Color(.labelColor)
    }

    /// Secondary text color
    static var dmSecondaryText: Color {
        Color(.secondaryLabelColor)
    }

    /// Tertiary text color
    static var dmTertiaryText: Color {
        Color(.tertiaryLabelColor)
    }

    /// Border/separator color
    static var dmBorder: Color {
        Color(.separatorColor)
    }

    // MARK: - Status Colors

    /// Success color (green)
    static var dmSuccess: Color {
        Color.green
    }

    /// Warning color (orange)
    static var dmWarning: Color {
        Color.orange
    }

    /// Error color (red)
    static var dmError: Color {
        Color.red
    }

    /// Info color (blue)
    static var dmInfo: Color {
        Color.accentColor
    }

    // MARK: - Sync Status Colors

    /// Color for connected disk status
    static var dmConnected: Color {
        Color.green
    }

    /// Color for disconnected disk status
    static var dmDisconnected: Color {
        Color.gray
    }

    /// Color for syncing status
    static var dmSyncing: Color {
        Color.accentColor
    }

    /// Color for pending sync
    static var dmPending: Color {
        Color.orange
    }

    // MARK: - Storage Bar Colors

    /// Storage bar color based on usage percentage
    static func storageColor(percentage: Double) -> Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.75 {
            return .orange
        } else {
            return .accentColor
        }
    }

    // MARK: - Convenience Initializers

    /// Create color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - NSColor Extensions

extension NSColor {
    /// Create NSColor from hex string
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ColorExtensions_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 10) {
            Group {
                colorSwatch("Background", color: .dmBackground)
                colorSwatch("Secondary BG", color: .dmSecondaryBackground)
                colorSwatch("Text", color: .dmText)
                colorSwatch("Secondary Text", color: .dmSecondaryText)
                colorSwatch("Border", color: .dmBorder)
            }

            Divider()

            Group {
                colorSwatch("Success", color: .dmSuccess)
                colorSwatch("Warning", color: .dmWarning)
                colorSwatch("Error", color: .dmError)
                colorSwatch("Info", color: .dmInfo)
            }

            Divider()

            Group {
                colorSwatch("Connected", color: .dmConnected)
                colorSwatch("Disconnected", color: .dmDisconnected)
                colorSwatch("Syncing", color: .dmSyncing)
            }

            Divider()

            HStack {
                colorSwatch("50%", color: .storageColor(percentage: 0.5))
                colorSwatch("80%", color: .storageColor(percentage: 0.8))
                colorSwatch("95%", color: .storageColor(percentage: 0.95))
            }
        }
        .padding()
    }

    static func colorSwatch(_ name: String, color: Color) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 40, height: 24)
            Text(name)
                .font(.caption)
        }
    }
}
#endif
