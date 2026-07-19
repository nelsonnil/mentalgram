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

/// Live readiness snapshot for Camera Test HUD (mirrors arming logic).
struct AIScreenCaptureReadiness: Equatable {
    let hasTopSignal: Bool
    let hasBottomSignal: Bool
    let isSoftReadable: Bool
    let isCompletePostFrame: Bool
    let ocrScore: Double
    let layoutScore: Double
    let previewTokens: [String]

    var phaseLabel: String {
        if isCompletePostFrame { return "READY — would fire + vibrate" }
        if isSoftReadable { return "Partial — keep moving" }
        if hasTopSignal || hasBottomSignal { return "Searching Instagram UI…" }
        return "Aim at the spectator screen"
    }
}

final class AIScreenCameraCaptureService: NSObject {
    static let shared = AIScreenCameraCaptureService()

    private struct SmartCaptureCandidate {
        let image: UIImage
        let capturedAt: Date
        let visualScore: Double
        let ocrScore: Double
        let meanConfidence: Double
        let layoutScore: Double
        let usefulTokens: [String]
        let lineCount: Int
        let hasTopSignal: Bool
        let hasBottomSignal: Bool
        let isCompletePostFrame: Bool
        /// True once a complete (or fallback) frame armed the burst.
        let afterReady: Bool
    }

    private struct SmartTextObservation {
        let token: String
        let capturedAt: Date
    }

    private struct FrameTextMetrics {
        let score: Double
        let usefulTokens: [String]
        let lineCount: Int
        let meanConfidence: Double
        let layoutScore: Double
        let hasTopSignal: Bool
        let hasBottomSignal: Bool
        let isCompletePostFrame: Bool
        let isSoftReadable: Bool
    }

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let imageContext = CIContext()
    private let sessionQueue = DispatchQueue(label: "com.vault.ai-screen-camera")
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var shouldCaptureNextFrame = false
    private var isConfigured = false
    private var lastWarmupAt: Date?
    private var smartCaptureCandidates: [SmartCaptureCandidate] = []
    private var smartTextObservations: [SmartTextObservation] = []
    private var lastOCRFrameAt: Date?
    /// First soft-readable OCR (partial screen OK) — used only for timeout fallback.
    private var softReadableAt: Date?
    /// First complete post frame (header + engagement) → start burst.
    private var smartReadyAt: Date?
    private var postReadySampleCount = 0
    private var armedViaFallback = false
    private var activeCaptureMode: TranspositionCaptureMode = .videoFrames
    private var isCapturingStillBurst = false
    private var stillBurstImages: [UIImage] = []
    private var stillBurstAttemptCount = 0
    private let smartFrameMinInterval: TimeInterval = 0.08
    private let smartTextWindow: TimeInterval = 2.8
    /// After a complete frame, keep ~6 more samples (~0.5s) then pick best coverage.
    private let smartBurstSampleCount = 6
    /// Hybrid mode: high-res stills after video OCR arms.
    private let hybridStillBurstCount = 3
    /// If magician never gets a full frame, don't hang forever.
    private let smartPartialFallbackTimeout: TimeInterval = 2.6
    private let smartMaxCandidateCount = 16
    private let smartMinimumUsefulTokens = 5
    private let smartMinimumLineCount = 2
    private let smartMinimumOCRScore = 0.55
    /// Extreme motion-blur veto only — OCR/layout remain the main ranking signals.
    private let smartBlurVetoVisualScore = 0.12
    private(set) var lastSmartCaptureOCRText = ""

    private override init() {
        super.init()
    }

