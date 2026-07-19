import Foundation

/// Shared reconciliation logic for Instagram profile-grid refreshes.
///
/// The public profile replica is rebuildable. Post Prediction sets are not touched
/// here; they live in DataManager/UserDefaults plus Documents/photos and reveal by
/// mediaId/local JPG independently from this grid cache.
enum ProfileMediaReconciler {
    struct PageRangeResult {
        let urls: [String]
        let itemsByURL: [String: InstagramMediaItem]
        let removedCount: Int
        let appendedCount: Int
        let replacedURLCount: Int
        let protectedCount: Int
    }

    /// Forces the grid prefix to match Instagram's returned window exactly (order + ids).
    ///
    /// - Prefix: `freshItems` in Instagram order (source of truth for the synced window).
    /// - Tail: previous local CDN posts that are older than `endCursor` and absent from
    ///   fresh (not yet covered by this sync). Anything "newer" than `endCursor` that
    ///   Instagram did not return is dropped (deleted/archived ghost).
    /// - Overlay URLs (`reveal://`, `amnesia://`) are preserved for the caller to place.
    ///
    /// Use for page-1 manual sync and for the accumulated window after pages 2..N.
    static func applyExactFetchedPrefix(
        currentURLs: [String],
        currentItemsByURL: [String: InstagramMediaItem],
        freshItems: [InstagramMediaItem],
        endCursor: String?
    ) -> PageRangeResult {
        let endPk = cursorPK(endCursor) // nil ⇒ Instagram returned the full public grid
        var freshByKey: [String: InstagramMediaItem] = [:]
        var freshKeysInOrder: [String] = []
        for item in freshItems {
            let key = mediaKey(item.mediaId.isEmpty ? item.imageURL : item.mediaId)
            if freshByKey[key] == nil {
                freshByKey[key] = item
                freshKeysInOrder.append(key)
            }
        }

        var resultURLs: [String] = []
        var resultItemsByURL: [String: InstagramMediaItem] = [:]
        var seenKeys = Set<String>()
        var removedCount = 0
        var replacedURLCount = 0

        // 1) Exact Instagram prefix
        for key in freshKeysInOrder {
            guard let fresh = freshByKey[key] else { continue }
            if let oldURL = currentURLs.first(where: {
                guard let existing = currentItemsByURL[$0], !isOverlayURL($0) else { return false }
                return mediaKey(existing.mediaId.isEmpty ? existing.imageURL : existing.mediaId) == key
            }), oldURL != fresh.imageURL {
                replacedURLCount += 1
            }
            append(fresh, preferredURL: fresh.imageURL, into: &resultURLs, itemsByURL: &resultItemsByURL, seenKeys: &seenKeys)
        }

        // 2) Preserve overlays (Performance repositions reveals as needed)
        for url in currentURLs where isOverlayURL(url) {
            if seenKeys.insert(url).inserted {
                resultURLs.append(url)
                if let existing = currentItemsByURL[url] {
                    resultItemsByURL[url] = existing
                }
            }
        }

        // 3) Older local tail only (outside the synced window)
        for url in currentURLs {
            guard !isOverlayURL(url), let existing = currentItemsByURL[url] else { continue }
            let key = mediaKey(existing.mediaId.isEmpty ? existing.imageURL : existing.mediaId)
            if freshByKey[key] != nil { continue }
            if seenKeys.contains(key) { continue }

            let pk = mediaPK(existing.mediaId)
            let keepAsOlderTail: Bool = {
                guard let endPk else {
                    // No further pages — anything not returned is gone from Instagram.
                    return false
                }
                guard let pk else {
                    // Unparseable id and not in fresh → drop (ghost / corrupt cache).
                    return false
                }
                return pk <= endPk
            }()

            if keepAsOlderTail {
                append(existing, preferredURL: existing.imageURL, into: &resultURLs, itemsByURL: &resultItemsByURL, seenKeys: &seenKeys)
            } else {
                removedCount += 1
            }
        }

        let previousKeys = Set(currentURLs.compactMap { url -> String? in
            guard !isOverlayURL(url), let existing = currentItemsByURL[url] else { return nil }
            return mediaKey(existing.mediaId.isEmpty ? existing.imageURL : existing.mediaId)
        })
        let appendedCount = freshKeysInOrder.filter { !previousKeys.contains($0) }.count

        return PageRangeResult(
            urls: resultURLs,
            itemsByURL: resultItemsByURL,
            removedCount: removedCount,
            appendedCount: appendedCount,
            replacedURLCount: replacedURLCount,
            protectedCount: 0
        )
    }

