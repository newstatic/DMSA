import SwiftUI

// MARK: - Status Ring Component

/// Status ring component - displays status icon and optional progress
/// Used in dashboard status banner and sync page
struct StatusRing: View {
    let size: CGFloat
    let icon: String
    let color: Color
    var progress: Double? = nil
    var isAnimating: Bool = false

    @State private var rotation: Double = 0

    // MARK: - Computed Properties

    private var strokeWidth: CGFloat {
        size * 0.06
    }

    private var iconSize: CGFloat {
        size * 0.4
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: strokeWidth)

            // Progress arc (if progress is provided)
            if let progress = progress {
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: strokeWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }

            // Inner background
            Circle()
                .fill(color.opacity(0.1))
                .padding(strokeWidth + 4)

            // Icon
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(color)
                .rotationEffect(.degrees(isAnimating ? rotation : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            startAnimationIfNeeded()
        }
        .onChange(of: isAnimating) { _ in
            startAnimationIfNeeded()
        }
    }

    // MARK: - Animation

    private func startAnimationIfNeeded() {
        if isAnimating {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                rotation = 0
            }
        }
    }
}

// MARK: - Status Ring Styles

extension StatusRing {
    /// Ready state
    static func ready(size: CGFloat) -> StatusRing {
        StatusRing(
            size: size,
            icon: "checkmark.circle.fill",
            color: .green,
            progress: 1.0
        )
    }

    /// Syncing state
    static func syncing(size: CGFloat, progress: Double) -> StatusRing {
        StatusRing(
            size: size,
            icon: "arrow.clockwise",
            color: .blue,
            progress: progress,
            isAnimating: true
        )
    }

    /// Paused state
    static func paused(size: CGFloat, progress: Double) -> StatusRing {
        StatusRing(
            size: size,
            icon: "pause.circle.fill",
            color: .orange,
            progress: progress
        )
    }

    /// Error state
    static func error(size: CGFloat) -> StatusRing {
        StatusRing(
            size: size,
            icon: "exclamationmark.triangle.fill",
            color: .red
        )
    }

    /// Has conflicts state
    static func hasConflicts(size: CGFloat) -> StatusRing {
        StatusRing(
            size: size,
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            progress: 1.0
        )
    }

    /// Service unavailable
    static func unavailable(size: CGFloat) -> StatusRing {
        StatusRing(
            size: size,
            icon: "xmark.circle.fill",
            color: .gray
        )
    }
}

// MARK: - Small Status Dot

/// Small status dot - used in list items
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Status Badge

/// Status badge - used to display connection status, etc.
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(10)
    }
}

// MARK: - Previews

#if DEBUG
struct StatusRing_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            Text("Status Ring Variants")
                .font(.headline)

            HStack(spacing: 24) {
                VStack {
                    StatusRing.ready(size: 80)
                    Text("Ready").font(.caption)
                }

                VStack {
                    StatusRing.syncing(size: 80, progress: 0.65)
                    Text("Syncing").font(.caption)
                }

                VStack {
                    StatusRing.paused(size: 80, progress: 0.4)
                    Text("Paused").font(.caption)
                }
            }

            HStack(spacing: 24) {
                VStack {
                    StatusRing.error(size: 80)
                    Text("Error").font(.caption)
                }

                VStack {
                    StatusRing.hasConflicts(size: 80)
                    Text("Conflicts").font(.caption)
                }

                VStack {
                    StatusRing.unavailable(size: 80)
                    Text("Unavailable").font(.caption)
                }
            }

            Divider()

            Text("Size Variants")
                .font(.headline)

            HStack(spacing: 24) {
                StatusRing.ready(size: 40)
                StatusRing.ready(size: 60)
                StatusRing.ready(size: 80)
                StatusRing.ready(size: 100)
            }

            Divider()

            Text("Status Dot & Badge")
                .font(.headline)

            HStack(spacing: 16) {
                StatusDot(color: .green)
                StatusDot(color: .orange)
                StatusDot(color: .red)
                StatusDot(color: .gray)
            }

            HStack(spacing: 12) {
                StatusBadge(text: "Connected", color: .green)
                StatusBadge(text: "Syncing", color: .blue)
                StatusBadge(text: "Offline", color: .gray)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
