import AVFoundation
import Foundation

public enum CameraSessionError: Error {
    case permissionDenied
    case restricted
    case configurationFailed
    case noCameraAvailable
}

public final class CameraSession: NSObject {
    public let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camerakit.session.queue")

    private var videoOutput: AVCaptureVideoDataOutput?

    public typealias FrameHandler = (CMSampleBuffer,AVCaptureConnection) -> Void
    private var frameHandler: FrameHandler?

    public override init() {
        super.init()
        session.sessionPreset = .hd1280x720
    }

    public func setFrameHandler(_ handler: FrameHandler?) {
        sessionQueue.async { [weak self] in
            self?.frameHandler = handler
        }
    }

    public func startRunning(
        completion:
            @escaping (Result<AVCaptureSession, CameraSessionError>) -> Void
    ) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart(completion: completion)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStart(completion: completion)
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(.permissionDenied))
                    }
                }
            }
        case .denied:
            completion(.failure(.permissionDenied))

        case .restricted:
            completion(.failure(.restricted))

        @unknown default:
            completion(.failure(.configurationFailed))
        }
    }

    public func stopRunning() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configureAndStart(
        completion:
            @escaping (Result<AVCaptureSession, CameraSessionError>) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureSession()
                self.session.startRunning()
                DispatchQueue.main.async {
                    completion(.success(self.session))
                }
            } catch let error as CameraSessionError {
                DispatchQueue.main.async {
                    completion(.failure(.configurationFailed))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.configurationFailed))
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()

        let currentInputs = session.inputs
        currentInputs.forEach { session.removeInput($0) }

        let currentOutputs = session.outputs
        currentOutputs.forEach { session.removeOutput($0) }

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .front
            )
        else {
            session.commitConfiguration()
            throw CameraSessionError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraSessionError.configurationFailed
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        //output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        //output.alwaysDiscardsLateVideoFrames = true
        
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0){
                connection.videoRotationAngle = 0
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraSessionError.configurationFailed
        }

        session.addOutput(output)
        videoOutput = output
        
        
        

        session.commitConfiguration()
    }
}


extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        print("frame captured")
        frameHandler?(sampleBuffer, connection)
    }
}