    /// Applies one authoritative Instagram feed page to an existing grid.
    ///
    /// Page 1 (`startCursor == nil`) uses exact Instagram prefix matching.
    /// Pages 2+ use PK-range replacement; prefer calling `applyExactFetchedPrefix`
    /// with the accumulated window when doing multi-page sync.
    ///
    /// Items in `protectedMediaIds` are never removed on deep pages; this protects
    /// page-1 pinned posts whose pk can be much older than their visible position.
    static func applyAuthoritativePageRange(
        currentURLs: [String],
        currentItemsByURL: [String: InstagramMediaItem],
        freshItems: [InstagramMediaItem],
        startCursor: String?,
        endCursor: String?,
        protectedMediaIds: Set<String> = []
    ) -> PageRangeResult {
        // Page 1: exact Instagram prefix — avoids first-slot ghosts after archive/delete.
        if startCursor == nil {
            return applyExactFetchedPrefix(
                currentURLs: currentURLs,
                currentItemsByURL: currentItemsByURL,
                freshItems: freshItems,
                endCursor: endCursor
            )
        }

        let startPk = cursorPK(startCursor) ?? Int64.max
        let endPk = cursorPK(endCursor) ?? Int64.min
        let protectedKeys = Set(protectedMediaIds.map(mediaKey))

        var freshByKey: [String: InstagramMediaItem] = [:]
        for item in freshItems {
            let key = mediaKey(item.mediaId.isEmpty ? item.imageURL : item.mediaId)
            if freshByKey[key] == nil {
                freshByKey[key] = item
            }
        }

        var resultURLs: [String] = []
        var resultItemsByURL: [String: InstagramMediaItem] = [:]
        var seenKeys = Set<String>()
        var removedCount = 0
        var replacedURLCount = 0
        var protectedCount = 0

        for url in currentURLs {
            guard !isOverlayURL(url), let existing = currentItemsByURL[url] else {
                if !seenKeys.contains(url) {
                    resultURLs.append(url)
                    if let existing = currentItemsByURL[url] {
                        resultItemsByURL[url] = existing
                    }
                    seenKeys.insert(url)
                }
                continue
            }

            let key = mediaKey(existing.mediaId.isEmpty ? existing.imageURL : existing.mediaId)
            if protectedKeys.contains(key) {
                protectedCount += 1
                append(existing, preferredURL: existing.imageURL, into: &resultURLs, itemsByURL: &resultItemsByURL, seenKeys: &seenKeys)
                continue
            }

            let pk = mediaPK(existing.mediaId)
            // Unparseable pk inside a deep sync: treat as in-range so ghosts still drop.
            let inRange = pk.map { $0 > endPk && $0 < startPk } ?? true
            if inRange {
                if let fresh = freshByKey[key] {
                    if fresh.imageURL != url { replacedURLCount += 1 }
                    append(fresh, preferredURL: fresh.imageURL, into: &resultURLs, itemsByURL: &resultItemsByURL, seenKeys: &seenKeys)
                } else {
                    removedCount += 1
                }
            } else {
                append(existing, preferredURL: existing.imageURL, into: &resultURLs, itemsByURL: &resultItemsByURL, seenKeys: &seenKeys)
            }
        }

        var appendedCount = 0
        for fresh in freshItems {
            let key = mediaKey(fresh.mediaId.isEmpty ? fresh.imageURL : fresh.mediaId)
            guard !seenKeys.contains(key) else { continue }
            append(fresh, preferredURL: fresh.imageURL, into: &resultURLs, itemsByURL: &resultItemsByURL, seenKeys: &seenKeys)
            appendedCount += 1
        }

        return PageRangeResult(
            urls: resultURLs,
            itemsByURL: resultItemsByURL,
            removedCount: removedCount,
            appendedCount: appendedCount,
            replacedURLCount: replacedURLCount,
            protectedCount: protectedCount
        )
    }

