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
        context.coordinator.forcedIndex    = forcedIndex
        context.coordinator.totalPostCount = totalPostCount
        context.coordinator.isActive       = isActive
        context.coordinator.hasActivatedBinding = $hasActivated
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
        var isActive = false
        var hasActivatedBinding: Binding<Bool>?

        /// Once true, the trick is done and all scrolling is normal.
        private var released = false
        /// The Y we're forcing the scroll to — cached after first successful resolution.
        private var cachedForcedY: CGFloat?
        private weak var originalDelegate: UIScrollViewDelegate?

        init(parent: ScrollViewInterceptor) {
            self.forcedIndex    = parent.forcedIndex
            self.totalPostCount = parent.totalPostCount
            self.isActive       = parent.isActive
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

            targetContentOffset.pointee.y = clampedY
            print("🎯 [FORCE] → final clampedY=\(clampedY)  maxY=\(maxY)  contentH=\(scrollView.contentSize.height)")
        }

        // MARK: - Detect when scroll settles on forced post → release

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            originalDelegate?.scrollViewDidEndDecelerating?(scrollView)

            if isActive && !released, let targetY = cachedForcedY {
                let currentY = scrollView.contentOffset.y
                // If the scroll stopped within one screen-height of the target,
                // the spectator has seen the forced post → release the trick.
                let tolerance = scrollView.bounds.height * 0.5
                if abs(currentY - targetY) < tolerance {
                    released = true
                    DispatchQueue.main.async { [weak self] in
                        self?.hasActivatedBinding?.wrappedValue = true
                    }
                }
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            originalDelegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)

            // If the user drags slowly and stops without deceleration,
            // check release condition here too.
            if !decelerate && isActive && !released, let targetY = cachedForcedY {
                let currentY = scrollView.contentOffset.y
                let tolerance = scrollView.bounds.height * 0.5
                if abs(currentY - targetY) < tolerance {
                    released = true
                    DispatchQueue.main.async { [weak self] in
                        self?.hasActivatedBinding?.wrappedValue = true
                    }
                }
            }
        }

        // MARK: - Compute forced Y (with caching)

        private func computeForcedY(in scrollView: UIScrollView) -> CGFloat? {
            if let view = Self.findView(identifier: "forced_post_card", in: scrollView) {
                let frame = view.convert(view.bounds, to: scrollView)

                let headerHeight: CGFloat = 48
                let imageHeight = UIScreen.main.bounds.width   // square post
                let viewportHeight = scrollView.bounds.height

                let y = frame.minY + headerHeight + imageHeight - viewportHeight

                print("""
                🎯 [FORCE DEBUG]
                   screen.width       = \(UIScreen.main.bounds.width)
                   screen.height      = \(UIScreen.main.bounds.height)
                   viewport.height    = \(viewportHeight)
                   contentInset.top   = \(scrollView.contentInset.top)
                   adjustedInset.top  = \(scrollView.adjustedContentInset.top)
                   card frame.minY    = \(frame.minY)
                   card frame.height  = \(frame.height)
                   imageHeight(width) = \(imageHeight)
                   computed Y         = \(y)
                   currentOffset.y    = \(scrollView.contentOffset.y)
                """)

                cachedForcedY = y
                return y
            }

            // If we already computed it before, reuse (LazyVStack may have recycled the view)
            if let cached = cachedForcedY {
                return cached
            }

            // Fallback: estimate from content size
            let contentHeight = scrollView.contentSize.height
            guard contentHeight > 0 else { return nil }
            let avg = contentHeight / CGFloat(max(1, totalPostCount))
            let y = CGFloat(forcedIndex) * avg
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
