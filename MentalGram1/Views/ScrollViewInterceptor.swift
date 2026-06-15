import SwiftUI
import UIKit

/// Makes the feed land on the forced post — reliably, on every device and image size.
///
/// THE TRICK (hidden-post design):
/// The forced post is NOT in the feed while the spectator browses, so it can never be
/// seen by scrolling. This UIKit bridge detects when the spectator lifts their finger
/// after a downward swipe, then settles the scroll onto the forced post.
///
/// WHY A GESTURE RECOGNIZER (not the scroll delegate):
/// SwiftUI owns the ScrollView's `delegate` on iOS 16 and may silently reclaim it, so
/// hijacking it is unreliable — `scrollViewWillEndDragging` can simply stop firing.
/// Instead we ADD our own `UIPanGestureRecognizer` (simultaneous, non-cancelling),
/// which SwiftUI cannot take away and which never interferes with normal scrolling.
///
/// THE SETTLE (real geometry, device-independent):
/// On finger-up we (1) halt momentum so nothing is revealed, (2) insert the forced
/// post just below the fold, (3) read the forced IMAGE's real frame after layout, and
/// (4) animate to the offset that shows the image fully — centered if it fits, top-
/// pinned if it is taller than the screen. The post rises from the bottom and stops
/// exactly when the image is fully visible.
struct ScrollViewInterceptor: UIViewRepresentable {
    let isActive: Bool
    let totalPostCount: Int
    /// Inserts the forced post at the given SwiftUI index (just below the fold).
    var insertForced: ((Int) -> Void)? = nil

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
        c.insertForced   = insertForced
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

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var totalPostCount: Int = 1
        var insertForced: ((Int) -> Void)?

        /// Once true, the trick is done and all scrolling is normal.
        private var released = false
        private weak var scrollView: UIScrollView?
        private var panRecognizer: UIPanGestureRecognizer?

        private var lastIsActive = false
        var isActive = false {
            didSet {
                if isActive && !lastIsActive { released = false }
                lastIsActive = isActive
            }
        }

        init(parent: ScrollViewInterceptor) {
            self.totalPostCount = parent.totalPostCount
            self.isActive       = parent.isActive
            self.lastIsActive   = parent.isActive
            self.insertForced   = parent.insertForced
        }

        func attach(to sv: UIScrollView) {
            guard panRecognizer == nil else { return }
            scrollView = sv
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false   // never steal touches from the scroll
            sv.addGestureRecognizer(pan)
            panRecognizer = pan
        }

        // Coexist with SwiftUI's own scroll pan recognizer.
        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        // MARK: - Finger up → settle on the forced post

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard isActive, !released, let sv = scrollView else { return }
            guard g.state == .ended else { return }

            // Finger moving UP (velocity.y < 0) means the spectator is browsing DOWN
            // the feed. A small threshold avoids firing on taps/tiny jitters.
            let velocity = g.velocity(in: sv)
            guard velocity.y < -80 else { return }
            guard sv.contentSize.height > 0, totalPostCount > 0 else { return }

            released = true

            // Halt momentum immediately so leftover inertia can't reveal the forced
            // post before we settle on it.
            sv.setContentOffset(sv.contentOffset, animated: false)

