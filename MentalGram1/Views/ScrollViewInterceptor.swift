import SwiftUI
import UIKit

/// Makes the feed land on the forced post — reliably, on every device and image size.
///
/// THE TRICK:
/// The forced post is NOT in the feed while the spectator browses. When the spectator
/// lifts their finger after swiping up, we:
///   1. Stop the momentum immediately.
///   2. Insert the forced post ~6 slots below the current viewport (invisible).
///   3. Animate to an estimated position so LazyVStack renders the cell.
///   4. Once the animation ends and the cell is rendered, read the real image frame
///      and snap precisely so the image is fully visible and centred.
///
/// WHY A GESTURE RECOGNIZER (not the scroll delegate):
/// SwiftUI owns the ScrollView's `delegate` on iOS 16 and may silently reclaim it, so
/// hijacking it is unreliable. We add our own UIPanGestureRecognizer (simultaneous,
/// non-cancelling) which SwiftUI cannot take away.
struct ScrollViewInterceptor: UIViewRepresentable {
    let isActive: Bool
    let totalPostCount: Int
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

    // MARK: - Hierarchy search

    static func findScrollView(in view: UIView) -> UIScrollView? {
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
            pan.cancelsTouchesInView = false
            sv.addGestureRecognizer(pan)
            panRecognizer = pan
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        // MARK: - Finger up

        @objc private func handlePan(_ g: UIPanGestureRecognizer) {
            guard isActive, !released, let sv = scrollView else { return }
            guard g.state == .ended else { return }

            // Swiping finger UP = browsing DOWN the feed.
            let velocity = g.velocity(in: sv)
            guard velocity.y < -80 else { return }
            guard sv.contentSize.height > 0, totalPostCount > 0 else { return }

            released = true

            // 1. Stop momentum so nothing gets revealed by inertia.
            sv.setContentOffset(sv.contentOffset, animated: false)

            // 2. Calculate insertion slot: first slot below the viewport + 6 extra,
            //    so the animation travels past ~6 real posts before the forced one.
            let avg = sv.contentSize.height / CGFloat(totalPostCount)
            let viewportBottom = sv.contentOffset.y + sv.bounds.height
            let baseSlot = Int((viewportBottom / avg).rounded(.up))
            let slot = min(baseSlot + 6, totalPostCount)
            print("🎯 [FORCE] inserting forced post at slot \(slot)")
            insertForced?(slot)

            // 3. Animate toward an estimate so LazyVStack renders the cell, then
            //    correct precisely once the real image marker appears.
            let estimate = estimatedTarget(for: slot, in: sv)
            UIView.animate(
                withDuration: 0.85, delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: { sv.contentOffset = CGPoint(x: 0, y: estimate) },
                completion: { [weak self, weak sv] _ in
                    guard let self, let sv else { return }
                    self.preciseSettle(in: sv, attempt: 0)
                }
            )
        }

        // MARK: - Precise settle after animation

        /// After the first animation the cell should be rendered. Read the real image
        /// marker and snap to show the image fully. Retries a few times in case
        /// layout hasn't finished on the first frame.
        private func preciseSettle(in sv: UIScrollView, attempt: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak sv] in
                guard let self, let sv else { return }
                guard let target = self.forcedTarget(in: sv) else {
                    if attempt < 6 { self.preciseSettle(in: sv, attempt: attempt + 1) }
                    else { print("⚠️ [FORCE] marker not found after \(attempt) retries") }
                    return
                }
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    sv.contentOffset = CGPoint(x: 0, y: target)
                }
            }
        }

        // MARK: - Geometry

        /// Estimated content offset for the given slot, using average row height.
        /// Only used for the initial animation to get LazyVStack to render the cell.
        private func estimatedTarget(for slot: Int, in sv: UIScrollView) -> CGFloat {
            let avg = sv.contentSize.height / CGFloat(max(1, totalPostCount))
            let topInset = sv.adjustedContentInset.top
            let botInset = sv.adjustedContentInset.bottom
            let visibleH = max(1, sv.bounds.height - topInset - botInset)
            // Centre the estimated slot vertically.
            let y = CGFloat(slot) * avg - topInset - (visibleH - avg) / 2
            return clamped(y, in: sv)
        }

        /// Precise content offset that shows the forced post's IMAGE fully visible:
        /// centred when it fits, top-pinned with a small margin when it is taller.
        private func forcedTarget(in sv: UIScrollView) -> CGFloat? {
            guard let marker = Self.findView(id: "forced_post_marker", in: sv) else { return nil }
            let topInset = sv.adjustedContentInset.top
            let botInset = sv.adjustedContentInset.bottom
            let visibleH = max(1, sv.bounds.height - topInset - botInset)

            let frame = marker.convert(marker.bounds, to: sv)
            let imageTop = frame.minY + sv.contentOffset.y
            let imageH   = max(1, frame.height)

            let y: CGFloat
            if imageH >= visibleH - 8 {
                y = imageTop - topInset - 8
            } else {
                y = imageTop - topInset - (visibleH - imageH) / 2
            }
            return clamped(y, in: sv)
        }

        private func clamped(_ y: CGFloat, in sv: UIScrollView) -> CGFloat {
            let top  = -sv.adjustedContentInset.top
            let maxY = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
            return min(max(top, y), maxY)
        }

        private static func findView(id: String, in root: UIView) -> UIView? {
            if root.accessibilityIdentifier == id { return root }
            for sub in root.subviews {
                if let found = findView(id: id, in: sub) { return found }
            }
            return nil
        }
    }
}

// MARK: - Forced image marker

/// A real UIKit view placed behind the forced post's IMAGE. Unlike a SwiftUI
/// `.accessibilityIdentifier` (which SwiftUI may strip), this guarantees a `UIView`
/// at the image's exact position, so `ScrollViewInterceptor` can settle the scroll
/// with the image fully visible on any device and image size.
struct ForcedCardMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.accessibilityIdentifier = "forced_post_marker"
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
