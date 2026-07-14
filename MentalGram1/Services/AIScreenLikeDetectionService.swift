import Foundation
import Combine
import UIKit

struct AIScreenLikeDetectionResult {
    let profile: InstagramProfile
    let mediaItems: [InstagramMediaItem]
    let matchedItem: InstagramMediaItem
}

enum AIScreenLikeDetectionError: LocalizedError {
    case noLatestFollower
    case privateProfile(String)
    case noPosts(String)
    case noSnapshot
    case noLikeIncrease
    case multipleLikeIncreases
    case likerNotConfirmed(String)

    var errorDescription: String? {
        switch self {
        case .noLatestFollower:
            return "No latest follower was found."
        case .privateProfile(let username):
            return "@\(username) is private or not accessible."
        case .noPosts(let username):
            return "@\(username) has no accessible posts."
        case .noSnapshot:
            return "Likes mode is not armed."
        case .noLikeIncrease:
            return "No post increased by one like."
        case .multipleLikeIncreases:
            return "More than one post increased in likes."
        case .likerNotConfirmed(let username):
            return "@\(username) was not found in the increased posts' likes."
        }
    }
}

final class AIScreenLikeDetectionService: ObservableObject {
    static let shared = AIScreenLikeDetectionService()

    @Published private(set) var armedUsername: String = ""
    @Published private(set) var armedPostCount: Int = 0
    @Published private(set) var armedAt: Date? = nil

    private struct Snapshot: Codable {
        let userId: String
        let username: String
        let capturedAt: Date
        let countsByMediaId: [String: Int]
        let expectedLikerUserId: String?
        let expectedLikerUsername: String?
    }

