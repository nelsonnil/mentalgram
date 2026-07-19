import AVFoundation
import Combine
import SwiftUI

struct TranspositionCameraTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = TranspositionCameraTestController()
    @ObservedObject private var integrations = IntegrationsSettings.shared

    private let zoomPresets: [Double] = [1.0, 1.2, 1.4, 1.6, 2.0, 2.5, 3.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TranspositionCameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Full-bleed guides matching OCR bands in AIScreenCameraCaptureService:
            // Vision top midY >= 0.60 → top 40% of frame; bottom midY <= 0.45 → bottom 45%.
            GeometryReader { geo in
                let topFraction: CGFloat = 0.40
                let bottomFraction: CGFloat = 0.45
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.cyan.opacity(camera.readiness.hasTopSignal ? 0.24 : 0.10))
                            .frame(height: geo.size.height * topFraction)
                            .overlay(alignment: .topLeading) {
                                Text("TOP — status / Publicaciones / username")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.top, 6)
                            }
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Color.orange.opacity(camera.readiness.hasBottomSignal ? 0.24 : 0.10))
                            .frame(height: geo.size.height * bottomFraction)
                            .overlay(alignment: .bottomLeading) {
                                Text("BOTTOM — comments / shares / liked-by")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 6)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                topBar
                ocrStatusCard
                Spacer()
                helpCard
                zoomSelector
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .onAppear {
            camera.start(zoom: CGFloat(integrations.aiScreenCameraZoom))
        }
        .onDisappear {
            camera.stop()
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Camera Test")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text("Live OCR = same gates as Performance capture")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Circle())
            }
        }
    }

    private var ocrStatusCard: some View {
        let r = camera.readiness
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(r.phaseLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                if camera.wouldFirePulse {
                    Text("FIRE")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(6)
                }
            }

            HStack(spacing: 8) {
                signalChip(title: "Top", on: r.hasTopSignal)
                signalChip(title: "Bottom", on: r.hasBottomSignal)
                signalChip(title: "Readable", on: r.isSoftReadable)
                signalChip(title: "Complete", on: r.isCompletePostFrame)
            }

            if camera.burstProgress > 0, camera.burstProgress < 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Burst sampling… \(Int(camera.burstProgress * 6))/6 (then would vibrate)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    ProgressView(value: camera.burstProgress)
                        .tint(.green)
                }
            }

            HStack {
                Text(String(format: "OCR %.2f", r.ocrScore))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text("·")
                    .foregroundColor(.white.opacity(0.4))
                Text(String(format: "Layout %.2f", r.layoutScore))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Confirmed (stable)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                if camera.confirmedTokens.isEmpty {
                    Text("Waiting for words that repeat across frames…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    Text(camera.confirmedTokens.joined(separator: "  ·  "))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.95))
                        .lineLimit(3)
                }

                Text("Live (flickers)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 2)
                if r.previewTokens.isEmpty {
                    Text("—")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                } else {
                    Text(r.previewTokens.joined(separator: "  ·  "))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.72))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(statusColor.opacity(0.7), lineWidth: r.isCompletePostFrame ? 2 : 1)
        )
    }

    private var statusColor: Color {
        if camera.readiness.isCompletePostFrame || camera.wouldFirePulse { return .green }
        if camera.readiness.isSoftReadable { return .yellow }
        return .orange
    }

    private func signalChip(title: String, on: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(on ? .black : .white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(on ? Color.green : Color.white.opacity(0.12))
            .cornerRadius(7)
    }

    private var helpCard: some View {
        Text("Green Complete = Performance would start the 6-frame burst and vibrate. Practice until Top + Bottom light up together.")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.55))
            .cornerRadius(12)
    }

    private var zoomSelector: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Zoom")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: "%.1fx", integrations.aiScreenCameraZoom))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            HStack(spacing: 10) {
                Button {
                    nudgeZoom(by: -0.1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.58))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { integrations.aiScreenCameraZoom },
                        set: { newValue in
                            let stepped = (newValue * 10).rounded() / 10
                            integrations.aiScreenCameraZoom = stepped
                            camera.applyZoom(CGFloat(stepped))
                        }
                    ),
                    in: IntegrationsSettings.aiScreenCameraZoomRange,
                    step: 0.1
                )
                .tint(.white)

                Button {
                    nudgeZoom(by: 0.1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.58))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(zoomPresets, id: \.self) { zoom in
                        Button {
                            integrations.aiScreenCameraZoom = zoom
                            camera.applyZoom(CGFloat(zoom))
                        } label: {
                            Text(String(format: "%.1fx", zoom))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(abs(integrations.aiScreenCameraZoom - zoom) < 0.01 ? .black : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(abs(integrations.aiScreenCameraZoom - zoom) < 0.01 ? Color.white : Color.black.opacity(0.58))
                                .cornerRadius(9)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.55))
        .cornerRadius(14)
        .padding(.bottom, 4)
    }

    private func nudgeZoom(by delta: Double) {
        let next = IntegrationsSettings.clampedAIScreenCameraZoom(integrations.aiScreenCameraZoom + delta)
        integrations.aiScreenCameraZoom = next
        camera.applyZoom(CGFloat(next))
    }
}

