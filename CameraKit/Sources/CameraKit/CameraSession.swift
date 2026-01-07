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
    
    public typealias FrameHandler = (CVPixelBuffer, CMTime) -> Void
    private var frameHandler: FrameHandler?
 
    public override init() {
        super.init()
        session.sessionPreset = .high
    }

    
    public func startRunning(
        completion: @escaping (Result<AVCaptureSession, CameraSessionError>) -> Void
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
        completion: @escaping (Result<AVCaptureSession, CameraSessionError>) -> Void
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
        session.inputs.forEach { session.removeInput($0) }

        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back)
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
        session.commitConfiguration()
    }
}
