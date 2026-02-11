import SwiftUI

// MARK: - Explore View (Instagram Explore Replica)

struct ExploreView: View {
    @ObservedObject var exploreManager = ExploreManager.shared
    @Binding var selectedTab: Int
    @Binding var showingExplore: Bool
    @State private var searchText = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var showingUserProfile = false
    @State private var searchedProfile: InstagramProfile?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showingConnectionError = false
    @State private var lastError: InstagramError?
    
    var body: some View {
        ZStack {
            // Main Explore view
            ZStack(alignment: .bottom) {
                // White background covering everything
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                // Search bar at top
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .font(.system(size: 16))
                        
                        TextField("Buscar", text: $searchText)
                            .font(.system(size: 16))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isSearchFieldFocused)
                            .onChange(of: searchText) { newValue in
                                performSearch(query: newValue)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                                isSearchFieldFocused = false
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 16))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(10)
                    
                    if isSearchFieldFocused || !searchText.isEmpty {
                        Button("Cancelar") {
                            searchText = ""
                            searchResults = []
                            isSearchFieldFocused = false
                        }
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    } else {
                        Button(action: {}) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .foregroundColor(.primary)
                                .font(.system(size: 20))
                        }
                    }
                }
                .responsiveHorizontalPadding()
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
                
                // Show search results if searching
                if !searchText.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            if isSearching {
                                HStack {
                                    ProgressView()
                                    Text("Buscando...")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            } else if searchResults.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    Text("No se encontraron resultados")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 60)
                            } else {
                                ForEach(searchResults) { result in
                                    SearchResultRow(result: result, onTap: {
                                        loadUserProfile(userId: result.userId)
                                    })
                                }
                            }
                        }
                    }
                    .background(Color.white)
                } else {
                    // Grid of explore content
                    if exploreManager.isLoading || exploreManager.exploreMedia.isEmpty {
                        // Show skeleton UI (like Instagram real)
                        ExploreGridSkeleton()
                            .padding(.bottom, 65)
                    } else {
                        ScrollView {
                            ExploreGridView(
                                mediaItems: exploreManager.exploreMedia,
                                cachedImages: exploreManager.cachedImages
                            )
                            .padding(.bottom, 65)
                        }
                    }
                }
            }
            
            // Instagram bottom bar
            InstagramBottomBar(
                profileImageURL: nil,
                cachedImage: nil,
                isHome: false,
                isSearch: true,
                onHomePress: {
                    showingExplore = false
                    selectedTab = 0 // Performance (perfil del usuario)
                },
                onSearchPress: {
                    // Already on search
                },
                onReelsPress: {
                    // Reels (disabled)
                },
                onMessagesPress: {
                    // Messages (disabled)
                },
                onProfilePress: {
                    showingExplore = false
                    selectedTab = 0 // Performance
                }
            )
            }
            .toolbar(.hidden, for: .tabBar)
            .edgesIgnoringSafeArea(.bottom)
            .navigationBarHidden(true)
            .overlay(
                Group {
                    if isSearching {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                            
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                
                                Text("Buscando @\(searchText)...")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                            .padding(32)
                            .background(Color(uiColor: .systemBackground))
                            .cornerRadius(16)
                        }
                    }
                }
            )
            
            // User Profile overlay (full screen on top)
            if showingUserProfile, let profile = searchedProfile {
                UserProfileView(profile: profile, onClose: {
                    withAnimation {
                        showingUserProfile = false
                    }
                })
                .transition(.move(edge: .trailing))
                .zIndex(1000)
            }
        }
        .connectionErrorAlert(isPresented: $showingConnectionError, error: lastError)
        .onAppear {
            // Auto-load Explore feed on appear (like Instagram real)
            if exploreManager.exploreMedia.isEmpty {
                exploreManager.loadExplore()
            }
        }
    }
    
    private func performSearch(query: String) {
        // Cancel previous search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // Debounce: wait 300ms before searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            do {
                let results = try await InstagramService.shared.searchUsers(query: query)
                
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    searchResults = results
                    isSearching = false
                }
            } catch let error as InstagramError {
                print("❌ [SEARCH] Instagram error: \(error)")
                await MainActor.run {
                    isSearching = false
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ [SEARCH] Error: \(error)")
                await MainActor.run {
                    isSearching = false
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
        }
    }
    
    private func loadUserProfile(userId: String) {
        isSearchFieldFocused = false
        
        print("🔍 [UI] Loading profile for user ID: \(userId)")
        
        Task {
            do {
                let profile = try await InstagramService.shared.getProfileInfo(userId: userId)
                
                await MainActor.run {
                    if let profile = profile {
                        print("✅ [UI] Profile loaded successfully: @\(profile.username)")
                        print("✅ [UI] Profile has \(profile.cachedMediaURLs.count) media URLs")
                        searchedProfile = profile
                        showingUserProfile = true
                        print("✅ [UI] showingUserProfile set to true")
                    } else {
                        print("❌ [UI] Profile is nil")
                    }
                }
            } catch let error as InstagramError {
                print("❌ [PROFILE] Instagram error loading profile: \(error)")
                await MainActor.run {
                    lastError = error
                    showingConnectionError = true
                }
            } catch {
                print("❌ [PROFILE] Error loading profile: \(error)")
                await MainActor.run {
                    lastError = .apiError(error.localizedDescription)
                    showingConnectionError = true
                }
            }
        }
    }
}

// MARK: - Explore Grid View

struct ExploreGridView: View {
    let mediaItems: [InstagramMediaItem]
    let cachedImages: [String: UIImage]
    
    var body: some View {
        LazyVStack(spacing: 2) {
            // Create rows of 3 items
            ForEach(0..<((mediaItems.count + 2) / 3), id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { colIndex in
                        let index = rowIndex * 3 + colIndex
                        if index < mediaItems.count {
                            ExploreMediaCell(
                                media: mediaItems[index],
                                cachedImage: cachedImages[mediaItems[index].imageURL]
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: UserSearchResult
    let onTap: () -> Void
    @State private var profileImage: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Profile picture
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                        )
                }
                
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(result.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if result.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    if !result.fullName.isEmpty {
                        Text(result.fullName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .responsiveHorizontalPadding()
            .padding(.vertical, 8)
            .background(Color.white)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard !result.profilePicURL.isEmpty,
              let url = URL(string: result.profilePicURL) else { return }
        
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let image = UIImage(data: data) {
                await MainActor.run {
                    profileImage = image
                }
            }
        }
    }
}

// MARK: - Explore Media Cell

struct ExploreMediaCell: View {
    let media: InstagramMediaItem
    let cachedImage: UIImage?
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            
            ZStack(alignment: .topTrailing) {
                // Show video player if it's a video, otherwise show image
                if media.mediaType == .video, let videoURL = media.videoURL {
                    GridVideoPlayer(videoURL: videoURL)
                        .frame(width: size, height: size)
                        .clipped()
                } else if let image = cachedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: size, height: size)
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
                
                // Carousel indicator (multiple icon)
                if media.mediaType == .carousel {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(6)
                }
            }
        }
        .aspectRatio(4/5, contentMode: .fit) // Instagram aspect ratio (same as profile grid)
    }
}
