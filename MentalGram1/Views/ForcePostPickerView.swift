import SwiftUI

/// Lets the magician search any Instagram profile, browse ALL their posts
/// (with automatic pagination), and select one to force during the trick.
/// Pass `editingUserId` when changing an existing entry (pre-fills username).
struct ForcePostPickerView: View {
    var editingUserId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = ForcePostSettings.shared
    @ObservedObject private var instagram = InstagramService.shared
    @ObservedObject private var uploadManager = UploadManager.shared

    @State private var usernameInput: String = ""
    @State private var posts: [InstagramMediaItem] = []
    @State private var cachedImages: [String: UIImage] = [:]
    @State private var isSearching = false          // initial search in progress
    @State private var isLoadingMore = false        // pagination in progress
    @State private var hasMorePages = false
    @State private var nextMaxId: String? = nil
    @State private var errorMessage: String?
    @State private var searchedUsername: String = ""
    @State private var searchedUserId: String = ""
    @State private var lastSearchTime: Date = .distantPast
    @State private var lastPageLoadTime: Date = .distantPast
    @State private var showingRelogin = false

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    private let pageSize = 36
    private let initialPrefetchTarget = 144
    private let minPageGap: TimeInterval = 3.5
    private let screenBackground = Color.black
    private let panelBackground = Color(red: 0.07, green: 0.07, blue: 0.08)
    private let fieldBackground = Color(red: 0.11, green: 0.11, blue: 0.13)
    private let accentBlue = Color(red: 0.10, green: 0.45, blue: 1.0)
    private var isUploadBusy: Bool {
        uploadManager.activeTask != nil || uploadManager.isUploading || uploadManager.isActive || uploadManager.isSyncArchiveActive
    }
    private let uploadBusyMessage = "Upload in progress. Wait until the upload pauses or finishes before loading Instagram posts."