            // Insert the forced post a few cells below the fold so the settle
            // animation travels past several real posts before landing — feels like
            // a natural long scroll rather than stopping immediately.
            let baseSlot = insertionSlot(in: sv)
            let slot = min(baseSlot + 6, totalPostCount)
            print("🎯 [FORCE] commit forced post at slot \(slot)")
            insertForced?(slot)
            // Kick off a two-phase settle, passing the slot so phase 1 can scroll
            // toward an estimate (triggering LazyVStack to materialise the cell)
            // while phase 2 corrects to the real marker geometry.
            settleOnForced(in: sv, slot: slot, attempt: 0)
        }

        /// Two-phase settle:
        /// Phase 1 (attempt 0): animate toward an ESTIMATED position using average
        ///   row height. This moves the viewport close to the forced post, which
        ///   causes LazyVStack to render the cell and its ForcedCardMarker.
        /// Phase 2 (attempts 1-12): once the real marker appears, correct to the
        ///   exact position so the image is fully visible and perfectly centred.
        private func settleOnForced(in sv: UIScrollView, slot: Int, attempt: Int) {
            let delay: TimeInterval = attempt == 0 ? 0.04 : 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak sv] in
                guard let self, let sv else { return }

                if let target = self.forcedTarget(in: sv) {
                    // Real marker found → final precise animation.
                    UIView.animate(withDuration: attempt == 0 ? 0.85 : 0.3,
                                   delay: 0, options: [.curveEaseOut]) {
                        sv.contentOffset = CGPoint(x: 0, y: target)
                    }
                    return
                }

                if attempt == 0 {
                    // Marker not rendered yet → animate toward the estimate so that
                    // LazyVStack materialises the cell during the animation.
                    let estimate = self.estimatedTarget(for: slot, in: sv)
                    UIView.animate(withDuration: 0.85, delay: 0, options: [.curveEaseOut]) {
                        sv.contentOffset = CGPoint(x: 0, y: estimate)
                    }
                }

                if attempt < 12 {
                    self.settleOnForced(in: sv, slot: slot, attempt: attempt + 1)
                } else {
                    print("⚠️ [FORCE] forced image never materialised after \(attempt) retries")
                }
            }
        }

        /// Estimated content offset for the forced slot using average row height.
        /// Used only as a first-pass target to trigger cell materialisation.
        private func estimatedTarget(for slot: Int, in sv: UIScrollView) -> CGFloat {
            guard sv.contentSize.height > 0, totalPostCount > 0 else {
                return sv.contentOffset.y
            }
            let avg = sv.contentSize.height / CGFloat(totalPostCount)
            let topInset = sv.adjustedContentInset.top
            let botInset = sv.adjustedContentInset.bottom
            let visibleH = max(1, sv.bounds.height - topInset - botInset)
            // Centre the estimated cell in the viewport.
            let estimated = CGFloat(slot) * avg - topInset - (visibleH - avg) / 2
            let maxY = max(0, sv.contentSize.height + botInset - sv.bounds.height)
            return min(max(-topInset, estimated), maxY)
        }

        // MARK: - Geometry

        /// Content offset that shows the forced post's IMAGE fully visible: centered
        /// when it fits the viewport, top-pinned (small margin) when it is taller.
        private func forcedTarget(in sv: UIScrollView) -> CGFloat? {
            guard let marker = Self.findView(identifier: "forced_post_marker", in: sv) else { return nil }
            let topInset = sv.adjustedContentInset.top
            let botInset = sv.adjustedContentInset.bottom
            let visibleH = max(1, sv.bounds.height - topInset - botInset)

            let frame = marker.convert(marker.bounds, to: sv)
            let imageTop = frame.minY + sv.contentOffset.y
            let imageH = max(1, frame.height)

            let y: CGFloat
            if imageH >= visibleH - 8 {
                y = imageTop - topInset - 8                       // tall image: pin top
            } else {
                y = imageTop - topInset - (visibleH - imageH) / 2 // center, fully visible
            }
            let maxY = max(0, sv.contentSize.height + botInset - sv.bounds.height)
            return min(max(-topInset, y), maxY)
        }

        /// SwiftUI index of the slot where the forced post should be inserted: the
        /// first materialised cell whose top is at or below the viewport's bottom
        /// edge. Inserting there puts the forced post just under the fold (it pushes
        /// that cell down), so it stays invisible until we animate to it.
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

        private static func forEachCellMarker(in root: UIView, _ body: (Int, UIView) -> Void) {
            if let id = root.accessibilityIdentifier, id.hasPrefix("post_cell_"),
               let index = Int(id.dropFirst("post_cell_".count)) {
                body(index, root)
            }
            for sub in root.subviews { forEachCellMarker(in: sub, body) }
        }

        private static func findView(identifier: String, in root: UIView) -> UIView? {
            if root.accessibilityIdentifier == identifier { return root }
            for sub in root.subviews {
                if let found = findView(identifier: identifier, in: sub) { return found }
            }
            return nil
        }
    }
}

// MARK: - Markers

/// A real UIKit marker placed behind the forced post's IMAGE. Unlike a SwiftUI
/// `.accessibilityIdentifier` (which SwiftUI may strip from the rendered tree), this
/// guarantees a genuine `UIView` exists at the image's exact position and size, so the
/// interceptor can settle the scroll with the image fully visible on ANY device.
struct ForcedCardMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.accessibilityIdentifier = "forced_post_marker"
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityIdentifier = "forced_post_marker"
    }
}

/// A real UIKit marker placed behind EVERY post card, carrying that card's index in
/// its identifier ("post_cell_<index>"). It lets the interceptor map the scroll's real
/// geometry back to a SwiftUI index and insert the forced post exactly below the fold.
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
