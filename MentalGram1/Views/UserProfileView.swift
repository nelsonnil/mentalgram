import SwiftUI

/// Vista de perfil de usuario buscado (réplica exacta de Instagram)
struct UserProfileView: View {
    let profile: InstagramProfile
    let onClose: () -> Void
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isLoadingImages = true
    @State private var selectedTab = 0
    @State private var isFollowing: Bool
    @State private var isFollowActionLoading = false
    
    init(profile: InstagramProfile, onClose: @escaping () -> Void) {
        self.profile = profile
        self.onClose = onClose
        self._isFollowing = State(initialValue: profile.isFollowing)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header (igual que Instagram)
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 24))
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Username con candado si es privado
                    HStack(spacing: 4) {
                        if profile.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                        }
                        Text(profile.username)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button(action: {}) {
                            Image(systemName: "bell")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: {}) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 24))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .responsiveHorizontalPadding()
                .padding(.vertical, 12)
                .background(Color.white)
                
                // Main content
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile Picture + Stats
                        HStack(alignment: .center, spacing: 0) {
                            // Profile Picture con círculo de historia
                            ZStack(alignment: .bottomTrailing) {
                                if !profile.profilePicURL.isEmpty,
                                   let image = cachedImages[profile.profilePicURL] {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 86, height: 86)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [.purple, .red, .orange],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 2
                                                )
                                                .padding(-2)
                                        )
                                } else {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 86, height: 86)
                                }
                                
                                // Plus button azul
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                            .padding(.leading, UIScreen.main.bounds.width * 0.04)
                            
                            Spacer(minLength: 8)
                            
                            // Stats
                            HStack(spacing: 0) {
                                UserStatView(number: profile.mediaCount, label: "posts")
                                UserStatView(number: profile.followerCount, label: "followers")
                                UserStatView(number: profile.followingCount, label: "following")
                            }
                            .padding(.trailing, UIScreen.main.bounds.width * 0.04)
                        }
                        
                        // Name + Bio
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.fullName)
                                .font(.system(size: 14, weight: .semibold))
                            
                            if !profile.biography.isEmpty {
                                Text(profile.biography)
                                    .font(.system(size: 14))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            if let url = profile.externalUrl, !url.isEmpty {
                                Link(url, destination: URL(string: "https://\(url)")!)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                            }
                            
                            // "@" + Name badge
                            HStack(spacing: 4) {
                                Image(systemName: "at.circle.fill")
                                    .font(.system(size: 12))
                                Text(profile.fullName)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .responsiveHorizontalPadding()
                        
                        // Followed by
                        if !profile.followedBy.isEmpty {
                            FollowedByView(followers: profile.followedBy, cachedImages: cachedImages)
                                .responsiveHorizontalPadding()
                        }
                        
                        // Following/Follow + Message buttons
                        HStack(spacing: 8) {
                            // Follow/Following button (FUNCIONAL)
                            Button(action: toggleFollow) {
                                if isFollowActionLoading {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .cornerRadius(8)
                                } else if isFollowing {
                                    HStack(spacing: 4) {
                                        Text("Following")
                                            .font(.system(size: 14, weight: .semibold))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(8)
                                } else {
                                    Text("Follow")
                                        .font(.system(size: 14, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                            .disabled(isFollowActionLoading)
                            
                            Button(action: {}) {
                                Text("Message")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .foregroundColor(.primary)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {}) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                    .frame(width: 32, height: 32)
                                    .background(Color(uiColor: .systemGray5))
                                    .cornerRadius(8)
                            }
                        }
                        .responsiveHorizontalPadding()
                        
                        // Story Highlights (placeholder)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                // Placeholder circles para highlights
                                ForEach(0..<3, id: \.self) { _ in
                                    VStack(spacing: 4) {
                                        Circle()
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            .frame(width: 64, height: 64)
                                        Text("")
                                            .font(.system(size: 12))
                                            .foregroundColor(.clear)
                                    }
                                }
                            }
                            .responsiveHorizontalPadding()
                        }
                        .padding(.vertical, 8)
                    }
                    .padding(.vertical, 12)
                    
                    // Tabs
                    HStack(spacing: 0) {
                        TabButton(icon: "square.grid.3x3", isSelected: selectedTab == 0) {
                            selectedTab = 0
                        }
                        TabButton(icon: "play.rectangle", isSelected: selectedTab == 1) {
                            selectedTab = 1
                        }
                        TabButton(icon: "person.crop.square", isSelected: selectedTab == 2) {
                            selectedTab = 2
                        }
                    }
                    .frame(height: 44)
                    
                    Divider()
                    
                    // Photo grid
                    PhotosGridView(
                        mediaURLs: profile.cachedMediaURLs,
                        cachedImages: cachedImages
                    )
                    .padding(.bottom, 65) // Space for bottom bar
                }
            }
            
            // Instagram bottom bar (igual que en Performance/Explore)
            InstagramBottomBar(
                profileImageURL: profile.profilePicURL,
                cachedImage: cachedImages[profile.profilePicURL],
                isHome: false,
                isSearch: false,
                onHomePress: {
                    // No action - stay here
                },
                onSearchPress: {
                    // No action - stay here
                },
                onReelsPress: {
                    // No action
                },
                onMessagesPress: {
                    // No action
                },
                onProfilePress: {
                    // Already on a profile
                }
            )
        }
        .navigationBarHidden(true)
        .onAppear {
            print("🎨 [UI] UserProfileView appeared for @\(profile.username)")
            print("🎨 [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
            print("🎨 [UI] Profile pic URL: \(profile.profilePicURL)")
            loadImages()
        }
    }
    
    private func loadImages() {
        print("🖼️ [UI] Starting to load images...")
        
        Task {
            // Load profile pic
            print("🖼️ [UI] Loading profile pic: \(profile.profilePicURL)")
            if !profile.profilePicURL.isEmpty,
               let url = URL(string: profile.profilePicURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    cachedImages[profile.profilePicURL] = image
                    print("✅ [UI] Profile pic loaded and cached")
                }
            } else {
                print("❌ [UI] Failed to load profile pic")
            }
            
            // Load follower pics
            for follower in profile.followedBy {
                if let picURL = follower.profilePicURL,
                   !picURL.isEmpty,
                   let url = URL(string: picURL),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        cachedImages[picURL] = image
                    }
                }
            }
            
            // Load media thumbnails
            for mediaURL in profile.cachedMediaURLs {
                guard !mediaURL.isEmpty,
                      let url = URL(string: mediaURL),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { continue }
                
                await MainActor.run {
                    cachedImages[mediaURL] = image
                }
            }
            
            await MainActor.run {
                isLoadingImages = false
            }
        }
    }
    
    private func toggleFollow() {
        guard !isFollowActionLoading else { return }
        
        isFollowActionLoading = true
        
        Task {
            do {
                let success: Bool
                
                if isFollowing {
                    // Unfollow
                    print("➖ [UI] Unfollowing @\(profile.username)...")
                    success = try await InstagramService.shared.unfollowUser(userId: profile.userId)
                } else {
                    // Follow
                    print("➕ [UI] Following @\(profile.username)...")
                    success = try await InstagramService.shared.followUser(userId: profile.userId)
                }
                
                await MainActor.run {
                    if success {
                        isFollowing.toggle()
                        print("✅ [UI] Follow status updated: \(isFollowing ? "Following" : "Not following")")
                    } else {
                        print("❌ [UI] Follow action failed")
                    }
                    isFollowActionLoading = false
                }
            } catch {
                print("❌ [UI] Error toggling follow: \(error)")
                await MainActor.run {
                    isFollowActionLoading = false
                }
            }
        }
    }
}

private struct UserStatView: View {
    let number: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(formatCount(number))")
                .font(.system(size: 16, weight: .semibold))
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}
