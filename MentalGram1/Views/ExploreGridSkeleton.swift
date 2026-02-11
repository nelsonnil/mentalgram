import SwiftUI

/// Instagram Explore skeleton loading UI
/// Shows gray animated placeholders in grid format
struct ExploreGridSkeleton: View {
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ],
                spacing: 2
            ) {
                ForEach(0..<30) { index in
                    SkeletonGridItem()
                        .transition(.opacity)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct SkeletonGridItem: View {
    @State private var isAnimating = false
    let width = (UIScreen.main.bounds.width - 4) / 3
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.25),
                        Color.gray.opacity(0.15),
                        Color.gray.opacity(0.25)
                    ]),
                    startPoint: isAnimating ? .topLeading : .bottomTrailing,
                    endPoint: isAnimating ? .bottomTrailing : .topLeading
                )
            )
            .frame(width: width, height: width)
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
