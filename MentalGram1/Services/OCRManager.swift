import AVFoundation
import Vision
import UIKit
import Combine

// MARK: - OCR Manager

@available(iOS 14.0, *)
final class OCRManager: NSObject {

    weak var delegate: OCRDelegate?
    private var configuration: OCRConfiguration = OCRConfiguration()

    // AVFoundation
    private let captureSession = AVCaptureSession()
    private var captureVideoDataOutput = AVCaptureVideoDataOutput()

    // Vision
    private lazy var textRequest: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest(completionHandler: handleDetectedText)
        r.recognitionLevel = .accurate
        r.usesLanguageCorrection = true
        return r
    }()

    // State
    private var isRecognizing = false
    private var occurrencesMap: [String: Int] = [:]
    private var hasFinished = false

    // MARK: - Public API

    func configure(with config: OCRConfiguration) {
        configuration = config
        textRequest.recognitionLanguages = [config.language]
    }

    /// Call this when Performance view appears. Camera starts silently in background.
    func start() {
        guard !hasFinished else { return }
        occurrencesMap.removeAll()
        setupSession()
        isRecognizing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    /// Call this if the user leaves before a result is obtained.
    func stop() {
        isRecognizing = false
        hasFinished = false
        occurrencesMap.removeAll()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    // MARK: - Session setup

    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.inputs.forEach  { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: configuration.cameraPosition),
              let input = try? AVCaptureDeviceInput(device: device) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) { captureSession.addInput(input) }

        captureVideoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        captureVideoDataOutput.setSampleBufferDelegate(
            self, queue: DispatchQueue(label: "com.vault.ocr.queue"))

        if captureSession.canAddOutput(captureVideoDataOutput) {
            captureSession.addOutput(captureVideoDataOutput)
        }

        captureSession.sessionPreset = .hd1280x720
        captureSession.commitConfiguration()
    }
}

// MARK: - Sample buffer delegate

@available(iOS 14.0, *)
extension OCRManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isRecognizing, !hasFinished else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .right,
                                            options: [:])
        try? handler.perform([textRequest])
    }
}

// MARK: - Vision processing

@available(iOS 14.0, *)
extension OCRManager {

    private func handleDetectedText(request: VNRequest?, error: Error?) {
        guard !hasFinished,
              let results = request?.results, !results.isEmpty else { return }

        for result in results {
            guard let obs = result as? VNRecognizedTextObservation,
                  let top = obs.topCandidates(1).first else { continue }

            let text = top.string.replacingOccurrences(of: " ", with: "")
            guard text.count >= configuration.minimumWordSize else { continue }

            let count = (occurrencesMap[text] ?? 0) + 1
            occurrencesMap[text] = count

            if count >= configuration.occurrences {
                finalize(text: text)
                return
            }
        }
    }

    private func finalize(text: String) {
        hasFinished = true
        isRecognizing = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }

        let stringType = OCRTextValidator.classify(text)
        let finalText: String

        switch stringType {
        case .operation:
            finalText = OCRTextValidator.evaluateOperation(text)
        case .date(let date):
            finalText = OCRTextValidator.formatDate(date)
        case .text:
            finalText = text
        }

        DispatchQueue.main.async { [weak self] in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self?.delegate?.ocrDidRecognize(text: finalText, type: stringType)
        }
    }
}

// MARK: - OCR Coordinator (SwiftUI bridge)

/// ObservableObject that wraps OCRManager and acts as its delegate.
/// Use as @StateObject in PerformanceView.
@available(iOS 14.0, *)
final class OCRCoordinator: NSObject, ObservableObject, OCRDelegate {

    @Published var recognizedText: String? = nil
    @Published var recognizedType: OCRStringType? = nil

    let manager = OCRManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func start(config: OCRConfiguration) {
        manager.configure(with: config)
        manager.start()
    }

    func stop() {
        manager.stop()
        recognizedText = nil
        recognizedType = nil
    }

    func ocrDidRecognize(text: String, type: OCRStringType) {
        DispatchQueue.main.async {
            self.recognizedText = text
            self.recognizedType = type
        }
    }
}
