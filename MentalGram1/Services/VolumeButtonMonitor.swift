import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Monitors physical volume button presses (up OR down) without showing the system HUD.
///
/// Reliability strategy:
/// 1. Keep system volume parked at ~50% so DOWN/UP always produce a KVO delta
///    (at 0.0, hardware DOWN is a no-op — the classic intermittent failure).
/// 2. Ignore only our own programmatic parks (by target match), never a long
///    time-based gate that swallows real presses.
/// 3. Keep `MPVolumeView` attached to the current key window (fullScreenCover /
///    scene changes otherwise leave a dead slider).
/// 4. Verify `outputVolume` after parking and retry until it sticks.
class VolumeButtonMonitor: ObservableObject {
    static let shared = VolumeButtonMonitor()

    /// Incremented every time a volume button press is detected (up or down).
    @Published private(set) var triggerCount: Int = 0

    /// Incremented only when the volume UP button is pressed.
    @Published private(set) var upCount: Int = 0

    /// Incremented only when the volume DOWN button is pressed.
    @Published private(set) var downCount: Int = 0

    private var volumeObservation: NSKeyValueObservation?
    private var persistentVolumeView: MPVolumeView?
    private var cachedSlider: UISlider?
    private var hasPrepared = false

    /// Volume we just wrote programmatically — KVO echoes matching this are ignored.
    private var pendingProgrammaticTarget: Float?
    private var lastProgrammaticSetAt: CFTimeInterval = 0

    /// Prevents spam re-parking when Instapick re-arms on every carousel appear.
    private var lastEnsureMidAt: CFTimeInterval = 0

    private var lifecycleObservers: [NSObjectProtocol] = []
    private var verifyWorkItem: DispatchWorkItem?

    /// True while the KVO observation is active (i.e. volume buttons are being tracked).
    var isMonitoring: Bool { volumeObservation != nil }

    /// Quiet mid level — far from 0/1 so both buttons always move `outputVolume`.
    private let parkLevel: Float = 0.5
    private let parkTolerance: Float = 0.045

    private init() {}

    // MARK: - Public API

    /// Marks that the volume system should be prepared.
    /// Does NOT touch the audio session or the window here — that happens
    /// lazily in startMonitoring() to avoid view-hierarchy side effects
    /// that can cause flicker on some devices.
    func prepareVolume() {
        hasPrepared = true
    }

    func setVolumeToMiddle() {
        ensureMidVolume(force: true, reason: "setVolumeToMiddle")
    }

    func setVolumeToMaximum() {
        parkVolume(1.0, reason: "setVolumeToMaximum")
    }

    /// Starts listening for volume button presses (up or down).
    /// All audio-session and MPVolumeView setup happens here (deferred from prepareVolume)
    /// so we never touch the window hierarchy during PerformanceView's .onAppear.
    func startMonitoring() {
        if volumeObservation != nil {
            // Already running — keep listening; only re-park if we drifted to a floor/ceiling.
            print("🔊 [VOLUME] startMonitoring() — already monitoring, ensuring mid volume")
            ensureMidVolume(force: false, reason: "startMonitoring-reuse")
            return
        }
        print("🔊 [VOLUME] startMonitoring() — starting fresh")
        activateSession()
        ensureVolumeViewInKeyWindow()
        installLifecycleObserversIfNeeded()

        volumeObservation = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                self?.handleOutputVolumeChange(
                    oldVol: change.oldValue ?? self?.parkLevel ?? 0.5,
                    newVol: change.newValue ?? self?.parkLevel ?? 0.5
                )
            }

