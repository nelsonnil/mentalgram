import SwiftUI

/// Instagram-style skeleton loading UI
/// Shows gray placeholders while profile is loading
struct InstagramProfileSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Top Bar (Instagram style)
                HStack {
                    SkeletonBox(width: 120, height: 20)
                        .padding(.leading, 16)
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        SkeletonCircle(size: 24)
                        SkeletonCircle(size: 24)
                    }
                    .padding(.trailing, 16)
                }
                .frame(height: 44)
                .padding(.top, 8)
                
                // Profile Header
                VStack(spacing: 16) {
                    // Profile Picture
                    SkeletonCircle(size: 86)
                        .padding(.top, 16)
                    
                    // Username
                    SkeletonBox(width: 140, height: 18)
                    
                    // Stats (Posts, Followers, Following)
                    HStack(spacing: 40) {
                        VStack(spacing: 4) {
                            SkeletonBox(width: 50, height: 20)
                            SkeletonBox(width: 50, height: 14)
                        }
                        VStack(spacing: 4) {
                            SkeletonBox(width: 50, height: 20)
                            SkeletonBox(width: 60, height: 14)
                        }
                        VStack(spacing: 4) {
                            SkeletonBox(width: 50, height: 20)
                            SkeletonBox(width: 60, height: 14)
                        }
                    }
                    .padding(.top, 8)
                    
                    // Bio
                    VStack(spacing: 6) {
                        SkeletonBox(width: UIScreen.main.bounds.width - 48, height: 14)
                        SkeletonBox(width: UIScreen.main.bounds.width - 80, height: 14)
                        SkeletonBox(width: UIScreen.main.bounds.width - 120, height: 14)
                    }
                    .padding(.top, 12)
                    
                    // Edit Profile Button
                    SkeletonBox(width: UIScreen.main.bounds.width - 32, height: 32)
                        .cornerRadius(8)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                
                // Tab Bar (Grid/Tagged/etc)
                HStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        SkeletonBox(width: UIScreen.main.bounds.width / 3, height: 44)
                    }
                }
                .padding(.top, 24)
                
                // Photos Grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(0..<12) { _ in
                        SkeletonBox(
                            width: (UIScreen.main.bounds.width - 4) / 3,
                            height: (UIScreen.main.bounds.width - 4) / 3 * 1.25
                        )
                    }
                }
                .padding(.top, 1)
            }
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Skeleton Components

struct SkeletonBox: View {
    let width: CGFloat
    let height: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .frame(width: width, height: height)
            .cornerRadius(4)
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating.toggle()
                }
            }
    }
}

struct SkeletonCircle: View {
    let size: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating.toggle()
                }
            }
    }
}

// MARK: - Preview

struct InstagramProfileSkeleton_Previews: PreviewProvider {
    static var previews: some View {
        InstagramProfileSkeleton()
    }
}
