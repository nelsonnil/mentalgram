import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Monitors physical volume button presses (up OR down) without showing the system HUD.
/// Keeps a single persistent MPVolumeView during monitoring so the slider reference
/// is always available for instant, reliable resets to 50%.
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
    private var isResetting = false

    private init() {}

    // MARK: - Public API

    /// Activates the audio session and warms up the volume view.
    /// Call when entering Performance view so the slider is ready before startMonitoring.
    func prepareVolume() {
        activateSession()
        setupPersistentVolumeView()
        // Give the view time to attach, then reset to 50%
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.resetVolume()
        }
    }

    /// Starts listening for volume button presses (up or down).
    func startMonitoring() {
        guard volumeObservation == nil else { return }
        activateSession()
        if cachedSlider == nil { setupPersistentVolumeView() }

        // Suppress spurious KVO fired during setup
        isResetting = true

        volumeObservation = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.old, .new]) { [weak self] session, change in
                guard let self, !self.isResetting else { return }
                let oldVol = change.oldValue ?? 0.5
                let newVol = change.newValue ?? 0.5
                let isUp = newVol > oldVol
                DispatchQueue.main.async {
                    self.triggerCount += 1
                    if isUp {
                        self.upCount += 1
                        print("🔊 [VOLUME] UP — trigger #\(self.triggerCount) (up #\(self.upCount))")
                    } else {
                        self.downCount += 1
                        print("🔊 [VOLUME] DOWN — trigger #\(self.triggerCount) (down #\(self.downCount))")
                    }
                    // Reset immediately using cached slider (no async view creation)
                    self.isResetting = true
                    self.resetVolume()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.isResetting = false
                    }
                }
            }

        // Open the gate after session settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isResetting = false
        }
    }

    /// Stops listening for volume button presses and removes the persistent view.
    func stopMonitoring() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        persistentVolumeView?.removeFromSuperview()
        persistentVolumeView = nil
        cachedSlider = nil
    }

    // MARK: - Private Helpers

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Creates (or reuses) a hidden MPVolumeView added to the key window.
    /// Caches the UISlider for fast subsequent resets.
    private func setupPersistentVolumeView() {
        guard persistentVolumeView == nil else { return }

        let vv = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        vv.alpha = 0.0001
        vv.isUserInteractionEnabled = false
        vv.showsVolumeSlider = true
        vv.showsRouteButton = false

        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window?.addSubview(vv)
        persistentVolumeView = vv

        // Cache slider after the view is in the hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak vv] in
            self?.cachedSlider = vv?.subviews.first(where: { $0 is UISlider }) as? UISlider
        }
    }

    /// Resets volume to 50% using the cached slider (fast, no view allocation).
    /// Falls back to creating a new view if the slider is not yet cached.
    private func resetVolume() {
        if let slider = cachedSlider {
            slider.value = 0.5
        } else {
            // Fallback: re-cache and retry once
            setupPersistentVolumeView()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.cachedSlider?.value = 0.5
            }
        }
    }
}
