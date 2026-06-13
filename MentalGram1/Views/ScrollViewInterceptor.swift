import SwiftUI
import UIKit

/// Makes the feed "naturally" land on the forced post.
///
/// THE TRICK (hidden-post design — robust on every device):
/// The forced post is NOT in the feed at all while the spectator browses; it cannot
/// be seen by scrolling fast or far. When the spectator flicks downward, UIKit tells
/// us exactly where that flick would naturally stop (`targetContentOffset`). At that
/// moment we INSERT the forced post into the landing slot — always below anything
/// already seen, so the insertion is invisible — and glide the scroll there with a
/// spring that inherits the finger's velocity. Result: a soft flick travels a
/// little, a hard flick travels far, and wherever the scroll stops, the forced post
/// is the one on screen, centered.
///
/// Anti-oscillation guarantees:
/// - Initial spring velocity is capped at the critical value (no overshoot).
/// - The glide is monotonic: it never reverses direction. If layout settles the
///   ideal center slightly behind us, we release where we are instead of backing up.
struct ScrollViewInterceptor: UIViewRepresentable {
    /// Index of the forced post in the CURRENT display list, or -1 while hidden.
    let forcedIndex: Int
    let totalPostCount: Int
    @Binding var hasActivated: Bool
    let isActive: Bool
    var forcedThumbnail: UIImage? = nil
    /// Asks SwiftUI to insert the forced post at the requested slot.
    /// Returns the post's final index (or -1 when impossible).
    var insertForcedPost: ((Int) -> Int)? = nil

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
        c.forcedIndex         = forcedIndex
        c.totalPostCount      = totalPostCount
        c.isActive            = isActive
        c.hasActivatedBinding = $hasActivated
        c.insertForcedPost    = insertForcedPost
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
        var forcedIndex: Int = -1
        var totalPostCount: Int = 1
        var hasActivatedBinding: Binding<Bool>?
        var insertForcedPost: ((Int) -> Int)?

        /// Once true, the trick is done and all scrolling is normal.
        private var released = false
        private weak var originalDelegate: UIScrollViewDelegate?
        private weak var attachedScrollView: UIScrollView?

        /// Bottom-most content Y the spectator has ever had on screen. The forced
        /// post is only inserted BELOW this line, so the insertion is invisible.
        private var maxSeenContentY: CGFloat = 0

        // ── Custom glide animation (CADisplayLink driven) ────────────────────
        private var displayLink: CADisplayLink?
        private var glideY: CGFloat = 0          // animated content offset
        private var glideV: CGFloat = 0          // animated velocity (pts/s)
        private var lastFrameTime: CFTimeInterval = 0
        /// Spring stiffness — settles in ≈1.2 s, close to UIKit's own deceleration.
        private let springOmega: CGFloat = 3.2

        /// Tracks the last isActive value to detect re-entry.
        private var lastIsActive = false
        var isActive = false {
            didSet {
                // Fresh activation (false → true): reset so the trick runs again.
                if isActive && !lastIsActive {
                    released = false
                    maxSeenContentY = 0
                    stopGlide()
                }
                lastIsActive = isActive
            }
        }

        init(parent: ScrollViewInterceptor) {
            self.forcedIndex      = parent.forcedIndex
            self.totalPostCount   = parent.totalPostCount
            self.isActive         = parent.isActive
            self.lastIsActive     = parent.isActive
            self.insertForcedPost = parent.insertForcedPost
        }

        deinit { displayLink?.invalidate() }

        func attach(to scrollView: UIScrollView) {
            originalDelegate = scrollView.delegate
            attachedScrollView = scrollView
            maxSeenContentY = scrollView.contentOffset.y + scrollView.bounds.height
            scrollView.delegate = self
        }

        // MARK: - Finger lift → insert forced post at the natural landing slot

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            originalDelegate?.scrollViewWillEndDragging?(
                scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset
            )

            guard isActive && !released else { return }

