import SwiftUI

// MARK: - Followers List View (fake Instagram UI)

enum FollowersListMode {
    case followers
    case following
}

struct FollowersListView: View {
    let username: String
    let followerCount: Int
    let followingCount: Int
    let onClose: () -> Void
    var mode: FollowersListMode = .followers

    @ObservedObject private var dateForce = DateForceSettings.shared

    @State private var followers: [InstagramFollower] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedTab: Int
    @State private var activeMode: FollowersListMode
    @State private var searchQuery = ""

    /// IDs seleccionados con tap en avatar — array ordenado para preservar orden de selección.
    /// Posición importa: primera mitad → grupo fecha, segunda mitad → grupo hora.
    @State private var localSelectedIds: [String] = []

    // Profile detail (inline slide)
    @State private var loadingProfileUserId: String? = nil
    @State private var openedProfile: InstagramProfile? = nil
    @State private var showingProfile = false
    /// Profile IDs that returned a non-retryable error (e.g. HTTP 400 — private
    /// or deleted account). Skip these to avoid wasting API calls on re-taps.
    @State private var failedProfileIds: Set<String> = []
    /// Timestamp of the last profile open, used to enforce a short cooldown
    /// between consecutive profile opens from the followers list.
    @State private var lastProfileOpenAt: Date = .distantPast
    /// Active profile-load task, kept so we can cancel it if the user
    /// navigates away before the profile finishes loading.
    @State private var profileLoadTask: Task<Void, Never>? = nil

    @ObservedObject private var instagram = InstagramService.shared

    init(username: String,
         followerCount: Int,
         followingCount: Int,
         onClose: @escaping () -> Void,
         mode: FollowersListMode = .followers) {
        self.username = username
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.onClose = onClose
        self.mode = mode
        _selectedTab = State(initialValue: mode == .followers ? 0 : 1)
        _activeMode = State(initialValue: mode)
    }

