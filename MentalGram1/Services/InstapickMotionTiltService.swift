import Foundation
import CoreMotion
import Combine

/// Portrait device-tilt for Instapick card slide (ported from CardTiltLab).
/// Gravity is stored with a lock so the display-link tick can read it without
/// hopping through `Task { @MainActor }` every frame (that was dropping tilt).
final class InstapickMotionTiltService: ObservableObject {
    @Published private(set) var isRunning = false

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var storedX: Double = 0
    private var storedY: Double = 0

    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }

    /// Latest gravity sample (portrait: +x right, +y toward screen bottom).
    var currentGravity: (x: Double, y: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (storedX, storedY)
    }

    init() {
        queue.name = "Instapick.Motion"
        queue.maxConcurrentOperationCount = 1
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !isRunning else {
            if !manager.isDeviceMotionAvailable {
                print("⚠️ [INSTAPICK] DeviceMotion unavailable — tilt disabled")
            }
            return
        }
        isRunning = true
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                print("⚠️ [INSTAPICK] DeviceMotion error: \(error.localizedDescription)")
                return
            }
            guard let g = motion?.gravity else { return }
            // Portrait: x = left/right, y = toward user / away (flip so +y = screen bottom).
            let gx = g.x
            let gy = -g.y
            self.lock.lock()
            self.storedX = gx
            self.storedY = gy
            self.lock.unlock()
        }
        print("🃏 [INSTAPICK] Motion tilt started")
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
        lock.lock()
        storedX = 0
        storedY = 0
        lock.unlock()
    }
}
