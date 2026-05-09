import SwiftUI
import UIKit

/// Intercepts UIScrollView deceleration to land on the forced post.
///
/// Behaviour:
/// 1. Every flick scroll (finger lift with velocity) redirects to the forced post
/// 2. Once the scroll has stopped on the forced post, the trick RELEASES
/// 3. After release, all scrolling is completely normal — the spectator
///    can browse up/down freely, slow or fast
///
/// This feels natural: the spectator scrolls, the feed "happens" to stop
/// on a specific image, then they can keep browsing.
struct ScrollViewInterceptor: UIViewRepresentable {
    let forcedIndex: Int
    let totalPostCount: Int
    @Binding var hasActivated: Bool
    let isActive: Bool
    var forcedThumbnail: UIImage? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let sv = Self.findScrollView(in: view) else {
                print("⚠️ [SCROLL] UIScrollView not found")
                return
            }
            context.coordinator.attach(to: sv)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let c = context.coordinator
        // If the key inputs changed (new session or different post), invalidate
        // the cached target Y so it's recalculated fresh on the next scroll.
        if c.forcedIndex != forcedIndex || c.totalPostCount != totalPostCount {
            c.invalidateCache()
        }
        c.forcedIndex        = forcedIndex
        c.totalPostCount     = totalPostCount
        c.isActive           = isActive
        c.hasActivatedBinding = $hasActivated
        c.forcedThumbnail    = forcedThumbnail
    }

    // MARK: - View hierarchy search

    private static func findScrollView(in view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let v = current {
            if let sv = v as? UIScrollView { return sv }
            if let parent = v.superview {
                for sibling in parent.subviews where sibling !== v {
                    if let found = findInSubtree(sibling) { return found }
                }
            }
            current = v.superview
        }
        return nil
    }

    private static func findInSubtree(_ root: UIView) -> UIScrollView? {
        if let sv = root as? UIScrollView { return sv }
        for sub in root.subviews {
            if let found = findInSubtree(sub) { return found }
        }
        return nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIScrollViewDelegate {
        var forcedIndex: Int = 0
        var totalPostCount: Int = 1
        var hasActivatedBinding: Binding<Bool>?
        var forcedThumbnail: UIImage? = nil

        /// Once true, the trick is done and all scrolling is normal.
        private var released = false
        /// The Y we're forcing the scroll to — cached within a single activation session.
        private var cachedForcedY: CGFloat?
        private weak var originalDelegate: UIScrollViewDelegate?

        /// Tracks the last isActive value to detect re-entry.
        private var lastIsActive = false
        var isActive = false {
            didSet {
                // When activating fresh (false → true), reset so the trick
                // runs again and the target Y is recalculated from scratch.
                if isActive && !lastIsActive {
                    released = false
                    cachedForcedY = nil
                }
                lastIsActive = isActive
            }
        }

        func invalidateCache() { cachedForcedY = nil }

        init(parent: ScrollViewInterceptor) {
            self.forcedIndex      = parent.forcedIndex
            self.totalPostCount   = parent.totalPostCount
            self.isActive         = parent.isActive
            self.lastIsActive     = parent.isActive
            self.forcedThumbnail  = parent.forcedThumbnail
        }

        func attach(to scrollView: UIScrollView) {
            originalDelegate = scrollView.delegate
            scrollView.delegate = self
        }

        // MARK: - Deceleration intercept

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            originalDelegate?.scrollViewWillEndDragging?(
                scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset
            )

            guard isActive && !released else { return }

            guard let targetY = computeForcedY(in: scrollView) else { return }

            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let clampedY = min(max(0, targetY), maxY)

            cachedForcedY = clampedY
            targetContentOffset.pointee.y = clampedY
            print("🎯 [FORCE] → final clampedY=\(clampedY)  maxY=\(maxY)  contentH=\(scrollView.contentSize.height)")
        }

        // MARK: - Detect when scroll settles on forced post → release

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            originalDelegate?.scrollViewDidEndDecelerating?(scrollView)
            releaseIfSettled(on: scrollView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            originalDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)

            // If the user drags slowly and stops without deceleration,
            // check release condition here too.
            if !decelerate { releaseIfSettled(on: scrollView) }
        }

        private func releaseIfSettled(on scrollView: UIScrollView) {
            guard isActive && !released, let targetY = cachedForcedY else { return }

            let visibleH = max(
                1,
                scrollView.bounds.height
                    - scrollView.adjustedContentInset.top
                    - scrollView.adjustedContentInset.bottom
            )
            let tolerance = min(max(visibleH * 0.08, 24), 64)
            let currentY = scrollView.contentOffset.y

            guard abs(currentY - targetY) <= tolerance else { return }

            released = true
            DispatchQueue.main.async { [weak self] in
                self?.hasActivatedBinding?.wrappedValue = true
            }
        }

        // MARK: - Compute forced Y (with caching)

        private func computeForcedY(in scrollView: UIScrollView) -> CGFloat? {
            let headerHeight: CGFloat = 48
            let screenW      = UIScreen.main.bounds.width
            let topInset     = scrollView.adjustedContentInset.top
            let botInset     = scrollView.adjustedContentInset.bottom
            let safeTop      = scrollView.safeAreaInsets.top
            let safeBottom   = scrollView.safeAreaInsets.bottom
            let visibleH     = max(1, scrollView.bounds.height - topInset - botInset)

            // Use the ACTUAL thumbnail dimensions to get the real rendered image height.
            // PostCardView uses .scaledToFit() at full width, so height = screenW × (h/w).
            // Capped at visibleH so very tall media still lands with the forced post dominant.
            let imageHeight: CGFloat = {
                let thumb = forcedThumbnail
                if let img = thumb {
                    let ratio = img.size.height / max(img.size.width, 1)
                    let natural = screenW * ratio
                    return min(natural, max(1, visibleH - headerHeight))
                }
                return screenW  // fallback: assume square
            }()

            // Helper: place the forced post near the top of the visible viewport.
            // This keeps the forced card visually dominant instead of centering it
            // and accidentally giving the previous post too much screen presence.
            func dominantOffset(cardAbsoluteY: CGFloat) -> CGFloat {
                let cardTopMargin = min(max(visibleH * 0.025, 8), 18)
                return cardAbsoluteY - topInset - cardTopMargin
            }

            // ── Primary: locate the card view by its accessibility identifier ──────
            // Note: SwiftUI may not expose the identifier in UIKit's tree, so this
            // path often falls through to the fallback below.
            if let view = Self.findView(identifier: "forced_post_card", in: scrollView) {
                // view.convert(…, to: scrollView) returns coords in the scrollView's
                // BOUNDS space (origin = contentOffset), so we add contentOffset.y
                // to get the absolute content position.
                let frame = view.convert(view.bounds, to: scrollView)
                let absoluteCardY = frame.minY + scrollView.contentOffset.y

                let y = dominantOffset(cardAbsoluteY: absoluteCardY)

                print("""
                🎯 [FORCE DEBUG] via findView
                   targetMode        = dominantTop
                   absoluteCardY     = \(absoluteCardY)  (frame.minY \(frame.minY) + offset \(scrollView.contentOffset.y))
                   topInset          = \(topInset)   bottomInset = \(botInset)
                   safeAreaTop       = \(safeTop)   safeAreaBottom = \(safeBottom)
                   visibleH          = \(visibleH)
                   imageHeight(real) = \(imageHeight)   screenW = \(screenW)
                   dominantOffset    = \(y)
                """)

                cachedForcedY = y
                return y
            }

            // If we already computed it before, reuse (findView may fail on subsequent
            // calls if SwiftUI has recycled or not yet rendered the cell).
            if let cached = cachedForcedY {
                return cached
            }

            // ── Fallback: estimate absolute card top from uniform row heights ───────
            // forcedIndex * avg gives the card's TOP in content coords.
            // We then apply the same dominant alignment formula.
            let contentHeight = scrollView.contentSize.height
            guard contentHeight > 0 else { return nil }
            let avg = contentHeight / CGFloat(max(1, totalPostCount))
            let cardAbsoluteY = CGFloat(forcedIndex) * avg

            let y = dominantOffset(cardAbsoluteY: cardAbsoluteY)

            print("""
            🎯 [FORCE DEBUG] via fallback
               targetMode        = dominantTop
               forcedIndex       = \(forcedIndex) / \(totalPostCount)
               avg card height   = \(avg)
               cardAbsoluteY     = \(cardAbsoluteY)
               topInset          = \(topInset)   bottomInset = \(botInset)
               safeAreaTop       = \(safeTop)   safeAreaBottom = \(safeBottom)
               visibleH          = \(visibleH)
               imageHeight(real) = \(imageHeight)   screenW = \(screenW)
               dominantOffset    = \(y)
            """)

            cachedForcedY = y
            return y
        }

        private static func findView(identifier: String, in root: UIView) -> UIView? {
            if root.accessibilityIdentifier == identifier { return root }
            for sub in root.subviews {
                if let found = findView(identifier: identifier, in: sub) { return found }
            }
            return nil
        }

        // MARK: - Forward delegate calls

        func scrollViewDidScroll(_ sv: UIScrollView) {
            originalDelegate?.scrollViewDidScroll?(sv)
        }
        func scrollViewWillBeginDragging(_ sv: UIScrollView) {
            originalDelegate?.scrollViewWillBeginDragging?(sv)
        }
        func scrollViewShouldScrollToTop(_ sv: UIScrollView) -> Bool {
            originalDelegate?.scrollViewShouldScrollToTop?(sv) ?? true
        }
        func scrollViewDidScrollToTop(_ sv: UIScrollView) {
            originalDelegate?.scrollViewDidScrollToTop?(sv)
        }
        func scrollViewDidEndScrollingAnimation(_ sv: UIScrollView) {
            originalDelegate?.scrollViewDidEndScrollingAnimation?(sv)
        }
    }
}
