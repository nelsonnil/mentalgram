import AVFoundation
import CoreImage
import Photos
import UIKit
import Vision

enum AIScreenCameraError: LocalizedError {
    case permissionDenied
    case unavailable
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission is not granted."
        case .unavailable: return "Camera is unavailable."
        case .captureFailed: return "Camera capture failed."
        }
    }
}

final class AIScreenCameraCaptureService: NSObject {
    static let shared = AIScreenCameraCaptureService()

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let imageContext = CIContext()
    private let sessionQueue = DispatchQueue(label: "com.vault.ai-screen-camera")
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var shouldCaptureNextFrame = false
    private var isConfigured = false
    private var lastWarmupAt: Date?
    private var burstFrames: [UIImage] = []
    private var captureTimeoutWorkItem: DispatchWorkItem?
    private var lastBurstFrameAt: Date?
    private let burstFrameTarget = 12
    private let burstFrameMinInterval: TimeInterval = 0.045

    private override init() {
        super.init()
    }

    func capturePhoto(zoom: CGFloat = 1.0) async throws -> UIImage {
        let granted = await requestCameraAccessIfNeeded()
        guard granted else { throw AIScreenCameraError.permissionDenied }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.continuation == nil else {
                    continuation.resume(throwing: AIScreenCameraError.captureFailed)
                    return
                }
                self.continuation = continuation
                do {
                    try self.configureIfNeeded()
                    let wasRunning = self.session.isRunning
                    if !wasRunning {
                        self.session.startRunning()
                    }
                    self.applyZoom(zoom)
                    let warmAge = self.lastWarmupAt.map { Date().timeIntervalSince($0) } ?? .infinity
                    let delay: TimeInterval = (wasRunning && warmAge < 30) ? 0.06 : 0.35
                    // Warm sessions can grab a frame almost immediately; cold sessions
                    // still need a short exposure/focus settle to avoid blurry text.
                    self.sessionQueue.asyncAfter(deadline: .now() + delay) {
                        self.burstFrames.removeAll(keepingCapacity: true)
                        self.lastBurstFrameAt = nil
                        self.shouldCaptureNextFrame = true
                        let timeout = DispatchWorkItem { [weak self] in
                            self?.finishBurstCapture()
                        }
                        self.captureTimeoutWorkItem = timeout
                        self.sessionQueue.asyncAfter(deadline: .now() + 0.95, execute: timeout)
                    }
                } catch {
                    self.continuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func prewarm(zoom: CGFloat = 1.0) async {
        let granted = await requestCameraAccessIfNeeded()
        guard granted else { return }

        sessionQueue.async {
            do {
                try self.configureIfNeeded()
                self.applyZoom(zoom)
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.lastWarmupAt = Date()
            } catch {
                print("⚠️ [AI SCREEN CAMERA] Prewarm failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.shouldCaptureNextFrame = false
            self.burstFrames.removeAll()
            self.lastBurstFrameAt = nil
            self.captureTimeoutWorkItem?.cancel()
            self.captureTimeoutWorkItem = nil
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(throwing: AIScreenCameraError.captureFailed)
            }
            self.lastWarmupAt = nil
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func requestCameraAccessIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw AIScreenCameraError.unavailable
        }

        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()

        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        session.addOutput(videoOutput)
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        session.commitConfiguration()
        isConfigured = true
    }

    private func applyZoom(_ zoom: CGFloat) {
        guard let input = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first else { return }
        let device = input.device
        try? device.lockForConfiguration()
        let clamped = min(max(zoom, 1.0), min(device.activeFormat.videoMaxZoomFactor, 6.0))
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
    }

    private func finishBurstCapture() {
        guard shouldCaptureNextFrame, let continuation else { return }
        shouldCaptureNextFrame = false
        self.continuation = nil
        captureTimeoutWorkItem?.cancel()
        captureTimeoutWorkItem = nil

        guard !burstFrames.isEmpty else {
            burstFrames.removeAll()
            lastWarmupAt = nil
            continuation.resume(throwing: AIScreenCameraError.captureFailed)
            sessionQueue.async { self.session.stopRunning() }
            return
        }

        let selected = selectBestFrame(from: burstFrames)
        saveSelectedCaptureToPhotosIfNeeded(selected)
        burstFrames.removeAll()
        lastBurstFrameAt = nil
        lastWarmupAt = nil
        continuation.resume(returning: selected)
        sessionQueue.async { self.session.stopRunning() }
    }

    private func selectBestFrame(from frames: [UIImage]) -> UIImage {
        let framesToScore: [UIImage] = {
            guard frames.count > 4 else { return frames }
            return Array(frames.dropFirst().dropLast())
        }()

        let preScored = framesToScore.map { frame in
            (image: frame, visual: visualQualityScore(frame))
        }
        let candidates = preScored
            .sorted { $0.visual > $1.visual }
            .prefix(3)

        return candidates
            .map { candidate in
                let textScore = localTextLegibilityScore(candidate.image)
                return (image: candidate.image, score: candidate.visual + textScore)
            }
            .max { $0.score < $1.score }?
            .image ?? frames[0]
    }

    private func visualQualityScore(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let edgeScore = averageIntensity(
            from: ciImage
                .applyingFilter("CIEdges", parameters: ["inputIntensity": 4.0])
                .cropped(to: extent)
        )
        let brightness = averageIntensity(from: ciImage)
        let exposureScore = max(0, 1.0 - abs(brightness - 0.52) * 2.2)
        return edgeScore * 2.0 + exposureScore
    }

    private func averageIntensity(from image: CIImage) -> Double {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return 0 }
        let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: image,
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        )
        guard let output = filter?.outputImage else { return 0 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        imageContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])) / (255.0 * 3.0)
    }

    private func localTextLegibilityScore(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0 }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "es-ES"]
        request.minimumTextHeight = 0.018

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImagePropertyOrientation(from: image.imageOrientation))
        do {
            try handler.perform([request])
            let strings = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            let joined = strings.joined(separator: " ").lowercased()
            let usernameLikeCount = strings.filter { text in
                text.range(of: #"@?[a-zA-Z0-9._]{3,30}"#, options: .regularExpression) != nil
            }.count
            let instagramHints = ["seguir", "seguidos", "publicaciones", "followers", "following", "posts", "me gusta"]
                .filter { joined.contains($0) }
                .count
            return min(Double(strings.count) * 0.08 + Double(usernameLikeCount) * 0.18 + Double(instagramHints) * 0.12, 1.2)
        } catch {
            return 0
        }
    }

    private func cgImagePropertyOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private func saveSelectedCaptureToPhotosIfNeeded(_ image: UIImage) {
        guard IntegrationsSettings.shared.transpositionSaveSelectedCaptureToPhotos else { return }
        guard let data = image.jpegData(compressionQuality: 0.95) else { return }

        Task {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            let granted: Bool
            switch status {
            case .authorized, .limited:
                granted = true
            case .notDetermined:
                let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                granted = requested == .authorized || requested == .limited
            default:
                granted = false
            }

            guard granted else {
                print("🖼️ [TRANSPOSITION] Selected capture not saved — Photos permission denied")
                return
            }

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    PHPhotoLibrary.shared().performChanges {
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: .photo, data: data, options: nil)
                    } completionHandler: { success, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: AIScreenCameraError.captureFailed)
                        }
                    }
                }
                print("🖼️ [TRANSPOSITION] Selected capture saved to Photos")
            } catch {
                print("🖼️ [TRANSPOSITION] Selected capture save failed: \(error.localizedDescription)")
            }
        }
    }
}

extension AIScreenCameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard shouldCaptureNextFrame else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            finishBurstCapture()
            lastWarmupAt = nil
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else {
            finishBurstCapture()
            lastWarmupAt = nil
            return
        }

        let now = Date()
        if let lastBurstFrameAt,
           now.timeIntervalSince(lastBurstFrameAt) < burstFrameMinInterval {
            return
        }
        lastBurstFrameAt = now
        burstFrames.append(UIImage(cgImage: cgImage))
        if burstFrames.count >= burstFrameTarget {
            finishBurstCapture()
        }
    }
}
