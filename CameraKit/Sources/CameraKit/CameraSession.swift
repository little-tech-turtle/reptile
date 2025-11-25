import AVFoundation
import SwiftUI

public final class CameraSession: NSObject {
    public weak var delegate: CameraFrameDelegate?

    private let captureSession = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "com.camerakit.videoQueue")
    private var videoOutput: AVCaptureVideoDataOutput!

    public override init() {
        super.init()
    }

    public func requestPermission(completion: @escaping @Sendable (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    public func configureSession(position: AVCaptureDevice.Position = .front) throws {
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
        }

        captureSession.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: position)
        else {
            throw CameraSessionError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        } else {
            throw CameraSessionError.cannotAddInput
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        self.videoOutput = output

        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
        } else {
            throw CameraSessionError.cannotAddOutput
        }

        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            }
        }

    }

    public func start() {
        if !captureSession.isRunning {
            videoQueue.async {
                self.captureSession.startRunning()
            }
        }
    }

    public func stop() {
        if captureSession.isRunning {
            videoQueue.async {
                self.captureSession.stopRunning()
            }
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        delegate?.cameraSession(self, didOutputPixelBuffer: pixelBuffer)
    }
}

public enum CameraSessionError: Error {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
}