    private let snapshotKey = "ai_screen_like_detection_snapshot"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        if let snapshot = loadSnapshot() {
            armedUsername = snapshot.username
            armedPostCount = snapshot.countsByMediaId.count
            armedAt = snapshot.capturedAt
        }
    }

    @discardableResult
    func armLatestFollower(limit: Int) async throws -> String {
        guard let follower = try await InstagramService.shared.getLatestFollower() else {
            throw AIScreenLikeDetectionError.noLatestFollower
        }

        let profile = try await loadProfile(userId: follower.userId, username: follower.username)
        return try await armProfile(profile, limit: limit)
    }

    @discardableResult
    func armTargetUsernameWithLatestFollower(_ username: String, limit: Int) async throws -> String {
        guard let follower = try await InstagramService.shared.getLatestFollower() else {
            throw AIScreenLikeDetectionError.noLatestFollower
        }
        return try await armTargetUsername(username, expectedLiker: follower, limit: limit)
    }

    @discardableResult
    func armTargetUsername(_ username: String, expectedLiker: InstagramFollower, limit: Int) async throws -> String {
        let target = try await loadProfileFromSearch(username)
        return try await armProfile(
            target,
            limit: min(limit, 24),
            expectedLiker: expectedLiker,
            allowPagination: true,
            maxExtraPages: 1,
            extraPageDelayNanoseconds: 3_000_000_000,
            tolerateExtraPageFailure: true
        )
    }

    @discardableResult
    func armUsername(_ username: String, limit: Int) async throws -> String {
        let profile = try await loadProfileFromSearch(username)
        return try await armProfile(
            profile,
            limit: min(limit, 24),
            allowPagination: true,
            maxExtraPages: 1,
            extraPageDelayNanoseconds: 3_000_000_000,
            tolerateExtraPageFailure: true
        )
    }

    private func loadProfileFromSearch(_ username: String) async throws -> InstagramProfile {
        let clean = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        let results = try await InstagramService.shared.searchUsers(query: clean)
        let selected = results.first { $0.username.lowercased() == clean.lowercased() }
            ?? results.first
        guard let selected else {
            throw AIScreenLikeDetectionError.noLatestFollower
        }
        guard let profile = try await InstagramService.shared.getProfileInfo(
            userId: selected.userId,
            usernameHint: selected.username,
            fullNameHint: selected.fullName,
            profilePicURLHint: selected.profilePicURL,
            isVerifiedHint: selected.isVerified
        ) else {
            throw AIScreenLikeDetectionError.noLatestFollower
        }
        return profile
    }

    @discardableResult
    private func armProfile(
        _ profile: InstagramProfile,
        limit: Int,
        expectedLiker: InstagramFollower? = nil,
        allowPagination: Bool = true,
        maxExtraPages: Int = 3,
        extraPageDelayNanoseconds: UInt64 = 0,
        tolerateExtraPageFailure: Bool = false
    ) async throws -> String {
        guard !profile.isPrivate || profile.isFollowing else {
            throw AIScreenLikeDetectionError.privateProfile(profile.username)
        }

        let items = try await loadCandidateItems(
            userId: profile.userId,
            initial: profile.cachedMediaItems,
            initialCursor: profile.cachedNextMaxId,
            limit: limit,
            allowPagination: allowPagination,
            maxExtraPages: maxExtraPages,
            extraPageDelayNanoseconds: extraPageDelayNanoseconds,
            tolerateExtraPageFailure: tolerateExtraPageFailure
        )
        let counts = snapshotCounts(from: items)
        guard !counts.isEmpty else {
            throw AIScreenLikeDetectionError.noPosts(profile.username)
        }

        let snapshot = Snapshot(
            userId: profile.userId,
            username: profile.username,
            capturedAt: Date(),
            countsByMediaId: counts,
            expectedLikerUserId: expectedLiker?.userId,
            expectedLikerUsername: expectedLiker?.username
        )
        saveSnapshot(snapshot)
        await MainActor.run {
            armedUsername = snapshot.username
            armedPostCount = snapshot.countsByMediaId.count
            armedAt = snapshot.capturedAt
        }
        if let liker = expectedLiker?.username {
            print("❤️ [LIKE DETECT] Armed target @\(snapshot.username) with \(counts.count) posts; expected liker @\(liker)")
        } else {
            print("❤️ [LIKE DETECT] Armed @\(snapshot.username) with \(counts.count) posts")
        }
        return snapshot.username
    }

    func detectLikeIncrease(limit: Int) async throws -> AIScreenLikeDetectionResult {
        guard let snapshot = loadSnapshot() else {
            throw AIScreenLikeDetectionError.noSnapshot
        }

        let profile = try await loadProfile(userId: snapshot.userId, username: snapshot.username)
        guard !profile.isPrivate || profile.isFollowing else {
            throw AIScreenLikeDetectionError.privateProfile(profile.username)
        }

        let snapshotLimit = max(12, snapshot.countsByMediaId.count)
        let items = try await loadCandidateItems(
            userId: profile.userId,
            initial: profile.cachedMediaItems,
            initialCursor: profile.cachedNextMaxId,
            limit: min(limit, snapshotLimit),
            allowPagination: false
        )
        let snapshotKeys = Set(snapshot.countsByMediaId.keys)
        let comparableItems = items.filter { snapshotKeys.contains(mediaKey($0.mediaId)) }
        let increased = comparableItems.filter { item in
            guard let current = item.likeCount,
                  let previous = snapshot.countsByMediaId[mediaKey(item.mediaId)] else { return false }
            return current > previous
        }

        guard !increased.isEmpty else { throw AIScreenLikeDetectionError.noLikeIncrease }
        let matched: InstagramMediaItem
        if increased.count == 1 {
            matched = increased[0]
        } else if let expectedLikerUserId = snapshot.expectedLikerUserId,
                  let expectedLikerUsername = snapshot.expectedLikerUsername {
            matched = try await confirmExpectedLiker(
                expectedUserId: expectedLikerUserId,
                expectedUsername: expectedLikerUsername,
                candidates: increased,
                snapshot: snapshot
            )
        } else {
            throw AIScreenLikeDetectionError.multipleLikeIncreases
        }

        print("✅ [LIKE DETECT] @\(profile.username) matched mediaId=\(matched.mediaId)")
        return AIScreenLikeDetectionResult(profile: profile, mediaItems: items, matchedItem: matched)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        armedUsername = ""
        armedPostCount = 0
        armedAt = nil
    }

    private func loadProfile(userId: String, username: String) async throws -> InstagramProfile {
        if let profile = try await InstagramService.shared.getProfileInfo(userId: userId, usernameHint: username) {
            return profile
        }
        return try await InstagramService.shared.searchAndLoadUserProfile(username: username)
    }

    private func loadCandidateItems(
        userId: String,
        initial: [InstagramMediaItem],
        initialCursor: String?,
        limit: Int,
        allowPagination: Bool = true,
        maxExtraPages: Int = 3,
        extraPageDelayNanoseconds: UInt64 = 0,
        tolerateExtraPageFailure: Bool = false
    ) async throws -> [InstagramMediaItem] {
        let clampedLimit = min(max(limit, 12), 48)
        var items = initial
        var cursor = initialCursor
        var pages = 0

        if items.isEmpty {
            let page = try await InstagramService.shared.getUserMediaItems(userId: userId, amount: min(18, clampedLimit))
            items = page.0
            cursor = page.1
            pages += 1
        }

        var extraPages = 0
        while allowPagination, items.count < clampedLimit, let next = cursor, !next.isEmpty, extraPages < maxExtraPages {
            if extraPageDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: extraPageDelayNanoseconds)
            }
            do {
                let page = try await InstagramService.shared.getUserMediaItems(userId: userId, amount: 18, maxId: next)
                items.append(contentsOf: page.0)
                cursor = page.1
                pages += 1
                extraPages += 1
            } catch {
                if tolerateExtraPageFailure, !items.isEmpty {
                    print("❤️ [LIKE DETECT] Extra page skipped for safety: \(error.localizedDescription)")
                    break
                }
                throw error
            }
        }

        var seen = Set<String>()
        return items.filter { item in
            let key = mediaKey(item.mediaId)
            return !key.isEmpty && seen.insert(key).inserted
        }.prefix(clampedLimit).map { $0 }
    }

    private func snapshotCounts(from items: [InstagramMediaItem]) -> [String: Int] {
        items.reduce(into: [String: Int]()) { result, item in
            guard let likes = item.likeCount else { return }
            result[mediaKey(item.mediaId)] = likes
        }
    }

    private func confirmExpectedLiker(
        expectedUserId: String,
        expectedUsername: String,
        candidates: [InstagramMediaItem],
        snapshot: Snapshot
    ) async throws -> InstagramMediaItem {
        let ranked = candidates.sorted { left, right in
            let leftDelta = (left.likeCount ?? 0) - (snapshot.countsByMediaId[mediaKey(left.mediaId)] ?? 0)
            let rightDelta = (right.likeCount ?? 0) - (snapshot.countsByMediaId[mediaKey(right.mediaId)] ?? 0)
            return leftDelta > rightDelta
        }
        guard ranked.count <= 3 else {
            print("❤️ [LIKE DETECT] \(ranked.count) increased posts — skipping liker scan for anti-bot safety")
            throw AIScreenLikeDetectionError.multipleLikeIncreases
        }

        for (index, item) in ranked.enumerated() {
            try? await Task.sleep(nanoseconds: index == 0 ? 800_000_000 : 1_200_000_000)
            let (likers, _) = try await InstagramService.shared.getMediaLikers(mediaId: item.mediaId)
            let found = likers.contains { liker in
                liker.userId == expectedUserId ||
                    liker.username.lowercased() == expectedUsername.lowercased()
            }
            if found {
                print("✅ [LIKE DETECT] Confirmed @\(expectedUsername) liked mediaId=\(item.mediaId)")
                return item
            }
        }

        throw AIScreenLikeDetectionError.likerNotConfirmed(expectedUsername)
    }

    private func mediaKey(_ mediaId: String) -> String {
        mediaId.split(separator: "_").first.map(String.init) ?? mediaId
    }

    private func saveSnapshot(_ snapshot: Snapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    private func loadSnapshot() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }
}
