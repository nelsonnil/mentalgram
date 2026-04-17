import SwiftUI

// MARK: - Followers List View (fake Instagram UI)

struct FollowersListView: View {
    let username: String
    let followerCount: Int
    let followingCount: Int
    let onClose: () -> Void

    @ObservedObject private var dateForce = DateForceSettings.shared

    @State private var followers: [InstagramFollower] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedTab = 0
    @State private var searchQuery = ""

    /// Ordered list of selected follower IDs (order = selection rank).
    @State private var selectedIds: [String] = []

    /// Follower tapped to open their profile (non-avatar tap).
    @State private var profileTarget: InstagramFollower? = nil

    /// In-session profile cache: avoids re-fetching already-loaded profiles.
    @State private var profileCache: [String: InstagramProfile] = [:]

    private var instagram: InstagramService { InstagramService.shared }

    // MARK: - Selection helpers

    private func isSelected(_ follower: InstagramFollower) -> Bool {
        selectedIds.contains(follower.userId)
    }

    private func selectionRank(of follower: InstagramFollower) -> Int? {
        selectedIds.firstIndex(of: follower.userId).map { $0 + 1 }
    }

    private func toggle(_ follower: InstagramFollower) {
        if let idx = selectedIds.firstIndex(of: follower.userId) {
            selectedIds.remove(at: idx)
        } else {
            selectedIds.append(follower.userId)
            schedulePreload(for: follower)
        }
    }

    /// Pre-loads the spectator's profile in the background with anti-bot protections:
    /// - Skips if session is currently challenged (rate-limited by Instagram).
    /// - Adds a random human-like delay proportional to selection rank to avoid
    ///   firing multiple simultaneous GET /users/{id}/info/ calls in quick succession.
    private func schedulePreload(for follower: InstagramFollower) {
        guard dateForce.preloadedProfiles[follower.userId] == nil else { return }

        // Rank of this follower in the selection order (1-based).
        let rank = selectedIds.count   // already appended above, so count = rank

        Task {
            // Skip entirely if Instagram is rate-limiting us right now.
            guard !instagram.isSessionChallenged else {
                print("⏸ [PRE-LOAD] Skipped @\(follower.userId) — session challenged")
                return
            }

            // Stagger calls: each additional selection waits an extra 1.2–2.0 s so
            // simultaneous taps don't fire N parallel GET requests at once.
            if rank > 1 {
                let jitter = Double.random(in: 1_200_000_000...2_000_000_000)
                try? await Task.sleep(nanoseconds: UInt64(Double(rank - 1) * jitter / 1.0))
            }

            // Re-check after the delay (user may have deselected in the meantime).
            guard selectedIds.contains(follower.userId),
                  dateForce.preloadedProfiles[follower.userId] == nil,
                  !instagram.isSessionChallenged else { return }

            if let p = try? await instagram.getProfileInfo(userId: follower.userId) {
                await MainActor.run {
                    dateForce.preloadedProfiles[follower.userId] = (
                        username: p.username,
                        followerCount: p.followerCount,
                        followingCount: p.followingCount
                    )
                    print("⚡️ [PRE-LOAD] @\(p.username) — followers:\(p.followerCount) following:\(p.followingCount)")
                }
            }
        }
    }

    /// Saves the ordered selection and closes the view.
    private func saveAndClose() {
        if !selectedIds.isEmpty {
            dateForce.autoSpectatorCount = selectedIds.count
            dateForce.selectedFollowerIds = selectedIds   // preserves selection order
        }
        onClose()
    }

    // MARK: - Filtered list

    private var filteredFollowers: [InstagramFollower] {
        guard !searchQuery.isEmpty else { return followers }
        let q = searchQuery.lowercased()
        return followers.filter {
            $0.username.lowercased().contains(q) || $0.fullName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            tabRow
            searchBar
            Divider()
            if isLoading {
                Spacer()
                ProgressView().tint(.black)
                Spacer()
            } else if let err = errorMessage {
                Spacer()
                Text(err)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding()
                Spacer()
            } else {
                followersList
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .task { await loadFollowers() }
        .fullScreenCover(item: $profileTarget) { follower in
            FollowerProfileSheet(
                follower: follower,
                cachedProfile: profileCache[follower.userId],
                onProfileLoaded: { loaded in profileCache[loaded.userId] = loaded },
                onClose: { profileTarget = nil }
            )
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Nav bar

    private var navBar: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                Color.clear.frame(height: statusBarHeight)
                HStack {
                    // Back — saves selection on close
                    Button(action: saveAndClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text(username)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                    Spacer()
                    Image("instagram_add_follower")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.black)
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 4)
                }
                .frame(height: 44)
            }
        }
        .frame(height: statusBarHeight + 44)
    }