private struct TranspositionCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

fileprivate final class TranspositionCameraTestController: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var readiness = AIScreenCaptureReadiness(
        hasTopSignal: false,
        hasBottomSignal: false,
        isSoftReadable: false,
        isCompletePostFrame: false,
        ocrScore: 0,
        layoutScore: 0,
        previewTokens: []
    )
    @Published var burstProgress: Double = 0
    @Published var wouldFirePulse = false
    /// Tokens seen repeatedly — stable enough to read while aiming.
    @Published var confirmedTokens: [String] = []

    private let sessionQueue = DispatchQueue(label: "com.vault.transposition-camera-test.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var lastOCRAt: Date?
    private var burstStartedAt: Date?
    private var firePulseUntil: Date?
    private var tokenHitCounts: [String: Int] = [:]
    private var lockedConfirmedTokens: [String]?
    private let ocrMinInterval: TimeInterval = 0.12
    private let burstDuration: TimeInterval = 0.48
    private let tokenConfirmHits = 3
    private let maxConfirmedTokens = 10

    func start(zoom: CGFloat) {
        Task {
            let granted = await requestAccess()
            guard granted else { return }
            sessionQueue.async {
                self.configureIfNeeded()
                self.applyZoomLocked(zoom)
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.burstStartedAt = nil
            self.firePulseUntil = nil
            self.tokenHitCounts.removeAll()
            self.lockedConfirmedTokens = nil
            DispatchQueue.main.async {
                self.burstProgress = 0
                self.wouldFirePulse = false
                self.confirmedTokens = []
            }
        }
    }

    func applyZoom(_ zoom: CGFloat) {
        sessionQueue.async {
            self.applyZoomLocked(zoom)
        }
    }

    private func applyZoomLocked(_ zoom: CGFloat) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            let clamped = min(max(zoom, 1.0), min(device.activeFormat.videoMaxZoomFactor, 6.0))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
    }

    private func requestAccess() async -> Bool {
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

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else {
            session.sessionPreset = .high
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }

        device = camera
        try? camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        camera.unlockForConfiguration()

        session.addInput(input)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        if let connection = videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        session.commitConfiguration()
        isConfigured = true
    }

    private func processFrameImage(_ image: UIImage) {
        let now = Date()
        if let lastOCRAt, now.timeIntervalSince(lastOCRAt) < ocrMinInterval { return }
        lastOCRAt = now

        let next = AIScreenCameraCaptureService.shared.evaluateCaptureReadiness(in: image)

        if next.isCompletePostFrame {
            if burstStartedAt == nil {
                burstStartedAt = now
            }
        } else if burstStartedAt != nil, !next.isSoftReadable {
            burstStartedAt = nil
        }

        var progress: Double = 0
        var pulse = false
        if let started = burstStartedAt {
            progress = min(1, now.timeIntervalSince(started) / burstDuration)
            if progress >= 1 {
                firePulseUntil = now.addingTimeInterval(0.9)
                burstStartedAt = nil
                progress = 0
            }
        }
        if let until = firePulseUntil {
            pulse = now < until
            if !pulse {
                firePulseUntil = nil
                lockedConfirmedTokens = nil
            }
        }

        let confirmed = updateConfirmedTokens(
            from: next.previewTokens,
            lockOnFire: pulse || progress >= 1 || (firePulseUntil != nil)
        )

        DispatchQueue.main.async {
            self.readiness = next
            self.burstProgress = progress
            self.wouldFirePulse = pulse
            self.confirmedTokens = confirmed
        }
    }

    /// Require the same token across several frames so the HUD is readable.
    private func updateConfirmedTokens(from live: [String], lockOnFire: Bool) -> [String] {
        if lockOnFire {
            if lockedConfirmedTokens == nil {
                let current = tokenHitCounts
                    .filter { $0.value >= tokenConfirmHits }
                    .sorted { $0.value > $1.value }
                    .prefix(maxConfirmedTokens)
                    .map(\.key)
                lockedConfirmedTokens = current.isEmpty ? live.prefix(maxConfirmedTokens).map { $0 } : Array(current)
            }
            return lockedConfirmedTokens ?? []
        }

        let liveSet = Set(live)
        for token in liveSet {
            tokenHitCounts[token, default: 0] += 1
        }
        for key in Array(tokenHitCounts.keys) where !liveSet.contains(key) {
            let next = (tokenHitCounts[key] ?? 0) - 1
            if next <= 0 {
                tokenHitCounts.removeValue(forKey: key)
            } else {
                tokenHitCounts[key] = next
            }
        }

        return tokenHitCounts
            .filter { $0.value >= tokenConfirmHits }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(maxConfirmedTokens)
            .map(\.key)
    }
}

extension TranspositionCameraTestController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        processFrameImage(UIImage(cgImage: cgImage))
    }
}