    /// Same OCR/layout gates used when arming Visual Match (for Camera Test HUD).
    func evaluateCaptureReadiness(in image: UIImage) -> AIScreenCaptureReadiness {
        let metrics = localTextMetrics(image)
        return AIScreenCaptureReadiness(
            hasTopSignal: metrics.hasTopSignal,
            hasBottomSignal: metrics.hasBottomSignal,
            isSoftReadable: metrics.isSoftReadable,
            isCompletePostFrame: metrics.isCompletePostFrame,
            ocrScore: metrics.score,
            layoutScore: metrics.layoutScore,
            previewTokens: Array(metrics.usefulTokens.prefix(8))
        )
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
                    // Still-photo hybrid makes shutter clicks — always use silent video frames.
                    self.activeCaptureMode = .videoFrames
                    let wasRunning = self.session.isRunning
                    if !wasRunning {
                        self.session.startRunning()
                    }
                    self.applyZoom(zoom)
                    let warmAge = self.lastWarmupAt.map { Date().timeIntervalSince($0) } ?? .infinity
                    let delay: TimeInterval = (wasRunning && warmAge < 30) ? 0.06 : 0.35
                    // Warm sessions can start OCR almost immediately; cold sessions
                    // still need a short exposure/focus settle to avoid blurry text.
                    self.sessionQueue.asyncAfter(deadline: .now() + delay) {
                        self.resetSmartCaptureState()
                        self.shouldCaptureNextFrame = true
                        print("📸 [SMART CAPTURE] Armed mode=\(self.activeCaptureMode.rawValue)")
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
            self.isCapturingStillBurst = false
            self.resetSmartCaptureState()
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
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            if #available(iOS 16.0, *) {
                photoOutput.maxPhotoQualityPrioritization = .quality
            }
        }
        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoOrientationSupported {
            photoConnection.videoOrientation = .portrait
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

    private func finishSmartCapture(with selected: UIImage) {
        guard shouldCaptureNextFrame || isCapturingStillBurst, let continuation else { return }
        shouldCaptureNextFrame = false
        isCapturingStillBurst = false
        self.continuation = nil
        lastSmartCaptureOCRText = accumulatedOCRText()
        saveSelectedCaptureToPhotosIfNeeded(selected)
        resetSmartCaptureState(keepLastOCRText: true)
        lastWarmupAt = nil
        continuation.resume(returning: selected)
        sessionQueue.async { self.session.stopRunning() }
    }

    private func failSmartCapture() {
        guard let continuation else { return }
        shouldCaptureNextFrame = false
        isCapturingStillBurst = false
        self.continuation = nil
        resetSmartCaptureState()
        lastWarmupAt = nil
        continuation.resume(throwing: AIScreenCameraError.captureFailed)
        sessionQueue.async { self.session.stopRunning() }
    }

    private func resetSmartCaptureState(keepLastOCRText: Bool = false) {
        smartCaptureCandidates.removeAll(keepingCapacity: true)
        smartTextObservations.removeAll(keepingCapacity: true)
        lastOCRFrameAt = nil
        softReadableAt = nil
        smartReadyAt = nil
        postReadySampleCount = 0
        armedViaFallback = false
        isCapturingStillBurst = false
        stillBurstImages.removeAll(keepingCapacity: true)
        stillBurstAttemptCount = 0
        if !keepLastOCRText {
            lastSmartCaptureOCRText = ""
        }
    }

    private func processSmartCaptureFrame(_ image: UIImage, capturedAt now: Date) {
        guard !isCapturingStillBurst else { return }
        if let lastOCRFrameAt,
           now.timeIntervalSince(lastOCRFrameAt) < smartFrameMinInterval {
            return
        }
        lastOCRFrameAt = now

        let visualScore = visualQualityScore(image)
        let metrics = localTextMetrics(image)
        rememberSmartText(tokens: metrics.usefulTokens, capturedAt: now)

        if metrics.isSoftReadable, softReadableAt == nil {
            softReadableAt = now
        }

        let wasReady = smartReadyAt != nil
        if !wasReady {
            if metrics.isCompletePostFrame {
                smartReadyAt = now
                armedViaFallback = false
                if activeCaptureMode == .hybridStillBurst {
                    print("📸 [SMART CAPTURE] mode=hybrid Full post frame — starting \(hybridStillBurstCount)-still burst")
                } else {
                    print("📸 [SMART CAPTURE] mode=video Full post frame — bursting \(smartBurstSampleCount) frames")
                }
            } else if let softAt = softReadableAt,
                      now.timeIntervalSince(softAt) >= smartPartialFallbackTimeout,
                      metrics.isSoftReadable {
                // Magician kept a partial crop too long — take best available rather than hang.
                smartReadyAt = now
                armedViaFallback = true
                if activeCaptureMode == .hybridStillBurst {
                    print("📸 [SMART CAPTURE] mode=hybrid Partial timeout — still burst on best available")
                } else {
                    print("📸 [SMART CAPTURE] mode=video Partial timeout — bursting best available")
                }
            }
        }

        let afterReady = smartReadyAt != nil
        let candidate = SmartCaptureCandidate(
            image: image,
            capturedAt: now,
            visualScore: visualScore,
            ocrScore: metrics.score,
            meanConfidence: metrics.meanConfidence,
            layoutScore: metrics.layoutScore,
            usefulTokens: metrics.usefulTokens,
            lineCount: metrics.lineCount,
            hasTopSignal: metrics.hasTopSignal,
            hasBottomSignal: metrics.hasBottomSignal,
            isCompletePostFrame: metrics.isCompletePostFrame,
            afterReady: afterReady
        )
        rememberSmartCaptureCandidate(candidate)

        // Just armed: hybrid fires stills immediately; video keeps sampling frames.
        if !wasReady, afterReady, activeCaptureMode == .hybridStillBurst {
            beginHybridStillBurst()
            return
        }

        guard wasReady, activeCaptureMode == .videoFrames else { return }

        postReadySampleCount += 1
        guard postReadySampleCount >= smartBurstSampleCount else { return }
        guard let selected = selectBestSmartCaptureFrame(now: now) else { return }
        print("📸 [SMART CAPTURE] mode=video Burst done (\(postReadySampleCount)) fallback=\(armedViaFallback) — sending best coverage frame")
        finishSmartCapture(with: selected)
    }

    private func beginHybridStillBurst() {
        guard !isCapturingStillBurst else { return }
        guard session.outputs.contains(where: { $0 === photoOutput }) else {
            print("⚠️ [SMART CAPTURE] mode=hybrid photo output missing — falling back to video frame")
            finishWithBestVideoFallback(reason: "no_photo_output")
            return
        }
        isCapturingStillBurst = true
        shouldCaptureNextFrame = false
        stillBurstImages.removeAll(keepingCapacity: true)
        stillBurstAttemptCount = 0
        print("📸 [SMART CAPTURE] mode=hybrid Capturing still 1/\(hybridStillBurstCount)")
        captureNextStillInBurst()
    }

    private func captureNextStillInBurst() {
        stillBurstAttemptCount += 1
        let settings = AVCapturePhotoSettings()
        if #available(iOS 16.0, *) {
            settings.photoQualityPrioritization = .quality
        }
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func handleStillBurstPhoto(_ image: UIImage?) {
        if let image {
            stillBurstImages.append(image)
            print("📸 [SMART CAPTURE] mode=hybrid still \(stillBurstImages.count)/\(hybridStillBurstCount) ok (attempt \(stillBurstAttemptCount))")
        } else {
            print("⚠️ [SMART CAPTURE] mode=hybrid still failed (attempt \(stillBurstAttemptCount))")
        }

        let maxAttempts = hybridStillBurstCount + 2
        if stillBurstImages.count < hybridStillBurstCount, stillBurstAttemptCount < maxAttempts {
            let next = stillBurstImages.count + 1
            print("📸 [SMART CAPTURE] mode=hybrid Capturing still \(next)/\(hybridStillBurstCount)")
            sessionQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.isCapturingStillBurst else { return }
                self.captureNextStillInBurst()
            }
            return
        }

        finalizeHybridStillBurst()
    }

