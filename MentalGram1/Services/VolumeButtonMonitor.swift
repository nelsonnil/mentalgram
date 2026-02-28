import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// Monitors physical volume button presses without showing the system volume HUD.
/// Resets volume to 50% silently after each press so subsequent presses are always detectable.
class VolumeButtonMonitor: ObservableObject {
    static let shared = VolumeButtonMonitor()

    /// Incremented every time a volume button press is detected.
    @Published private(set) var triggerCount: Int = 0

    private var volumeObservation: NSKeyValueObservation?
    private var isResetting = false

    private init() {}

    // MARK: - Public API

    /// Sets device volume to 50% silently (no HUD). Call when entering Performance view.
    func prepareVolume() {
        activateSession()
        setVolumeSilently(0.5)
    }

    /// Starts listening for volume button presses.
    func startMonitoring() {
        guard volumeObservation == nil else { return }
        activateSession()

        // Suppress any spurious KVO fired during the settling period
        // (e.g. from prepareVolume() or session activation).
        isResetting = true

        volumeObservation = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
                guard let self, !self.isResetting else { return }
                DispatchQueue.main.async {
                    self.triggerCount += 1
                    self.isResetting = true
                    self.setVolumeSilently(0.5)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isResetting = false
                    }
                }
            }

        // Open the gate after the session has settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isResetting = false
        }
    }

    /// Stops listening for volume button presses.
    func stopMonitoring() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }

    // MARK: - Private Helpers

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Sets volume without triggering the system HUD by using an off-screen MPVolumeView.
    private func setVolumeSilently(_ level: Float) {
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false

        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window?.addSubview(volumeView)

        // Slider must be set after the view is in the hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                slider.value = level
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                volumeView.removeFromSuperview()
            }
        }
    }
}
