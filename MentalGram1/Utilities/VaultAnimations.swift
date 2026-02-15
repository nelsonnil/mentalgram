import SwiftUI

// MARK: - Vault Animation System

struct VaultAnimations {
    
    // MARK: - Standard Animations
    
    static let quick = Animation.easeInOut(duration: 0.2)
    static let standard = Animation.easeInOut(duration: 0.3)
    static let smooth = Animation.easeInOut(duration: 0.4)
    static let gentle = Animation.easeInOut(duration: 0.6)
    
    // MARK: - Spring Animations
    
    static let springQuick = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let springStandard = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.6)
    
    // MARK: - Specialized Animations
    
    static let fadeIn = Animation.easeIn(duration: 0.2)
    static let fadeOut = Animation.easeOut(duration: 0.2)
    static let slideIn = Animation.easeOut(duration: 0.3)
}

// MARK: - Animated View Modifiers

struct PulseEffect: ViewModifier {
    @State private var isPulsing = false
    let color: Color
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .shadow(color: color.opacity(isPulsing ? 0.5 : 0.2), radius: isPulsing ? 15 : 8)
            .animation(
                Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

struct FloatingEffect: ViewModifier {
    @State private var isFloating = false
    
    func body(content: Content) -> some View {
        content
            .offset(y: isFloating ? -10 : 0)
            .animation(
                Animation.easeInOut(duration: 2).repeatForever(autoreverses: true),
                value: isFloating
            )
            .onAppear {
                isFloating = true
            }
    }
}

// MARK: - View Extensions

extension View {
    func pulseEffect(color: Color = VaultTheme.Colors.primary) -> some View {
        self.modifier(PulseEffect(color: color))
    }
    
    func shimmerEffect() -> some View {
        self.modifier(ShimmerEffect())
    }
    
    func floatingEffect() -> some View {
        self.modifier(FloatingEffect())
    }
    
    func fadeTransition() -> some View {
        self.transition(.opacity.animation(VaultAnimations.fadeIn))
    }
    
    func scaleTransition() -> some View {
        self.transition(.scale.combined(with: .opacity).animation(VaultAnimations.springQuick))
    }
    
    func slideTransition() -> some View {
        self.transition(.move(edge: .trailing).combined(with: .opacity).animation(VaultAnimations.slideIn))
    }
}

// MARK: - Loading Indicators

struct VaultLoadingView: View {
    @State private var isAnimating = false
    var size: CGFloat = 50
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(VaultTheme.Colors.cardBorder, lineWidth: 4)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(VaultTheme.Colors.gradientPrimary, lineWidth: 4)
                .frame(width: size, height: size)
                .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                .animation(
                    Animation.linear(duration: 1).repeatForever(autoreverses: false),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct VaultSpinnerView: View {
    @State private var rotation: Double = 0
    var color: Color = VaultTheme.Colors.primary
    var size: CGFloat = 20
    
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: size))
            .foregroundColor(color)
            .rotationEffect(Angle(degrees: rotation))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