    private func finalizeHybridStillBurst() {
        guard isCapturingStillBurst else { return }
        if stillBurstImages.isEmpty {
            print("⚠️ [SMART CAPTURE] mode=hybrid still burst empty — falling back to video frame")
            finishWithBestVideoFallback(reason: "still_burst_empty")
            return
        }

        let now = Date()
        var bestImage: UIImage?
        var bestScore = -Double.infinity
        for image in stillBurstImages {
            let metrics = localTextMetrics(image)
            let visual = visualQualityScore(image)
            let candidate = SmartCaptureCandidate(
                image: image,
                capturedAt: now,
                visualScore: visual,
                ocrScore: metrics.score,
                meanConfidence: metrics.meanConfidence,
                layoutScore: metrics.layoutScore,
                usefulTokens: metrics.usefulTokens,
                lineCount: metrics.lineCount,
                hasTopSignal: metrics.hasTopSignal,
                hasBottomSignal: metrics.hasBottomSignal,
                isCompletePostFrame: metrics.isCompletePostFrame,
                afterReady: true
            )
            rememberSmartText(tokens: metrics.usefulTokens, capturedAt: now)
            let score = selectionScore(candidate)
            if score > bestScore {
                bestScore = score
                bestImage = image
            }
        }

        guard let selected = bestImage else {
            finishWithBestVideoFallback(reason: "still_score_failed")
            return
        }
        print("📸 [SMART CAPTURE] mode=hybrid chose still score=\(String(format: "%.2f", bestScore)) from \(stillBurstImages.count) photos fallbackArm=\(armedViaFallback)")
        finishSmartCapture(with: selected)
    }

