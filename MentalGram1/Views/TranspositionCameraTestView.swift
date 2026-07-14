import AVFoundation
import SwiftUI

struct TranspositionCameraTestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = TranspositionCameraTestController()
    @ObservedObject private var integrations = IntegrationsSettings.shared

    private let zooms: [Double] = [1.3, 1.4, 1.5]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TranspositionCameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                framingPanel
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
                Text("Choose the best framing for your device")
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

    private var framingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Framing guide")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            Text("Select the zoom that best matches your performance distance and device. The spectator's iPhone screen should fill most of the frame while still showing the profile username, the post/reel title or caption area, and enough of the image/video to identify the post.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            Text("The zoom selected here is saved and used later in Performance.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(12)
        .background(Color.black.opacity(0.62))
        .cornerRadius(14)
    }

    private var zoomSelector: some View {
        HStack(spacing: 8) {
            ForEach(zooms, id: \.self) { zoom in
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
        .padding(.top, 10)
        .padding(.bottom, 8)
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

final class TranspositionCameraTestController {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.vault.transposition-camera-test.session")
    private var device: AVCaptureDevice?

    func start(zoom: CGFloat) {
        Task {
            let granted = await requestAccess()
            guard granted else { return }
            sessionQueue.async {
                self.configureIfNeeded()
                self.applyZoom(zoom)
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
        }
    }

    func applyZoom(_ zoom: CGFloat) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(zoom, 1.0), min(device.activeFormat.videoMaxZoomFactor, 6.0))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
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
        guard session.inputs.isEmpty else { return }
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
        session.commitConfiguration()
    }
}
