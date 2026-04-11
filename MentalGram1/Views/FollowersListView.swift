import SwiftUI

// MARK: - Followers List View (fake Instagram UI)

struct FollowersListView: View {
    let username: String
    let followerCount: Int
    let followingCount: Int
    let onClose: () -> Void

    @State private var followers: [InstagramFollower] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedTab = 0
    @State private var searchQuery = ""

    private var instagram: InstagramService { InstagramService.shared }

    private var filteredFollowers: [InstagramFollower] {
        guard !searchQuery.isEmpty else { return followers }
        let q = searchQuery.lowercased()
        return followers.filter {
            $0.username.lowercased().contains(q) ||
            $0.fullName.lowercased().contains(q)
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
                ProgressView()
                    .tint(.black)
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
    }

    // MARK: - Nav bar

    private var navBar: some View {
        ZStack {
            Color.white
            VStack(spacing: 0) {
                Color.clear.frame(height: statusBarHeight)

                HStack {
                    Button(action: onClose) {
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

    // MARK: - List

    private var followersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if searchQuery.isEmpty {
                    Text("followers.section.all")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                }

                ForEach(filteredFollowers) { follower in
                    FollowerRow(follower: follower)
                    Divider()
                        .padding(.leading, 76)
                }
            }
        }
        .background(Color.white)
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

    // Deterministic "Seguir también" for ~55% of followers (based on userId hash)
    private var showFollowBack: Bool {
        abs(follower.userId.hashValue) % 10 < 6
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
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
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            // Text info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(follower.username)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    if showFollowBack {
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

            // "Quitar" button (decorative)
            Text("followers.remove_btn")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(white: 0.93))
                .cornerRadius(8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white)
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
