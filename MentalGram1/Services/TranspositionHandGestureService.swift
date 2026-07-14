import AVFoundation
import Vision

final class TranspositionHandGestureService: NSObject {
    static let shared = TranspositionHandGestureService()

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.vault.transposition-hand.camera")
    private let visionQueue = DispatchQueue(label: "com.vault.transposition-hand.vision")
    private var request = VNDetectHumanHandPoseRequest()
    private var isConfigured = false
    private var isProcessing = false
    private var lastTriggerAt: Date = .distantPast
    private var onOpenHand: (() -> Void)?

    private override init() {
        super.init()
        request.maximumHandCount = 1
    }

    func start(onOpenHand: @escaping () -> Void) {
        self.onOpenHand = onOpenHand
        sessionQueue.async {
            do {
                try self.configureIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                    print("🖐️ [TRANSPOSITION] Hand detector started")
                }
            } catch {
                print("🖐️ [TRANSPOSITION] Hand detector failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        onOpenHand = nil
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                print("🖐️ [TRANSPOSITION] Hand detector stopped")
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw AIScreenCameraError.unavailable
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
        session.addInput(input)
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        session.commitConfiguration()
        isConfigured = true
    }
}

extension TranspositionHandGestureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !isProcessing else { return }
        guard Date().timeIntervalSince(lastTriggerAt) > 0.6 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let orientations: [CGImagePropertyOrientation] = [.leftMirrored, .rightMirrored, .left, .right]
            for orientation in orientations {
                let request = VNDetectHumanHandPoseRequest()
                request.maximumHandCount = 1
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
                try handler.perform([request])
                guard let observation = request.results?.first else { continue }
                if isOpenHand(observation) {
                    lastTriggerAt = Date()
                    DispatchQueue.main.async { [weak self] in
                        self?.onOpenHand?()
                    }
                    return
                }
            }
        } catch {
            print("🖐️ [TRANSPOSITION] Hand Vision error: \(error.localizedDescription)")
        }
    }

    private func isOpenHand(_ observation: VNHumanHandPoseObservation) -> Bool {
        let tipNames: [VNHumanHandPoseObservation.JointName] = [
            .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
        ]
        guard let points = try? observation.recognizedPoints(.all) else { return false }
        let tips = tipNames.compactMap { points[$0] }.filter { $0.confidence > 0.28 }
        guard tips.count >= 4,
              let wrist = points[.wrist],
              wrist.confidence > 0.25 else { return false }

        let averageTipY = tips.map(\.location.y).reduce(0, +) / CGFloat(tips.count)
        let spreadX = (tips.map(\.location.x).max() ?? 0) - (tips.map(\.location.x).min() ?? 0)
        let spreadY = (tips.map(\.location.y).max() ?? 0) - (tips.map(\.location.y).min() ?? 0)
        let averageDistanceFromWrist = tips
            .map { hypot($0.location.x - wrist.location.x, $0.location.y - wrist.location.y) }
            .reduce(0, +) / CGFloat(tips.count)

        let upwardOpen = averageTipY > wrist.location.y + 0.05
        let broadPalm = spreadX > 0.12 || spreadY > 0.16
        return averageDistanceFromWrist > 0.16 && broadPalm && (upwardOpen || tips.count >= 5)
    }
}
