import SwiftUI
import UIKit

/// Makes the feed land on the forced post — reliably, on every device and image size.
///
/// THE TRICK:
/// The forced post is NOT in the feed while the spectator browses. When the spectator
/// lifts their finger after swiping up, this bridge:
///   1. Stops the momentum immediately (so nothing is revealed by inertia).
///   2. Calls `insertForced(slot)` to insert the hidden post just below the fold.
///   3. Calls `onInserted()` so SwiftUI can animate to the post with `scrollTo`.
///
/// WHY A GESTURE RECOGNIZER (not the scroll delegate):
/// SwiftUI owns the ScrollView's `delegate` on iOS 16 and may silently reclaim it, so
/// hijacking it is unreliable. We add our own UIPanGestureRecognizer (simultaneous,
/// non-cancelling) which SwiftUI cannot take away.
///
/// WHY SwiftUI handles the final animation (not UIView.animate):
/// Calling `UIView.animate { scrollView.contentOffset = … }` conflicts with
/// UIScrollView's own deceleration engine, causing the scroll to continue
/// unexpectedly after the animation. SwiftUI's `proxy.scrollTo` works through the
/// correct channel and handles centering for any screen/image size.
struct ScrollViewInterceptor: UIViewRepresentable {
    let isActive: Bool
    let totalPostCount: Int
    /// Inserts the forced post at the given SwiftUI index (just below the fold).
    var insertForced: ((Int) -> Void)? = nil
    /// Called right after insertion so SwiftUI can animate to the post.
    var onInserted: (() -> Void)? = nil

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
        c.onInserted     = onInserted
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
        var onInserted: (() -> Void)?

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
            self.onInserted     = parent.onInserted
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
            //    so SwiftUI's scrollTo animation travels past ~6 real posts.
            let avg = sv.contentSize.height / CGFloat(totalPostCount)
            let viewportBottom = sv.contentOffset.y + sv.bounds.height
            let baseSlot = Int((viewportBottom / avg).rounded(.up))
            let slot = min(baseSlot + 6, totalPostCount)
            print("🎯 [FORCE] inserting forced post at slot \(slot)")

            // 3. Insert the forced post (invisible, below the fold).
            insertForced?(slot)

            // 4. Wait one runloop so SwiftUI processes the state update, then tell
            //    SwiftUI to animate to the post. SwiftUI's scrollTo works through the
            //    correct channel and handles any screen/image size perfectly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.onInserted?()
            }
        }
    }
}

// MARK: - Forced image marker

/// A real UIKit view placed behind the forced post's IMAGE. Ensures a `UIView` exists
/// at the image's exact position for geometry-based centering if needed.
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