    // MARK: - Tab row

    private var tabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                TabItem(
                    title: formatCount(followerCount) + " " + String(localized: "ig.stat.followers"),
                    isSelected: selectedTab == 0
                ) { selectedTab = 0 }
                TabItem(
                    title: formatCount(followingCount) + " " + String(localized: "ig.stat.following"),
                    isSelected: selectedTab == 1
                ) { selectedTab = 1 }
                TabItem(title: String(localized: "followers.tab.subscriptions"), isSelected: false) {}
                TabItem(title: String(localized: "followers.tab.more"), isSelected: false) {}
            }
        }
        .background(Color.white)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(white: 0.45))
            TextField(String(localized: "followers.search"), text: $searchQuery)
                .font(.system(size: 14))
                .foregroundColor(.black)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.55))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.93))
        .cornerRadius(10)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    // MARK: - Followers list

    private var followersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if searchQuery.isEmpty {
                    sectionHeader(String(localized: "followers.section.all"))
                }

                ForEach(searchQuery.isEmpty ? followers : filteredFollowers) { follower in
                    FollowerRow(
                        follower: follower,
                        rank: selectionRank(of: follower),
                        onAvatarTap: { toggle(follower) },
                        onRowTap: { profileTarget = follower }
                    )
                    Divider()
                        .padding(.leading, 82)
                }
            }
        }
        .background(Color.white)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    // MARK: - Load

    private func loadFollowers() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await instagram.getRecentFollowers(count: 50)
            await MainActor.run {
                followers = result
                isLoading = false
                // If baseline exists, pre-select new followers automatically
                if dateForce.hasBaseline {
                    let newOnes = dateForce.newFollowers(from: result)
                    if !newOnes.isEmpty {
                        selectedIds = newOnes.map { $0.userId }
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Helpers

    private var statusBarHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 47
    }

    private func formatCount(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .black : Color(white: 0.5))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                Rectangle()
                    .fill(isSelected ? Color.black : Color.clear)
                    .frame(height: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Follower Row

private struct FollowerRow: View {
    let follower: InstagramFollower
    /// Non-nil = this follower is selected; value is their 1-based selection rank.
    var rank: Int? = nil
    /// Tap on the avatar → toggle secret selection ring.
    var onAvatarTap: (() -> Void)? = nil
    /// Tap on the rest of the row → open profile.
    var onRowTap: (() -> Void)? = nil

    private var isSelected: Bool { rank != nil }

    private var showFollowBack: Bool {
        !isSelected && abs(follower.userId.hashValue) % 10 < 6
    }

    private var storyGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(hex: "F58529"), Color(hex: "FEDA77"),
                Color(hex: "DD2A7B"), Color(hex: "8134AF"),
                Color(hex: "515BD4"), Color(hex: "F58529")
            ]),
            center: .center
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar: tap = toggle selection ring (secret gesture)
            avatarContainer
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
                .onTapGesture { onAvatarTap?() }
                .contentShape(Circle())

            // Profile info + button: tap = open profile
            Button(action: { onRowTap?() }) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(follower.username)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                                .lineLimit(1)

                            if !isSelected && showFollowBack {
                                Text("·")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(white: 0.5))
                                Text("followers.follow_back")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.0, green: 0.47, blue: 1.0))
                                    .lineLimit(1)
                            }
                        }

                        if !follower.fullName.isEmpty {
                            Text(follower.fullName)
                                .font(.system(size: 13))
                                .foregroundColor(Color(white: 0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("followers.remove_btn")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(white: 0.93))
                        .cornerRadius(8)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    // MARK: - Avatar with story ring

    private var avatarContainer: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                // Gradient ring (visible when selected)
                Circle()
                    .stroke(storyGradient, lineWidth: isSelected ? 2.5 : 0)
                    .frame(width: 56, height: 56)

                // White gap between ring and avatar
                Circle()
                    .fill(Color.white)
                    .frame(width: 52, height: 52)
                    .opacity(isSelected ? 1 : 0)

                avatarImage
                    .frame(width: isSelected ? 48 : 50, height: isSelected ? 48 : 50)
                    .clipShape(Circle())
            }
            .frame(width: 56, height: 56)

            // Rank badge (blue — looks like a normal notification badge)
            if let rank = rank {
                Text("\(rank)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: "0095F6")))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 56, height: 56)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlStr = follower.profilePicURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(white: 0.88))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(white: 0.65))
            )
    }
}