    var body: some View {
        NavigationView {
            ZStack {
                screenBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                    playingCardProfileTip
                    if isUploadBusy {
                        uploadBusyBanner
                    }
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.38, blue: 0.38))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                    contentArea
                }
            }
            .navigationTitle(editingUserId != nil ? "Change Post" : "Add Force Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(accentBlue)
                }
                if let uid = editingUserId, settings.entry(forUserId: uid) != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Remove", role: .destructive) {
                            settings.clearEntry(userId: uid)
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                // Pre-fill username when editing an existing entry
                if let uid = editingUserId,
                   let entry = settings.entry(forUserId: uid) {
                    usernameInput = entry.username
                }
            }
            .sheet(isPresented: $showingRelogin) {
                ReloginSheet(isPresented: $showingRelogin)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("", text: $usernameInput, prompt: Text("Instagram username").foregroundColor(.white.opacity(0.38)))
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .tint(accentBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(fieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(usernameInput.isEmpty ? Color.white.opacity(0.12) : accentBlue.opacity(0.65), lineWidth: 1)
                )
                .cornerRadius(12)
                .onSubmit { searchPosts() }

            Button(action: searchPosts) {
                if isSearching {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 46, height: 46)
                        .background(accentBlue.opacity(0.55))
                        .cornerRadius(12)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(accentBlue)
                        .cornerRadius(12)
                }
            }
            .disabled(isSearching || usernameInput.trimmingCharacters(in: .whitespaces).isEmpty || instagram.isLocked || isUploadBusy)
            .opacity(isSearching || usernameInput.trimmingCharacters(in: .whitespaces).isEmpty || instagram.isLocked || isUploadBusy ? 0.55 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var uploadBusyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.top, 1)
            Text(uploadBusyMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var playingCardProfileTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.22))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color(red: 1.0, green: 0.82, blue: 0.22).opacity(0.16)))

            Text("force.post.picker.playingcard.tip")
                .font(.system(size: 13, weight: .medium))
                .lineSpacing(2)
                .foregroundColor(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.72, blue: 0.10).opacity(0.16),
                    panelBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(red: 1.0, green: 0.82, blue: 0.22).opacity(0.28), lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if posts.isEmpty && !isSearching {
            emptyState
        } else if posts.isEmpty && isSearching {
            Spacer()
            ProgressView("Searching…")
                .tint(.white)
                .foregroundColor(.white.opacity(0.78))
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Header with post count
                    HStack {
                        Text("@\(searchedUsername) · \(posts.count)\(hasMorePages ? "+" : "") posts")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.60))
                        Spacer()
                        if isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(posts) { post in
                            PostPickerCell(
                                post: post,
                                image: cachedImages[post.imageURL],
                                isSelected: isPostSelected(post),
                                onTap: { select(post) }
                            )
                            .onAppear { loadMoreIfNeeded(currentPost: post) }
                        }
                    }

                    // Load more button
                    if hasMorePages {
                        Button(action: loadMorePosts) {
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            } else {
                                Text("Load more posts")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .disabled(isLoadingMore || isUploadBusy)
                        .background(panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(screenBackground)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.34))
            Text(searchedUsername.isEmpty
                 ? "Search a username to see their posts"
                 : "No posts found for @\(searchedUsername)")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(screenBackground)
    }

    // MARK: - Search

    private func searchPosts() {
        let username = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !username.isEmpty else { return }
        guard !isUploadBusy else {
            errorMessage = uploadBusyMessage
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastSearchTime) < 2 {
            let remaining = Int(2 - now.timeIntervalSince(lastSearchTime)) + 1
            errorMessage = "Wait \(remaining)s before searching again"
            return
        }
        guard !instagram.isLocked else {
            errorMessage = "Service temporarily unavailable. Try again later."
            return
        }

        // Session expired — prompt re-login directly
        if instagram.isSessionExpired {
            showingRelogin = true
            return
        }

        lastSearchTime = now
        errorMessage = nil
        isSearching = true
        posts = []
        cachedImages = [:]
        nextMaxId = nil
        hasMorePages = false
        searchedUsername = username

        Task {
            do {
                try await instagram.waitForNetworkStability()

                guard let results = try? await instagram.searchUsers(query: username),
                      let match = results.first(where: { $0.username.lowercased() == username })
                                  ?? results.first else {
                    await MainActor.run {
                        errorMessage = "Profile '@\(username)' not found"
                        isSearching = false
                    }
                    return
                }

                let userId = match.userId
                await MainActor.run { searchedUserId = userId }

                let pause = UInt64.random(in: 450_000_000...900_000_000)
                try await Task.sleep(nanoseconds: pause)
                guard await MainActor.run(body: { !isUploadBusy }) else {
                    await MainActor.run {
                        isSearching = false
                        errorMessage = uploadBusyMessage
                    }
                    return
                }

                let (fetched, nextId) = try await instagram.getUserMediaItems(userId: userId, amount: pageSize)
                let uniqueFetched = uniquePosts(fetched)
                await MainActor.run {
                    posts = uniqueFetched
                    nextMaxId = nextId
                    hasMorePages = nextId != nil
                    isSearching = false
                }

                await downloadThumbnails(for: uniqueFetched)
                await prefetchInitialPagesIfNeeded()

            } catch {
                let msg = "\(error)"
                let isPrivate = msg.lowercased().contains("not authorized") || msg.lowercased().contains("not found")
                await MainActor.run {
                    isSearching = false
                    if instagram.isSessionExpired {
                        showingRelogin = true
                    } else {
                        errorMessage = isPrivate
                            ? "@\(username) is a private account. You need to follow them first."
                            : "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Load more pages

    private func loadMorePosts() {
        guard let maxId = nextMaxId, !searchedUserId.isEmpty else { return }
        guard !isLoadingMore else { return }
        guard !isUploadBusy else {
            errorMessage = uploadBusyMessage
            return
        }
        guard !instagram.isLocked else {
            errorMessage = "Service temporarily unavailable. Try again later."
            return
        }
        if instagram.isSessionExpired {
            showingRelogin = true
            return
        }
        let elapsed = Date().timeIntervalSince(lastPageLoadTime)
        let waitBeforeRequest = max(0, minPageGap - elapsed)
        isLoadingMore = true

        Task {
            do {
                if waitBeforeRequest > 0 {
                    try await Task.sleep(nanoseconds: UInt64(waitBeforeRequest * 1_000_000_000))
                }
                let pause = UInt64.random(in: 1_200_000_000...2_400_000_000)
                try await Task.sleep(nanoseconds: pause)
                guard await MainActor.run(body: { !isUploadBusy }) else {
                    await MainActor.run {
                        isLoadingMore = false
                        errorMessage = uploadBusyMessage
                    }
                    return
                }
                await MainActor.run { lastPageLoadTime = Date() }

                let (fetched, nextId) = try await instagram.getUserMediaItems(userId: searchedUserId, amount: pageSize, maxId: maxId)
                let existingKeys = await MainActor.run {
                    Set(posts.map { $0.mediaId.isEmpty ? $0.imageURL : $0.mediaId })
                }
                let fresh = fetched.filter {
                    !existingKeys.contains($0.mediaId.isEmpty ? $0.imageURL : $0.mediaId)
                }
                let uniqueFresh = uniquePosts(fresh)
                await MainActor.run {
                    posts.append(contentsOf: uniqueFresh)
                    nextMaxId = nextId
                    hasMorePages = nextId != nil && nextId != maxId
                    isLoadingMore = false
                }
                await downloadThumbnails(for: uniqueFresh)

            } catch {
                await MainActor.run {
                    isLoadingMore = false
                    if instagram.isSessionExpired {
                        showingRelogin = true
                    }
                }
                print("⚠️ [FORCE POST] Pagination error: \(error)")
            }
        }
    }

    private func loadMoreIfNeeded(currentPost: InstagramMediaItem) {
        guard hasMorePages, !isLoadingMore else { return }
        let currentKey = currentPost.mediaId.isEmpty ? currentPost.imageURL : currentPost.mediaId
        guard let index = posts.firstIndex(where: {
            ($0.mediaId.isEmpty ? $0.imageURL : $0.mediaId) == currentKey
        }) else { return }
        let threshold = max(1, Int(Double(posts.count) * 0.82))
        if index >= threshold {
            loadMorePosts()
        }
    }

    private func prefetchInitialPagesIfNeeded() async {
        while true {
            let shouldContinue = await MainActor.run {
                hasMorePages && !isLoadingMore && !searchedUserId.isEmpty && posts.count < initialPrefetchTarget && !isUploadBusy
            }
            guard shouldContinue else { return }

            await MainActor.run { isLoadingMore = true }
            do {
                try await Task.sleep(nanoseconds: 700_000_000)
                guard let cursor = await MainActor.run(body: { nextMaxId }) else {
                    await MainActor.run { isLoadingMore = false }
                    return
                }
                let elapsed = await MainActor.run { Date().timeIntervalSince(lastPageLoadTime) }
                let waitBeforeRequest = max(0, minPageGap - elapsed)
                if waitBeforeRequest > 0 {
                    try await Task.sleep(nanoseconds: UInt64(waitBeforeRequest * 1_000_000_000))
                }
                let pause = UInt64.random(in: 1_200_000_000...2_400_000_000)
                try await Task.sleep(nanoseconds: pause)
                guard await MainActor.run(body: { !isUploadBusy }) else {
                    await MainActor.run {
                        isLoadingMore = false
                        errorMessage = uploadBusyMessage
                    }
                    return
                }
                await MainActor.run { lastPageLoadTime = Date() }

                let (fetched, nextId) = try await instagram.getUserMediaItems(userId: searchedUserId, amount: pageSize, maxId: cursor)
                let existingKeys = await MainActor.run {
                    Set(posts.map { $0.mediaId.isEmpty ? $0.imageURL : $0.mediaId })
                }
                let uniqueFresh = uniquePosts(fetched.filter {
                    !existingKeys.contains($0.mediaId.isEmpty ? $0.imageURL : $0.mediaId)
                })

                await MainActor.run {
                    posts.append(contentsOf: uniqueFresh)
                    nextMaxId = nextId
                    hasMorePages = nextId != nil && nextId != cursor
                    isLoadingMore = false
                }
                await downloadThumbnails(for: uniqueFresh)
            } catch {
                await MainActor.run { isLoadingMore = false }
                print("⚠️ [FORCE POST] Initial prefetch error: \(error)")
                return
            }
        }
    }

    // MARK: - Helpers

    private func isPostSelected(_ post: InstagramMediaItem) -> Bool {
        // When editing an existing entry, match against that entry's mediaId.
        // When adding new, match against any existing entry for the searched user.
        if let uid = editingUserId {
            return settings.entry(forUserId: uid)?.mediaId == post.mediaId
        }
        return settings.entry(forUserId: searchedUserId)?.mediaId == post.mediaId
    }

    private func select(_ post: InstagramMediaItem) {
        settings.selectPost(item: post, username: searchedUsername, userId: searchedUserId)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }

    private func downloadThumbnails(for items: [InstagramMediaItem]) async {
        for item in items {
            guard cachedImages[item.imageURL] == nil else { continue }
            if let img = await downloadImage(from: item.imageURL) {
                await MainActor.run { cachedImages[item.imageURL] = img }
            }
        }
    }

    private func downloadImage(from urlString: String) async -> UIImage? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private func uniquePosts(_ items: [InstagramMediaItem]) -> [InstagramMediaItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = item.mediaId.isEmpty ? item.imageURL : item.mediaId
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Post cell

private struct PostPickerCell: View {
    let post: InstagramMediaItem
    let image: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(1, contentMode: .fill)
                    .overlay(ProgressView().scaleEffect(0.7))
            }

            if isSelected {
                Color.blue.opacity(0.35)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
