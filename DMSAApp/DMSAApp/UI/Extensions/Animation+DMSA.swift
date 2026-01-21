import SwiftUI

// MARK: - Animation Extensions

extension Animation {
    // MARK: - Standard Animations

    /// Quick animation for immediate feedback (100ms)
    static var dmQuick: Animation {
        .easeOut(duration: 0.1)
    }

    /// Standard animation for most UI transitions (200ms)
    static var dmStandard: Animation {
        .easeInOut(duration: 0.2)
    }

    /// Smooth animation for larger transitions (300ms)
    static var dmSmooth: Animation {
        .easeInOut(duration: 0.3)
    }

    /// Spring animation for bouncy effects
    static var dmSpring: Animation {
        .spring(response: 0.3, dampingFraction: 0.7)
    }

    /// Gentle spring for subtle bounces
    static var dmGentleSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.8)
    }

    // MARK: - Specific Animations

    /// Animation for menu expansion
    static var dmMenuExpand: Animation {
        .easeOut(duration: 0.2)
    }

    /// Animation for window appearance
    static var dmWindowAppear: Animation {
        .spring(response: 0.3, dampingFraction: 0.8)
    }

    /// Animation for progress bar updates
    static var dmProgress: Animation {
        .easeInOut(duration: 0.3)
    }

    /// Animation for status changes
    static var dmStatusChange: Animation {
        .easeInOut(duration: 0.3)
    }

    /// Animation for sync icon rotation (continuous)
    static var dmSyncRotation: Animation {
        .linear(duration: 1.0).repeatForever(autoreverses: false)
    }

    /// Animation for hover effects
    static var dmHover: Animation {
        .easeInOut(duration: 0.15)
    }

    /// Animation for selection changes
    static var dmSelection: Animation {
        .easeInOut(duration: 0.2)
    }

    /// Animation for content loading
    static var dmLoading: Animation {
        .easeInOut(duration: 0.5)
    }

    /// Animation for fade in/out
    static var dmFade: Animation {
        .easeInOut(duration: 0.25)
    }
}

// MARK: - View Transition Extensions

extension AnyTransition {
    /// Slide and fade transition from bottom
    static var dmSlideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Slide and fade transition from top
    static var dmSlideDown: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    /// Scale and fade transition
    static var dmScale: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    /// Standard fade transition
    static var dmFade: AnyTransition {
        .opacity
    }
}

// MARK: - View Modifier for Animated Appearance

struct AnimatedAppearance: ViewModifier {
    let animation: Animation
    @State private var isVisible: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .onAppear {
                withAnimation(animation) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Apply animated appearance when view appears
    func animatedAppearance(_ animation: Animation = .dmSpring) -> some View {
        modifier(AnimatedAppearance(animation: animation))
    }
}

// MARK: - Rotating View Modifier

struct RotatingModifier: ViewModifier {
    let isAnimating: Bool
    @State private var rotation: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .onChange(of: isAnimating) { animating in
                if animating {
                    withAnimation(.dmSyncRotation) {
                        rotation = 360
                    }
                } else {
                    rotation = 0
                }
            }
    }
}

extension View {
    /// Apply continuous rotation when condition is true
    func rotating(when isAnimating: Bool) -> some View {
        modifier(RotatingModifier(isAnimating: isAnimating))
    }
}

// MARK: - Pulsing View Modifier

struct PulsingModifier: ViewModifier {
    let isAnimating: Bool
    @State private var isPulsing: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .onChange(of: isAnimating) { animating in
                if animating {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPulsing = false
                    }
                }
            }
    }
}

extension View {
    /// Apply pulsing animation when condition is true
    func pulsing(when isAnimating: Bool) -> some View {
        modifier(PulsingModifier(isAnimating: isAnimating))
    }
}

// MARK: - Previews

#if DEBUG
struct AnimationExtensions_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            // Animated appearance
            Text("Animated Appearance")
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
                .animatedAppearance()

            // Rotating icon
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .rotating(when: true)

            // Pulsing indicator
            Circle()
                .fill(Color.green)
                .frame(width: 20, height: 20)
                .pulsing(when: true)
        }
        .padding()
    }
}
#endif
