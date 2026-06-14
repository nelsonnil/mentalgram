import SwiftUI
import UIKit

/// Makes the feed land on the forced post — simple and reliable on every device.
///
/// THE TRICK (hidden-post design):
/// The forced post is NOT in the feed while the spectator browses, so it can never be
/// seen by scrolling. This UIKit bridge does ONE job: detect when the spectator lifts
/// their finger after a downward flick, cancel the native deceleration, and report a
/// safe insertion slot (the first cell just below the fold, found from real geometry).
///
/// SwiftUI then inserts the forced post at that slot (invisibly, below the fold) and
/// scrolls it to the center with `ScrollViewReader.scrollTo(anchor:)`. The distance is
/// roughly one screen regardless of flick strength, so the behaviour is consistent and
/// does not depend on finger speed — exactly what we want for a dependable stop.
struct ScrollViewInterceptor: UIViewRepresentable {
    let isActive: Bool
    let totalPostCount: Int
    /// Called once when the spectator commits a downward flick. The argument is the
    /// SwiftUI index where the forced post should be inserted (just below the fold).
    var commitForce: ((Int) -> Void)? = nil

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
        c.totalPostCount = totalPostCount
        c.isActive       = isActive
        c.commitForce    = commitForce
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
        var totalPostCount: Int = 1
        var commitForce: ((Int) -> Void)?

        /// Once true, the trick is done and all scrolling is normal.
        private var released = false
        private weak var originalDelegate: UIScrollViewDelegate?

        private var lastIsActive = false
        var isActive = false {
            didSet {
                // Fresh activation (false → true): reset so the trick runs again.
                if isActive && !lastIsActive { released = false }
                lastIsActive = isActive
            }
        }

        init(parent: ScrollViewInterceptor) {
            self.totalPostCount = parent.totalPostCount
            self.isActive       = parent.isActive
            self.lastIsActive   = parent.isActive
            self.commitForce    = parent.commitForce
        }

        func attach(to scrollView: UIScrollView) {
            originalDelegate = scrollView.delegate
            scrollView.delegate = self
        }

        // MARK: - Finger lift → commit the forced post just below the fold

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            originalDelegate?.scrollViewWillEndDragging?(
                scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset
            )

            guard isActive, !released else { return }
            // Fire on a downward flick (spectators browse a feed downward). Upward or
            // near-zero gestures scroll normally so the spectator can look around.
            guard velocity.y > 0.1 else { return }
            guard scrollView.contentSize.height > 0, totalPostCount > 0 else { return }

            let slot = insertionSlot(in: scrollView)

            // Cancel the native deceleration so the scroll stops where the finger
            // lifted; SwiftUI then animates a single, smooth move to center the post.
            targetContentOffset.pointee = scrollView.contentOffset
            released = true
            print("🎯 [FORCE] commit forced post at slot \(slot)")
            commitForce?(slot)
        }

        // MARK: - Insertion slot from real geometry

        /// SwiftUI index of the slot where the forced post should be inserted: the
        /// first materialised cell whose top is at or below the viewport's bottom
        /// edge. Inserting there puts the forced post just under the fold (it pushes
        /// that cell down), so it stays invisible until SwiftUI scrolls to it.
        /// Falls back to just past the last materialised cell, then to the list end.
        private func insertionSlot(in sv: UIScrollView) -> Int {
            let viewportBottom = sv.contentOffset.y + sv.bounds.height
            var firstBelow: (index: Int, top: CGFloat)?
            var maxSeenIndex = -1

            Self.forEachCellMarker(in: sv) { index, view in
                let frame = view.convert(view.bounds, to: sv)
                let top = frame.minY + sv.contentOffset.y
                maxSeenIndex = max(maxSeenIndex, index)
                if top >= viewportBottom - 1 {
                    if firstBelow == nil || top < firstBelow!.top {
                        firstBelow = (index, top)
                    }
                }
            }

            if let firstBelow { return firstBelow.index }
            if maxSeenIndex >= 0 { return min(maxSeenIndex + 1, totalPostCount) }
            return totalPostCount
        }

        /// Visits every materialised per-cell marker, decoding its index.
        private static func forEachCellMarker(in root: UIView, _ body: (Int, UIView) -> Void) {
            if let id = root.accessibilityIdentifier, id.hasPrefix("post_cell_"),
               let index = Int(id.dropFirst("post_cell_".count)) {
                body(index, root)
            }
            for sub in root.subviews { forEachCellMarker(in: sub, body) }
        }

        // MARK: - Forward delegate calls

        func scrollViewDidScroll(_ sv: UIScrollView) {
            originalDelegate?.scrollViewDidScroll?(sv)
        }
        func scrollViewWillBeginDragging(_ sv: UIScrollView) {
            originalDelegate?.scrollViewWillBeginDragging?(sv)
        }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate decelerate: Bool) {
            originalDelegate?.scrollViewDidEndDragging?(sv, willDecelerate: decelerate)
        }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
            originalDelegate?.scrollViewDidEndDecelerating?(sv)
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

// MARK: - Per-cell geometry marker

/// A real UIKit marker placed behind EVERY post card, carrying that card's index in
/// its identifier ("post_cell_<index>"). Unlike a SwiftUI `.accessibilityIdentifier`
/// (which SwiftUI may strip from the rendered UIKit tree), this guarantees a genuine
/// `UIView` exists at the card's position, letting `ScrollViewInterceptor` map the
/// scroll's real geometry back to a SwiftUI index and insert the forced post exactly
/// below the fold on ANY device.
struct PostCellMarker: UIViewRepresentable {
    let index: Int

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.accessibilityIdentifier = "post_cell_\(index)"
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityIdentifier = "post_cell_\(index)"
    }
}
