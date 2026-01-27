import SwiftUI

// MARK: - Action Card Component

/// 快速操作卡片 - 用于仪表盘快速操作区域
struct ActionCard: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isEnabled ? .accentColor : .secondary)

                // Title
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isEnabled ? .primary : .secondary)
                    .multilineTextAlignment(.center)

                // Shortcut (optional)
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered && isEnabled
                          ? Color(NSColor.selectedContentBackgroundColor)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Action Card Grid

/// 快速操作卡片网格
struct ActionCardGrid: View {
    let cards: [ActionCardItem]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(cards) { card in
                ActionCard(
                    icon: card.icon,
                    title: card.title,
                    shortcut: card.shortcut,
                    isEnabled: card.isEnabled,
                    action: card.action
                )
            }
        }
    }
}

/// 快速操作卡片数据模型
struct ActionCardItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var shortcut: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void
}

// MARK: - Compact Action Button

/// 紧凑型操作按钮 - 用于页面内操作
struct CompactActionButton: View {
    let icon: String
    let title: String
    var style: ButtonStyleType = .secondary
    var isEnabled: Bool = true
    let action: () -> Void

    enum ButtonStyleType {
        case primary
        case secondary
        case destructive
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return .accentColor
        case .secondary:
            return Color(NSColor.controlBackgroundColor)
        case .destructive:
            return .red
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .primary
        }
    }
}

// MARK: - Icon Circle Button

/// 圆形图标按钮
struct IconCircleButton: View {
    let icon: String
    var size: CGFloat = 32
    var iconSize: CGFloat = 14
    var color: Color = .accentColor
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? color.opacity(0.2) : color.opacity(0.1))
                    .frame(width: size, height: size)

                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundColor(color)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Previews

#if DEBUG
struct ActionCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            Text("Action Cards")
                .font(.headline)

            HStack(spacing: 12) {
                ActionCard(
                    icon: "arrow.clockwise",
                    title: "Sync Now",
                    shortcut: "⌘S",
                    action: {}
                )

                ActionCard(
                    icon: "externaldrive.badge.plus",
                    title: "Add Disk",
                    action: {}
                )

                ActionCard(
                    icon: "folder",
                    title: "Open Downloads",
                    action: {}
                )
            }

            HStack(spacing: 12) {
                ActionCard(
                    icon: "arrow.clockwise",
                    title: "Disabled",
                    isEnabled: false,
                    action: {}
                )
            }

            Divider()

            Text("Compact Action Buttons")
                .font(.headline)

            HStack(spacing: 12) {
                CompactActionButton(
                    icon: "arrow.clockwise",
                    title: "Sync",
                    style: .primary,
                    action: {}
                )

                CompactActionButton(
                    icon: "pause.fill",
                    title: "Pause",
                    style: .secondary,
                    action: {}
                )

                CompactActionButton(
                    icon: "xmark",
                    title: "Cancel",
                    style: .destructive,
                    action: {}
                )
            }

            Divider()

            Text("Icon Circle Buttons")
                .font(.headline)

            HStack(spacing: 16) {
                IconCircleButton(icon: "plus", action: {})
                IconCircleButton(icon: "gear", color: .secondary, action: {})
                IconCircleButton(icon: "trash", color: .red, action: {})
                IconCircleButton(icon: "arrow.clockwise", size: 40, iconSize: 18, action: {})
            }
        }
        .padding()
        .frame(width: 500)
    }
}
#endif