// MARK: - Follower Profile Sheet

/// Loads and presents a follower's Instagram profile in full screen.
private struct FollowerProfileSheet: View {
    let follower: InstagramFollower
    /// Already-loaded profile from the parent's in-session cache (skips API call).
    var cachedProfile: InstagramProfile? = nil
    var onProfileLoaded: ((InstagramProfile) -> Void)? = nil
    let onClose: () -> Void

    @State private var profile: InstagramProfile? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var pendingOCR: String? = nil

    private var instagram: InstagramService { InstagramService.shared }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let profile {
                InstagramProfileView(
                    profile: profile,
                    cachedImages: $cachedImages,
                    onRefresh: { Task { await reload() } },
                    onAsyncRefresh: { await reload() },
                    onPlusPress: {},
                    pendingOCRWord: $pendingOCR
                )
            } else if isLoading {
                loadingPlaceholder
            } else {
                errorPlaceholder
            }

            // Back button overlay
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    )
            }
            .padding(.top, safeAreaTop + 8)
            .padding(.leading, 12)
        }
        .task { await loadProfile() }
    }

    // MARK: - Placeholders

    private var loadingPlaceholder: some View {
        Color.white.ignoresSafeArea()
            .overlay(
                VStack(spacing: 12) {
                    avatarPreview
                    Text("@\(follower.username)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    ProgressView().tint(.black)
                }
            )
    }

    private var errorPlaceholder: some View {
        Color.white.ignoresSafeArea()
            .overlay(
                VStack(spacing: 14) {
                    avatarPreview
                    Text("@\(follower.username)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    Text(errorMessage ?? "No se pudo cargar el perfil")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        Task {
                            // Wait 2s before retry to respect Instagram rate limit
                            isLoading = true
                            errorMessage = nil
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            await fetchFromAPI()
                        }
                    } label: {
                        Text("Reintentar")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 9)
                            .background(Color.black)
                            .cornerRadius(20)
                    }
                }
            )
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let urlStr = follower.profilePicURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                        .frame(width: 72, height: 72).clipShape(Circle())
                } else {
                    Circle().fill(Color(white: 0.88)).frame(width: 72, height: 72)
                }
            }
        } else {
            Circle().fill(Color(white: 0.88)).frame(width: 72, height: 72)
        }
    }

    // MARK: - Load

    @MainActor
    private func loadProfile() async {
        // Use parent cache if available — no API call needed
        if let cached = cachedProfile {
            profile = cached
            isLoading = false
            return
        }
        await fetchFromAPI()
    }

    @MainActor
    private func reload() async {
        await fetchFromAPI()
    }

    @MainActor
    private func fetchFromAPI() async {
        isLoading = true
        errorMessage = nil

        // Anti-bot: if session is currently challenged, don't make another API call.
        // Show a friendly message instead and let the user retry manually.
        if instagram.isSessionChallenged {
            errorMessage = "Instagram está limitando las consultas ahora mismo.\nEspera unos segundos y reintenta."
            isLoading = false
            return
        }

        // Anti-bot: small random delay (0.5–1.5 s) before fetching profile to avoid
        // back-to-back GET /users/{id}/info/ calls when opening profiles in quick succession.
        try? await Task.sleep(nanoseconds: UInt64.random(in: 500_000_000...1_500_000_000))

        do {
            guard let p = try await instagram.getProfileInfo(userId: follower.userId) else {
                errorMessage = "Instagram no devolvió datos para este perfil."
                isLoading = false
                return
            }
            profile = p
            onProfileLoaded?(p)
            // Pre-load avatar into cache
            if let url = URL(string: p.profilePicURL),
               let (data, _) = try? await URLSession.shared.data(from: url),
               let img = UIImage(data: data) {
                cachedImages[p.profilePicURL] = img
            }
        } catch {
            let msg = error.localizedDescription
            if msg.contains("429") || msg.contains("Rate") || msg.contains("blocked") || msg.contains("spam") || msg.contains("challenge") {
                errorMessage = "Instagram ha limitado las consultas temporalmente.\nEspera unos segundos y reintenta."
            } else {
                errorMessage = "No se pudo cargar el perfil.\n\(msg)"
            }
        }
        isLoading = false
    }

    private var safeAreaTop: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 47
    }
}