    private func finishWithBestVideoFallback(reason: String) {
        let now = Date()
        if let selected = selectBestSmartCaptureFrame(now: now) {
            print("📸 [SMART CAPTURE] mode=hybrid video fallback (\(reason))")
            // Re-enable finish gate: still path may have cleared shouldCaptureNextFrame.
            shouldCaptureNextFrame = true
            isCapturingStillBurst = true
            finishSmartCapture(with: selected)
            return
        }
        failSmartCapture()
    }

    private func rememberSmartCaptureCandidate(_ candidate: SmartCaptureCandidate) {
        smartCaptureCandidates.append(candidate)
        smartCaptureCandidates.sort { lhs, rhs in
            let left = selectionScore(lhs)
            let right = selectionScore(rhs)
            if abs(left - right) < 0.05 {
                return lhs.capturedAt > rhs.capturedAt
            }
            return left > right
        }
        if smartCaptureCandidates.count > smartMaxCandidateCount {
            smartCaptureCandidates.removeLast(smartCaptureCandidates.count - smartMaxCandidateCount)
        }
    }

    /// Prefer full-screen Instagram coverage (header + counters) and useful OCR data for GPT.
    private func selectionScore(_ candidate: SmartCaptureCandidate) -> Double {
        var score = candidate.layoutScore * 1.35
        score += candidate.ocrScore * 0.85
        score += candidate.meanConfidence * 0.30
        score += min(max(candidate.visualScore, 0), 1.0) * 0.18
        if candidate.isCompletePostFrame { score += 0.55 }
        if candidate.hasTopSignal { score += 0.12 }
        if candidate.hasBottomSignal { score += 0.12 }
        if candidate.afterReady { score += 0.03 }
        return score
    }

    private func rememberSmartText(tokens: [String], capturedAt now: Date) {
        smartTextObservations.append(contentsOf: tokens.map { SmartTextObservation(token: $0, capturedAt: now) })
        pruneSmartText(now: now)
    }

    private func pruneSmartText(now: Date) {
        smartTextObservations.removeAll { now.timeIntervalSince($0.capturedAt) > smartTextWindow }
    }

    private func selectBestSmartCaptureFrame(now: Date) -> UIImage? {
        let burst = smartCaptureCandidates.filter { $0.afterReady && !$0.usefulTokens.isEmpty }
        let complete = burst.filter(\.isCompletePostFrame)
        let recent = smartCaptureCandidates.filter {
            now.timeIntervalSince($0.capturedAt) <= smartTextWindow && !$0.usefulTokens.isEmpty
        }
        var pool: [SmartCaptureCandidate]
        if !complete.isEmpty {
            pool = complete
        } else if !burst.isEmpty {
            pool = burst
        } else if !recent.isEmpty {
            pool = recent
        } else {
            pool = smartCaptureCandidates
        }

        let nonBlurred = pool.filter { $0.visualScore >= smartBlurVetoVisualScore }
        if nonBlurred.count >= 2 {
            pool = nonBlurred
        }

        return pool
            .max { lhs, rhs in
                let left = selectionScore(lhs)
                let right = selectionScore(rhs)
                if abs(left - right) < 0.05 {
                    return lhs.capturedAt < rhs.capturedAt
                }
                return left < right
            }?
            .image
    }

