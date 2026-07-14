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

    /// Applies one authoritative Instagram feed page to an existing grid.
    ///
    /// The authoritative page range is `(endCursorPk, startCursorPk)`.
    /// - Page 1 uses `startCursor == nil`, so the range is `(endCursorPk, +infinity)`.
    /// - Page 2+ uses the previous page cursor as `startCursor` and the current
    ///   response cursor as `endCursor`.
    ///
    /// Items in the range that are not returned by Instagram are removed as
    /// deleted/archived. Items outside the range are left untouched. Items in
    /// `protectedMediaIds` are never removed; this protects page-1 pinned posts,
    /// whose pk can be much older than their visible position.
    static func applyAuthoritativePageRange(
        currentURLs: [String],
        currentItemsByURL: [String: InstagramMediaItem],
        freshItems: [InstagramMediaItem],
        startCursor: String?,
        endCursor: String?,
        protectedMediaIds: Set<String> = []
    ) -> PageRangeResult {
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
            let inRange = pk.map { $0 > endPk && $0 < startPk } ?? false
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
        url.hasPrefix("reveal://") || url.hasPrefix("reveal://test-") || url.hasPrefix("amnesia://")
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