        ensureMidVolume(force: true, reason: "startMonitoring-fresh")
    }

    /// Stops listening for volume button presses and removes the persistent view.
    func stopMonitoring() {
        guard volumeObservation != nil || persistentVolumeView != nil else { return }
        print("🔊 [VOLUME] stopMonitoring() called")
        volumeObservation?.invalidate()
        volumeObservation = nil
        verifyWorkItem?.cancel()
        verifyWorkItem = nil
        pendingProgrammaticTarget = nil
        removeLifecycleObservers()
        persistentVolumeView?.removeFromSuperview()
        persistentVolumeView = nil
        cachedSlider = nil
        hasPrepared = false
    }

    // MARK: - KVO

    private func handleOutputVolumeChange(oldVol: Float, newVol: Float) {
        // Ignore no-ops / floating noise.
        guard abs(newVol - oldVol) > 0.001 else { return }

        // Swallow echoes of our own park writes.
        if shouldIgnoreAsProgrammatic(oldVol: oldVol, newVol: newVol) {
            return
        }

        let isUp = newVol > oldVol
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Re-check on main in case a park landed in the meantime.
            if self.shouldIgnoreAsProgrammatic(oldVol: oldVol, newVol: newVol) {
                return
            }
            self.triggerCount += 1
            if isUp {
                self.upCount += 1
                print("🔊 [VOLUME] UP — trigger #\(self.triggerCount) (up #\(self.upCount)) vol \(oldVol)→\(newVol)")
            } else {
                self.downCount += 1
                print("🔊 [VOLUME] DOWN — trigger #\(self.triggerCount) (down #\(self.downCount)) vol \(oldVol)→\(newVol)")
            }
            // Re-park immediately so the next press cannot hit 0.0 / 1.0.
            self.parkVolume(self.parkLevel, reason: "after-press")
        }
    }

    private func shouldIgnoreAsProgrammatic(oldVol: Float, newVol: Float) -> Bool {
        guard let target = pendingProgrammaticTarget else { return false }
        let age = CACurrentMediaTime() - lastProgrammaticSetAt
        // Only consider recent parks (echo window). Real presses after that always count.
        guard age < 0.85 else {
            pendingProgrammaticTarget = nil
            return false
        }
        // Exact / near arrival at our target.
        if abs(newVol - target) <= parkTolerance {
            pendingProgrammaticTarget = nil
            return true
        }
        // Intermediate slider steps moving toward the target (not a user press).
        let movedTowardTarget = abs(newVol - target) < abs(oldVol - target) - 0.0005
        if movedTowardTarget {
            return true
        }
        // Moved away from target → real hardware press during park. Count it.
        return false
    }

    // MARK: - Mid volume parking

    /// Ensures volume sits near 50%. Safe to call often (carousel appear / page change).
    private func ensureMidVolume(force: Bool, reason: String) {
        activateSession()
        ensureVolumeViewInKeyWindow()

        let live = AVAudioSession.sharedInstance().outputVolume
        let now = CACurrentMediaTime()
        let recentlyEnsured = (now - lastEnsureMidAt) < 0.35
        let alreadyMid = abs(live - parkLevel) <= parkTolerance

        if !force, alreadyMid, recentlyEnsured {
            return
        }
        if !force, alreadyMid, live > 0.08, live < 0.92 {
            lastEnsureMidAt = now
            return
        }

        lastEnsureMidAt = now
        print("🔊 [VOLUME] ensureMid (\(reason)) live=\(String(format: "%.3f", live)) → \(parkLevel)")
        parkVolume(parkLevel, reason: reason)
    }

    private func parkVolume(_ value: Float, reason: String) {
        // Never park exactly at 0/1 while monitoring buttons — those edges make
        // one hardware direction a silent no-op. Maximum is only for explicit callers.
        let finalTarget: Float
        if reason == "setVolumeToMaximum" {
            finalTarget = 1.0
        } else if abs(value - parkLevel) < 0.01 {
            finalTarget = parkLevel
        } else {
            finalTarget = min(max(value, 0.05), 0.95)
        }

        activateSession()
        ensureVolumeViewInKeyWindow()
        pendingProgrammaticTarget = finalTarget
        lastProgrammaticSetAt = CACurrentMediaTime()

        applySliderValue(finalTarget)

        verifyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.verifyParked(finalTarget, attempt: 0)
        }
        verifyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func verifyParked(_ target: Float, attempt: Int) {
        guard isMonitoring || hasPrepared || persistentVolumeView != nil else { return }
        ensureVolumeViewInKeyWindow()
        let live = AVAudioSession.sharedInstance().outputVolume
        if abs(live - target) <= parkTolerance {
            // Keep the programmatic tag briefly so a late KVO echo is not
            // counted as a real hardware press.
            pendingProgrammaticTarget = target
            lastProgrammaticSetAt = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                guard let self else { return }
                if self.pendingProgrammaticTarget == target,
                   CACurrentMediaTime() - self.lastProgrammaticSetAt >= 0.27 {
                    self.pendingProgrammaticTarget = nil
                }
            }
            return
        }
        guard attempt < 8 else {
            print("⚠️ [VOLUME] park verify gave up — live=\(String(format: "%.3f", live)) target=\(target)")
            // Keep pending briefly so a late echo is still ignored, then clear.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.pendingProgrammaticTarget = nil
            }
            return
        }
        pendingProgrammaticTarget = target
        lastProgrammaticSetAt = CACurrentMediaTime()
        applySliderValue(target)
        let delay = 0.07 + Double(attempt) * 0.05
        let work = DispatchWorkItem { [weak self] in
            self?.verifyParked(target, attempt: attempt + 1)
        }
        verifyWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applySliderValue(_ value: Float) {
        refreshCachedSlider()
        if cachedSlider == nil {
            // Slider often appears one run-loop later — force another pass.
            DispatchQueue.main.async { [weak self] in
                self?.refreshCachedSlider()
                self?.cachedSlider?.value = value
            }
        }
        cachedSlider?.value = value
    }

    // MARK: - Session / MPVolumeView

    private func activateSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: .mixWithOthers)
            try session.setActive(true, options: [])
        } catch {
            print("⚠️ [VOLUME] audio session activate failed: \(error.localizedDescription)")
        }
    }

    /// Creates or re-parents the hidden MPVolumeView onto the current key window.
    private func ensureVolumeViewInKeyWindow() {
        let window = currentKeyWindow()

        if let vv = persistentVolumeView {
            if vv.window !== window {
                vv.removeFromSuperview()
                window?.addSubview(vv)
                cachedSlider = nil
                print("🔊 [VOLUME] MPVolumeView reattached to key window")
            }
            refreshCachedSlider()
            return
        }

        let vv = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        vv.alpha = 0.0001
        vv.isUserInteractionEnabled = false
        vv.showsVolumeSlider = true
        vv.showsRouteButton = false

        window?.addSubview(vv)
        persistentVolumeView = vv
        refreshCachedSlider()

        DispatchQueue.main.async { [weak self] in
            self?.refreshCachedSlider()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.refreshCachedSlider()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshCachedSlider()
        }
    }

    private func currentKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isHidden == false }
    }

    private func refreshCachedSlider() {
        guard let vv = persistentVolumeView else { return }
        if let slider = vv.subviews.first(where: { $0 is UISlider }) as? UISlider {
            cachedSlider = slider
        }
    }

    // MARK: - Lifecycle

    private func installLifecycleObserversIfNeeded() {
        guard lifecycleObservers.isEmpty else { return }

        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isMonitoring else { return }
            self.activateSession()
            self.ensureVolumeViewInKeyWindow()
            self.ensureMidVolume(force: false, reason: "didBecomeActive")
        })

        lifecycleObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self, self.isMonitoring else { return }
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            if type == .ended {
                self.activateSession()
                self.ensureVolumeViewInKeyWindow()
                self.ensureMidVolume(force: true, reason: "interruptionEnded")
            }
        })

        lifecycleObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isMonitoring else { return }
            self.ensureVolumeViewInKeyWindow()
            self.ensureMidVolume(force: false, reason: "routeChange")
        })
    }

    private func removeLifecycleObservers() {
        let center = NotificationCenter.default
        for token in lifecycleObservers {
            center.removeObserver(token)
        }
        lifecycleObservers.removeAll()
    }
}