            // Upward or near-zero flicks scroll 100% naturally; the trick fires on
            // the next downward flick (spectators browse a feed downward).
            let vY = velocity.y   // points per millisecond; > 0 = scrolling down
            guard vY > 0.05 else { return }

            // UIKit's exact natural landing offset for this flick — what makes the
            // motion length feel genuine for slow AND fast scrolls on any screen.
            let naturalY = targetContentOffset.pointee.y

            let topInset  = scrollView.adjustedContentInset.top
            let botInset  = scrollView.adjustedContentInset.bottom
            let visibleH  = max(1, scrollView.bounds.height - topInset - botInset)
            let contentH  = scrollView.contentSize.height
            guard contentH > 0, totalPostCount > 0 else { return }
            let avg = contentH / CGFloat(totalPostCount)

            if forcedIndex < 0 {
                // Hidden → insert into the slot centered at the natural landing,
                // clamped below everything the spectator has already seen.
                let landingCenterY = naturalY + topInset + visibleH / 2
                var slot = Int((landingCenterY / avg).rounded(.down))
                let firstUnseen = Int((maxSeenContentY / avg).rounded(.down)) + 1
                slot = max(slot, firstUnseen)
                slot = min(slot, totalPostCount)
                guard let newIdx = insertForcedPost?(slot), newIdx >= 0 else { return }
                forcedIndex = newIdx
                totalPostCount += 1
                print("🎯 [FORCE] inserted forced post at slot \(newIdx) (natural landing ≈ \(Int(naturalY)))")
            } else {
                // Already inserted by a previous (interrupted) flick. If it has been
                // seen, only intervene when it still lies below the current view.
                let forcedTopAbs = markerAbsoluteY(in: scrollView) ?? CGFloat(forcedIndex) * avg
                if forcedTopAbs < maxSeenContentY {
                    let viewportBottomAbs = scrollView.contentOffset.y + scrollView.bounds.height
                    guard forcedTopAbs > viewportBottomAbs else { return }
                }
            }

            // Glide target (estimate now; refined per-frame from real geometry).
            guard let target = desiredY(in: scrollView) else { return }
            let delta = target - scrollView.contentOffset.y
            guard delta > 1 else { return }   // never glide upward