    private var filteredFollowers: [InstagramFollower] {
        guard !searchQuery.isEmpty else { return followers }
        let q = searchQuery.lowercased()
        return followers.filter {
            $0.username.lowercased().contains(q) ||
            $0.fullName.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                navBar
                // Hint bar when Date Force is enabled
                if dateForce.isEnabled {
                    dateForceBanner
                }
                tabRow
                searchBar
                Divider()
                if isLoading {
                    Spacer()
                    ProgressView().tint(Color(UIColor.label))
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
            .background(Color(UIColor.igPageBackground))
            .ignoresSafeArea(edges: .top)

            // Loading overlay while fetching profile
            if loadingProfileUserId != nil {
                Color.black.opacity(0.08).ignoresSafeArea()
                ProgressView().tint(Color(UIColor.label))
            }

            // Inline profile view — slides in from right
            if showingProfile, let profile = openedProfile {
                UserProfileView(profile: profile, onClose: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showingProfile = false
                    }
                })
                // Force SwiftUI to discard @State and re-init when the profile changes.
                .id(profile.userId)
                .transition(.move(edge: .trailing))
                .zIndex(10)
            }
        }
        .task { await loadUsers() }
        .onDisappear {
            // Cancel any in-flight profile load when the view is dismissed.
            // Without this, a profile that started loading right before the user
            // navigated away would continue running in the background and fire
            // concurrent API calls (e.g. /friendships/{uid}/followers/) alongside
            // the next operation (S&A), which is what triggered the May 17 403.
            profileLoadTask?.cancel()
            profileLoadTask = nil
        }
        .onChange(of: selectedTab) { newTab in
            guard newTab == 0 || newTab == 1 else { return }
            let newMode: FollowersListMode = newTab == 0 ? .followers : .following
            guard newMode != activeMode else { return }
            activeMode = newMode
            searchQuery = ""
            Task { await loadUsers() }
        }
    }

    // MARK: - Date Force banner

    private var dateForceBanner: some View {
        EmptyView()
    }

    // MARK: - Open profile (inline slide, same flow as Explore)

    private func openProfile(_ follower: InstagramFollower) {
        guard loadingProfileUserId == nil else { return }

        // Skip profiles that already failed with a non-retryable error this session
        // (e.g. HTTP 400 — private or deleted account). Fire a haptic so the user
        // gets tactile feedback and understands the profile can't be opened.
        guard !failedProfileIds.contains(follower.userId) else {
            print("⏭️ [FOLLOWERS] Skipping @\(follower.username) — failed previously this session")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Budget guard: block profile opens when only a few actions remain in the
        // hourly budget. Cached profiles are always allowed (they make no API calls).
        // Threshold: 8 remaining leaves enough headroom for S&A or other essentials.
        let rateCheck = instagram.checkRateLimit()
        if rateCheck.remaining < 8,
           VisitedProfileCacheService.shared.loadProfile(userId: follower.userId) == nil {
            print("⚠️ [FOLLOWERS] Profile open blocked — only \(rateCheck.remaining) actions remaining this hour")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }

        // Cooldown: prevent rapid consecutive opens (e.g. accidental double-taps or
        // quick browsing). Each new profile costs 3-4 API calls; 3 seconds between
        // opens is imperceptible to the user but prevents burst patterns.
        let sinceLastOpen = Date().timeIntervalSince(lastProfileOpenAt)
        guard sinceLastOpen >= 3.0 else {
            print("⏳ [FOLLOWERS] Profile open throttled — \(String(format: "%.1f", sinceLastOpen))s since last open (min 3s)")
            return
        }

        // Check visited-profile cache first — avoids 3-4 API calls when the user
        // opens the same follower repeatedly (e.g. during Counter Glitch rehearsal).
        if let cached = VisitedProfileCacheService.shared.loadProfile(userId: follower.userId) {
            print("📦 [FOLLOWERS] Opened @\(cached.username) from visited cache — no API call")
            lastProfileOpenAt = Date()
            openedProfile = cached
            withAnimation(.easeInOut(duration: 0.22)) { showingProfile = true }
            return
        }

        lastProfileOpenAt = Date()
        loadingProfileUserId = follower.userId
        profileLoadTask?.cancel()
        profileLoadTask = Task {
            do {
                let profile = try await instagram.getProfileInfo(
                    userId: follower.userId,
                    usernameHint: follower.username,
                    fullNameHint: follower.fullName,
                    profilePicURLHint: follower.profilePicURL
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    loadingProfileUserId = nil
                    if let profile {
                        openedProfile = profile
                        withAnimation(.easeInOut(duration: 0.22)) { showingProfile = true }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    loadingProfileUserId = nil
                    // Mark as failed so retaps don't waste more API calls.
                    // Only cache the failure for non-network errors (HTTP 400 = account
                    // not accessible); network timeouts should still be retryable.
                    let desc = error.localizedDescription.lowercased()
                    let isHardFailure = desc.contains("400") || desc.contains("not found") || desc.contains("forbidden")
                    if isHardFailure {
                        failedProfileIds.insert(follower.userId)
                        print("❌ [FOLLOWERS] @\(follower.username) marked as failed (hard error) — won't retry")
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            }
        }
    }

    /// Confirma la selección ordenada en DateForce y cierra la lista.
    /// El orden del array determina el grupo: primera mitad → fecha, segunda mitad → hora.
    private func commitAndClose() {
        if dateForce.isEnabled && !localSelectedIds.isEmpty {
            dateForce.selectedFollowerIds = localSelectedIds   // array ordenado
            let half = localSelectedIds.count / 2
            print("📋 [DATE FORCE] Confirmados \(localSelectedIds.count) espectadores — \(half) para fecha, \(localSelectedIds.count - half) para hora")
        }
        onClose()
    }

    // MARK: - Nav bar

    private var navBar: some View {
        ZStack {
            Color(UIColor.igPageBackground)
            VStack(spacing: 0) {
                Color.clear.frame(height: statusBarHeight)
                HStack {
                    Button(action: commitAndClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(UIColor.label))
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text(username)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(UIColor.label))
                    Spacer()
                    ZStack(alignment: .topTrailing) {
                        Image("instagram_add_follower")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color(UIColor.label))
                            .frame(width: 24, height: 24)
                        // Budget dot: only visible to magician, only when budget is low.
                        // A spectator glancing at the header won't notice an 8px dot.
                        budgetDot
                    }
                    .frame(width: 44, height: 44)
                    .padding(.trailing, 4)
                }
                .frame(height: 44)
            }
        }
        .frame(height: statusBarHeight + 44)
    }

    /// Small red dot overlaid on the nav bar icon when fewer than 8 API actions
    /// remain in the hourly budget. Invisible when budget is healthy.
    @ViewBuilder
    private var budgetDot: some View {
        if instagram.checkRateLimit().remaining < 8 {
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color(UIColor.igPageBackground), lineWidth: 1.5))
                .offset(x: 3, y: -3)
                .transition(.opacity)
        }
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
        .background(Color(UIColor.igPageBackground))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(UIColor.secondaryLabel))

            TextField(String(localized: "followers.search"), text: $searchQuery)
                .font(.system(size: 14))
                .foregroundColor(Color(UIColor.label))
                .autocapitalization(.none)
                .disableAutocorrection(true)

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(UIColor.secondaryLabel))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.igButtonFill))
        .cornerRadius(10)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(UIColor.igPageBackground))
    }

    // MARK: - List

    private var sectionHeader: String {
        activeMode == .followers
            ? String(localized: "followers.section.all")
            : String(localized: "followers.section.following")
    }

    private var followersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if searchQuery.isEmpty {
                    Text(sectionHeader)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(UIColor.label))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                }
                ForEach(filteredFollowers) { follower in
                    let orderIdx = localSelectedIds.firstIndex(of: follower.userId)
                    FollowerRow(
                        follower: follower,
                        mode: activeMode,
                        isDateForceSelected: orderIdx != nil,
                        dateForceEnabled: dateForce.isEnabled,
                        selectionOrder: orderIdx.map { $0 + 1 },
                        isFailed: failedProfileIds.contains(follower.userId),
                        onAvatarTap: {
                            if dateForce.isEnabled {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if let idx = localSelectedIds.firstIndex(of: follower.userId) {
                                        // Deseleccionar — eliminar del cache también
                                        localSelectedIds.remove(at: idx)
                                        dateForce.preloadedProfiles.removeValue(forKey: follower.userId)
                                    } else {
                                        // Seleccionar — añadir al array (orden preservado)
                                        localSelectedIds.append(follower.userId)
                                        // Pre-cargar perfil completo en background
                                        Task {
                                            if let p = try? await instagram.getProfileInfo(
                                                userId: follower.userId,
                                                usernameHint: follower.username,
                                                fullNameHint: follower.fullName,
                                                profilePicURLHint: follower.profilePicURL
                                            ) {
                                                await MainActor.run {
                                                    dateForce.preloadedProfiles[follower.userId] = (
                                                        username: p.username,
                                                        userId: p.userId,
                                                        profilePicURL: p.profilePicURL,
                                                        followerCount: p.followerCount,
                                                        followingCount: p.followingCount
                                                    )
                                                    print("✅ [PRELOAD] @\(p.username) seguidores=\(p.followerCount) seguidos=\(p.followingCount)")
                                                }
                                            }
                                        }
                                    }
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else {
                                openProfile(follower)
                            }
                        },
                        onRowTap: { openProfile(follower) }
                    )
                    Divider().padding(.leading, 76)
                }
            }
        }
        .background(Color(UIColor.igPageBackground))
    }

    // MARK: - Load

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = activeMode == .followers
                ? try await instagram.getRecentFollowers(count: 50)
                : try await instagram.getRecentFollowing(count: 50)
            await MainActor.run {
                followers = result
                isLoading = false
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
                    .foregroundColor(isSelected ? Color(UIColor.label) : Color(UIColor.secondaryLabel))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                Rectangle()
                    .fill(isSelected ? Color(UIColor.label) : Color.clear)
                    .frame(height: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Follower Row

private struct FollowerRow: View {
    let follower: InstagramFollower
    let mode: FollowersListMode
    let isDateForceSelected: Bool
    let dateForceEnabled: Bool
    /// Posición de selección (1-based) cuando está seleccionado, nil si no lo está
    let selectionOrder: Int?
    /// True when the profile returned a hard error (e.g. HTTP 400 not authorized).
    /// The row dims and shows a lock icon to signal the profile cannot be opened.
    var isFailed: Bool = false
    let onAvatarTap: () -> Void
    let onRowTap: () -> Void

    // Show "Follow too" in blue for private accounts — this is the real signal:
    // private accounts' follower/following lists are inaccessible, so the magician
    // knows at a glance which spectators cannot be used for Date Force.
    private var showFollowBack: Bool {
        !isFailed && mode == .followers && follower.isPrivate
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar — tap target separado
            avatarView
                .frame(width: 50, height: 50)
                .contentShape(Circle())
                .onTapGesture { onAvatarTap() }

            // Resto de la fila — abre el perfil
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(follower.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isFailed ? Color(UIColor.tertiaryLabel) : Color(UIColor.label))
                            .lineLimit(1)

                        if isFailed {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                        } else if showFollowBack {
                            Text("·")
                                .font(.system(size: 12))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                            Text(String(localized: "followers.follow_back"))
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.0, green: 0.47, blue: 1.0))
                                .lineLimit(1)
                        }
                    }

                    if !follower.fullName.isEmpty {
                        Text(follower.fullName)
                            .font(.system(size: 13))
                            .foregroundColor(isFailed ? Color(UIColor.tertiaryLabel) : Color(UIColor.secondaryLabel))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(localized: mode == .followers ? "followers.remove_btn" : "followers.following_btn"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isFailed ? Color(UIColor.tertiaryLabel) : Color(UIColor.label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(UIColor.igButtonFill))
                    .cornerRadius(8)
            }
            .contentShape(Rectangle())
            .onTapGesture { onRowTap() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(UIColor.igPageBackground))
        .opacity(isFailed ? 0.55 : 1.0)
    }

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            Group {
                if let urlStr = follower.profilePicURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: avatarPlaceholder
                        }
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        isDateForceSelected ? Color(hex: "0095F6") : Color.clear,
                        lineWidth: isDateForceSelected ? 3 : 0
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDateForceSelected)
            )

            // Badge con número de orden de selección
            if let order = selectionOrder {
                ZStack {
                    Circle()
                        .fill(Color(hex: "0095F6"))
                        .frame(width: 19, height: 19)
                    Text("\(order)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .offset(x: 17, y: 17)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(UIColor.systemGray4))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            )
    }
}
