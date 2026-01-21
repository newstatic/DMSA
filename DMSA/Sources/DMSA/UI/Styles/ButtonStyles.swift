import SwiftUI

// MARK: - Primary Button Style

/// Primary action button style
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? Color.accentColor : Color.accentColor.opacity(0.5))
            )
            .foregroundColor(.white)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

/// Secondary action button style
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .foregroundColor(isEnabled ? .primary : .secondary)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Destructive Button Style

/// Destructive action button style
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? Color.red : Color.red.opacity(0.5))
            )
            .foregroundColor(.white)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Icon Button Style

/// Icon-only button style
struct IconButtonStyle: ButtonStyle {
    let size: CGFloat

    init(size: CGFloat = 24) {
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color(.selectedContentBackgroundColor) : Color.clear)
            )
            .foregroundColor(.secondary)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Menu Button Style

/// Style for menu items
struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color(.selectedContentBackgroundColor) : Color.clear)
            )
            .foregroundColor(.primary)
    }
}

// MARK: - Link Button Style

/// Hyperlink-style button
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.accentColor)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Card Button Style

/// Button that looks like a selectable card
struct CardButtonStyle: ButtonStyle {
    let isSelected: Bool

    init(isSelected: Bool = false) {
        self.isSelected = isSelected
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(.separatorColor), lineWidth: isSelected ? 2 : 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Button Style Extension

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var linkStyle: LinkButtonStyle { LinkButtonStyle() }
}

// MARK: - Previews

#if DEBUG
struct ButtonStyles_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Button("Primary Button") { }
                .buttonStyle(PrimaryButtonStyle())

            Button("Secondary Button") { }
                .buttonStyle(SecondaryButtonStyle())

            Button("Destructive Button") { }
                .buttonStyle(DestructiveButtonStyle())

            Button("Link Button") { }
                .buttonStyle(LinkButtonStyle())

            HStack {
                Button { } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(IconButtonStyle())

                Button { } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(IconButtonStyle())
            }

            Button { } label: {
                HStack {
                    Image(systemName: "folder")
                    Text("Card Button")
                    Spacer()
                }
            }
            .buttonStyle(CardButtonStyle(isSelected: true))
            .frame(width: 200)
        }
        .padding()
    }
}
#endif