    /// Marks set photos as archived when their mediaId falls inside the synced
    /// Instagram window but was not returned by Instagram (deleted/archived on IG,
    /// or leftover set reveal that is no longer public).
    ///
    /// Photos older than `syncedWindowEndPk` are left alone — they simply were not
    /// covered by this sync depth. MediaIds in `protectedMediaIds` (e.g. pending
    /// `reveal://` not yet indexed by Instagram) are never archived here.
    @MainActor
    static func reconcileSetPhotosMissingFromSyncedFeed(
        fetchedKeys: Set<String>,
        syncedWindowEndPk: Int64?,
        userId: String?,
        protectedMediaIds: Set<String> = []
    ) {
        let normalizedFetched = Set(fetchedKeys.map(mediaKey))
        let protectedKeys = Set(protectedMediaIds.map(mediaKey))
        var archivedCount = 0

        for set in DataManager.shared.sets {
            for photo in set.photos {
                guard let mediaId = photo.mediaId, !photo.isArchived else { continue }
                let key = mediaKey(mediaId)
                if normalizedFetched.contains(key) { continue }
                if protectedKeys.contains(key) { continue }

                let pk = mediaPK(mediaId)
                let shouldArchive: Bool = {
                    guard let endPk = syncedWindowEndPk else {
                        // Full public grid was returned — anything missing is gone.
                        return true
                    }
                    guard let pk else {
                        // Can't place it in the window; leave alone.
                        return false
                    }
                    // Inside the synced window (newer than oldest fetched cursor) but absent.
                    return pk > endPk
                }()

                guard shouldArchive else { continue }

                DataManager.shared.updatePhoto(
                    photoId: photo.id,
                    mediaId: mediaId,
                    isArchived: true,
                    uploadStatus: .completed,
                    errorMessage: nil,
                    uploadDate: photo.uploadDate
                )
                ProfileCacheService.shared.removeMediaEverywhere(mediaId: mediaId, userId: userId)
                archivedCount += 1
                print("🔄 [SET SYNC] Archived set photo \(mediaId) — absent from Instagram sync window")
            }
        }

        if archivedCount > 0 {
            LogManager.shared.info("Set reconcile after sync: archived \(archivedCount) photo(s) missing from Instagram", category: .general)
        }
    }

    static func mediaKeys(from items: [InstagramMediaItem]) -> Set<String> {
        Set(items.map { mediaKey($0.mediaId.isEmpty ? $0.imageURL : $0.mediaId) })
    }

    static func mediaKey(_ mediaId: String) -> String {
        mediaId.split(separator: "_").first.map(String.init) ?? mediaId
    }

    static func cursorPK(_ cursor: String?) -> Int64? {
        guard let cursor, !cursor.isEmpty else { return nil }
        return cursor.split(separator: "_").first.flatMap { Int64($0) }
    }

    static func mediaPK(_ mediaId: String) -> Int64? {
        let key = mediaKey(mediaId)
        return Int64(key)
    }

    static func isOverlayURL(_ url: String) -> Bool {
        url.hasPrefix("reveal://")
            || url.hasPrefix("reveal://test-")
            || url.hasPrefix("amnesia://")
            || url.hasPrefix("instapick://")
    }

    private static func append(
        _ item: InstagramMediaItem,
        preferredURL: String,
        into urls: inout [String],
        itemsByURL: inout [String: InstagramMediaItem],
        seenKeys: inout Set<String>
    ) {
        let key = mediaKey(item.mediaId.isEmpty ? preferredURL : item.mediaId)
        guard seenKeys.insert(key).inserted else { return }
        urls.append(preferredURL)
        itemsByURL[preferredURL] = item
    }
}