    private func accumulatedOCRText() -> String {
        uniqueUsefulTokens(from: smartTextObservations.map(\.token)).joined(separator: " ")
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

    private func localTextMetrics(_ image: UIImage) -> FrameTextMetrics {
        let empty = FrameTextMetrics(
            score: 0, usefulTokens: [], lineCount: 0, meanConfidence: 0,
            layoutScore: 0, hasTopSignal: false, hasBottomSignal: false,
            isCompletePostFrame: false, isSoftReadable: false
        )
        guard let cgImage = image.cgImage else { return empty }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        // Armed-capture OCR: readable + spatial coverage. Full multi-language OCR runs after capture.
        request.recognitionLanguages = ["en-US", "es-ES"]
        request.minimumTextHeight = 0.014

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImagePropertyOrientation(from: image.imageOrientation)
        )
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            var strings: [String] = []
            var confidences: [Double] = []
            var boxes: [CGRect] = []
            for observation in observations {
                guard let best = observation.topCandidates(1).first else { continue }
                strings.append(best.string)
                confidences.append(Double(best.confidence))
                boxes.append(observation.boundingBox)
            }

            let meanConfidence = confidences.isEmpty
                ? 0
                : confidences.reduce(0, +) / Double(confidences.count)
            let tokens = uniqueUsefulTokens(from: strings.flatMap { rawUsefulTokens(from: $0) })
            let layout = layoutCoverage(strings: strings, boxes: boxes, tokens: tokens)

            let longTokenCount = tokens.filter { $0.count >= 7 }.count
            let numberTokenCount = tokens.filter { $0.rangeOfCharacter(from: .decimalDigits) != nil }.count
            let usernameLikeCount = tokens.filter(isUsernameLikeToken).count
            let lineScore = min(Double(strings.count), 8) * 0.07
            let tokenScore = min(Double(tokens.count), 14) * 0.05
            let distinctiveScore = min(Double(longTokenCount), 4) * 0.13
            let numberScore = min(Double(numberTokenCount), 5) * 0.11
            let usernameScore = min(Double(usernameLikeCount), 4) * 0.12
            let confidenceScore = meanConfidence * 0.35
            let ocrScore = min(
                lineScore + tokenScore + distinctiveScore + numberScore + usernameScore + confidenceScore,
                1.6
            )

            let softReadable = tokens.count >= smartMinimumUsefulTokens
                && strings.count >= smartMinimumLineCount
                && ocrScore >= smartMinimumOCRScore
                && (longTokenCount > 0 || numberTokenCount > 0 || usernameLikeCount > 0)

            return FrameTextMetrics(
                score: ocrScore,
                usefulTokens: tokens,
                lineCount: strings.count,
                meanConfidence: meanConfidence,
                layoutScore: layout.score,
                hasTopSignal: layout.hasTop,
                hasBottomSignal: layout.hasBottom,
                isCompletePostFrame: layout.isComplete && softReadable,
                isSoftReadable: softReadable
            )
        } catch {
            return empty
        }
    }

    /// Vision boxes use bottom-left origin: top of phone screen ≈ high Y, bottom ≈ low Y.
    private func layoutCoverage(
        strings: [String],
        boxes: [CGRect],
        tokens: [String]
    ) -> (score: Double, hasTop: Bool, hasBottom: Bool, isComplete: Bool) {
        let topChrome: Set<String> = [
            "publicaciones", "posts", "publications", "beitrage", "seguir", "follow",
            "following", "reels", "reel"
        ]
        let bottomSocial: Set<String> = [
            "gusta", "liked", "les", "personas", "people", "others", "autres", "outras",
            "comentarios", "comments", "me"
        ]

        var hasTopChrome = false
        var hasTopUsername = false
        var hasBottomNumbers = false
        var hasBottomSocial = false
        var topYs: [CGFloat] = []
        var bottomYs: [CGFloat] = []
        var allYs: [CGFloat] = []

        for (index, string) in strings.enumerated() {
            guard index < boxes.count else { continue }
            let box = boxes[index]
            let midY = box.midY
            allYs.append(midY)
            let normalized = string
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            let lineTokens = rawUsefulTokens(from: normalized)

            // Vision Y: 0 = bottom of image, 1 = top (includes spectator status-bar / nav).
            // Slightly taller bands so header + engagement are harder to miss while aiming.
            let inTop = midY >= 0.60
            let inBottom = midY <= 0.45

            if inTop {
                topYs.append(midY)
                if lineTokens.contains(where: { topChrome.contains($0) })
                    || topChrome.contains(where: { normalized.contains($0) }) {
                    hasTopChrome = true
                }
                if lineTokens.contains(where: isUsernameLikeToken) {
                    hasTopUsername = true
                }
            }
            if inBottom {
                bottomYs.append(midY)
                if lineTokens.contains(where: { $0.rangeOfCharacter(from: .decimalDigits) != nil }) {
                    hasBottomNumbers = true
                }
                if lineTokens.contains(where: { bottomSocial.contains($0) })
                    || bottomSocial.contains(where: { normalized.contains($0) }) {
                    hasBottomSocial = true
                }
            }
        }

        // Also accept username-like tokens globally if any text sits in the top band.
        if !hasTopUsername, !topYs.isEmpty {
            hasTopUsername = tokens.contains(where: isUsernameLikeToken)
        }

        let hasTop = hasTopChrome || hasTopUsername
        let hasBottom = hasBottomNumbers || hasBottomSocial
        let span: Double = {
            guard let minY = allYs.min(), let maxY = allYs.max(), maxY > minY else { return 0 }
            return Double(maxY - minY)
        }()

        var score = 0.0
        if hasTopChrome { score += 0.35 }
        if hasTopUsername { score += 0.45 }
        if hasBottomNumbers { score += 0.50 }
        if hasBottomSocial { score += 0.25 }
        score += min(span, 0.85) * 0.55
        if hasTop && hasBottom { score += 0.40 }

        // Complete = header/author zone + engagement zone (numbers or liked-by).
        let isComplete = hasTop && hasBottom && (hasTopUsername || hasTopChrome) && (hasBottomNumbers || hasBottomSocial)
        return (min(score, 2.2), hasTop, hasBottom, isComplete)
    }

    private func isUsernameLikeToken(_ token: String) -> Bool {
        token.range(of: #"^[a-z0-9._]{3,30}$"#, options: .regularExpression) != nil
            && token.contains(where: \.isLetter)
    }

    private func rawUsefulTokens(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "._")) }
            .filter { token in
                guard token.count >= 3 else { return false }
                if token.allSatisfy({ $0.isNumber }) {
                    return token.count >= 2
                }
                return token.contains { $0.isLetter }
            }
    }

    private func uniqueUsefulTokens(from tokens: [String]) -> [String] {
        var seen = Set<String>()
        return tokens.filter { token in
            seen.insert(token).inserted
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
        guard shouldCaptureNextFrame, !isCapturingStillBurst else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            failSmartCapture()
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(ciImage, from: ciImage.extent) else {
            failSmartCapture()
            return
        }

        processSmartCaptureFrame(UIImage(cgImage: cgImage), capturedAt: Date())
    }
}

extension AIScreenCameraCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        sessionQueue.async {
            guard self.isCapturingStillBurst else { return }
            if let error {
                print("⚠️ [SMART CAPTURE] mode=hybrid photo error: \(error.localizedDescription)")
                self.handleStillBurstPhoto(nil)
                return
            }
            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                self.handleStillBurstPhoto(nil)
                return
            }
            // Normalize orientation for Vision/OCR + GPT.
            let normalized: UIImage = {
                if image.imageOrientation == .up { return image }
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = image.scale
                return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
            }()
            self.handleStillBurstPhoto(normalized)
        }
    }
}