            // Take over the deceleration. Initial velocity inherits the finger speed
            // but is capped at the spring's critical value → can NEVER overshoot,
            // which is what previously caused the up-and-down wobble.
            targetContentOffset.pointee = scrollView.contentOffset
            let v0 = max(150, min(vY * 1000, springOmega * delta))
            startGlide(in: scrollView, initialVelocity: v0)
        }

        func scrollViewWillBeginDragging(_ sv: UIScrollView) {
            originalDelegate?.scrollViewWillBeginDragging?(sv)
            // User touched down again — hand control back instantly.
            stopGlide()
        }

        // MARK: - Glide animation

        private func startGlide(in sv: UIScrollView, initialVelocity: CGFloat) {
            attachedScrollView = sv
            glideY = sv.contentOffset.y
            glideV = initialVelocity
            lastFrameTime = CACurrentMediaTime()

            displayLink?.invalidate()
            let dl = CADisplayLink(target: self, selector: #selector(stepGlide(_:)))
            dl.add(to: .main, forMode: .common)
            displayLink = dl
        }

        func stopGlide() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func stepGlide(_ dl: CADisplayLink) {
            guard let sv = attachedScrollView, isActive, !released else {
                stopGlide()
                return
            }

            let now = dl.timestamp
            let dt = CGFloat(min(max(now - lastFrameTime, 1.0 / 120.0), 1.0 / 30.0))
            lastFrameTime = now

            // Refine the target every frame: as cells materialise during the glide
            // the forced card's REAL geometry becomes available and centering
            // becomes exact. Changes are small because the post was inserted in the
            // landing zone, so the spring absorbs them smoothly.
            guard let target = desiredY(in: sv) else {
                stopGlide()
                return
            }

            let delta = target - glideY

            // MONOTONIC GUARD: if the ideal center ended up behind us (layout shifted
            // upward while cells materialised), settle right here — never scroll back.
            if delta < -24 {
                sv.setContentOffset(CGPoint(x: 0, y: clampedY(glideY, in: sv)), animated: false)
                stopGlide()
                finishRelease()
                return
            }

            // Critically-damped spring: natural ease-out, no oscillation.
            let accel = springOmega * springOmega * delta - 2 * springOmega * glideV
            glideV += accel * dt
            glideV = max(glideV, -120)   // tiny easing allowed, no visible reversal
            glideY += glideV * dt

            sv.setContentOffset(CGPoint(x: 0, y: clampedY(glideY, in: sv)), animated: false)

            // Settled with the forced post centered → land exactly and release.
            if abs(delta) < 0.5 && abs(glideV) < 8 {
                sv.setContentOffset(CGPoint(x: 0, y: clampedY(target, in: sv)), animated: false)
                stopGlide()
                finishRelease()
            }
        }

        private func finishRelease() {
            released = true
            print("🎯 [FORCE] settled on forced post — trick released")
            DispatchQueue.main.async { [weak self] in
                self?.hasActivatedBinding?.wrappedValue = true
            }
        }

        // MARK: - Target computation

        /// Content offset that shows the forced post fully visible and CENTERED in
        /// the viewport (top-pinned with a margin when taller than the screen).
        private func desiredY(in sv: UIScrollView) -> CGFloat? {
            guard forcedIndex >= 0 else { return nil }
            let topInset = sv.adjustedContentInset.top
            let botInset = sv.adjustedContentInset.bottom
            let visibleH = max(1, sv.bounds.height - topInset - botInset)

            // ── Precise: real UIKit marker behind the forced card ────────────────
            if let marker = findMarker(in: sv) {
                let frame = marker.convert(marker.bounds, to: sv)
                let cardTop = frame.minY + sv.contentOffset.y
                let cardH = max(1, frame.height)

                let y: CGFloat
                if cardH >= visibleH - 16 {
                    y = cardTop - topInset - 8                      // tall card: pin top
                } else {
                    y = cardTop - topInset - (visibleH - cardH) / 2 // center, fully visible
                }
                return clampedY(y, in: sv)
            }

            // ── Estimate (until the card materialises): average row height ──────
            let contentH = sv.contentSize.height
            guard contentH > 0, totalPostCount > 0 else { return nil }
            let avg = contentH / CGFloat(totalPostCount)
            let cardTop = CGFloat(forcedIndex) * avg
            let cardH = min(avg, visibleH)
            let y = cardTop - topInset - max(0, (visibleH - cardH) / 2)
            return clampedY(y, in: sv)
        }

        /// Absolute content-Y of the forced card's top, when it is materialised.
        private func markerAbsoluteY(in sv: UIScrollView) -> CGFloat? {
            guard let marker = findMarker(in: sv) else { return nil }
            let frame = marker.convert(marker.bounds, to: sv)
            return frame.minY + sv.contentOffset.y
        }

        private func findMarker(in sv: UIScrollView) -> UIView? {
            Self.findView(identifier: "forced_post_marker", in: sv)
                ?? Self.findView(identifier: "forced_post_card", in: sv)
        }

        private func clampedY(_ y: CGFloat, in sv: UIScrollView) -> CGFloat {
            let maxY = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - sv.bounds.height)
            return min(max(-sv.adjustedContentInset.top, y), maxY)
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
            // Track how far down the spectator has ever seen (for invisible insertion).
            if isActive && !released {
                maxSeenContentY = max(maxSeenContentY, sv.contentOffset.y + sv.bounds.height)
            }
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

// MARK: - Forced Card Marker

/// A real UIKit marker view placed behind the forced post card. Unlike a SwiftUI
/// `.accessibilityIdentifier` (which SwiftUI may strip from the rendered UIKit tree),
/// this guarantees a genuine `UIView` carrying the identifier exists at the card's
/// exact position and size, so `ScrollViewInterceptor` can read precise geometry
/// on ANY device.
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
