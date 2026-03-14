import AVFoundation
import Combine
import Foundation
import ImageIO
import UIKit

public enum CameraSessionError: Error, Sendable {
    case permissionDenied
    case restricted
    case configurationFailed
    case noCameraAvailable
}

public enum CameraSessionState: Sendable {
    case idle
    case starting
    case running
    case stopping
    case failed(CameraSessionError)
}

public final class CameraSession: NSObject {
    public let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "camerakit.session.queue")

    public var interfaceOrientation: UIInterfaceOrientation = .portrait
    public var mirrorVisionInput: Bool = false
    public var cameraPosition: AVCaptureDevice.Position = .front

    private let frameSubject = PassthroughSubject<CameraFrame, Never>()
    private let stateSubject = CurrentValueSubject<CameraSessionState, Never>(.idle)

    public var frames: AnyPublisher<CameraFrame, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public var states: AnyPublisher<CameraSessionState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    public override init() {
        super.init()
        session.sessionPreset = .hd1280x720
    }

    public func startRunning() {
        publishState(.starting)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStart()
                } else {
                    self.publishState(.failed(.permissionDenied))
                }
            }
        case .denied:
            publishState(.failed(.permissionDenied))

        case .restricted:
            publishState(.failed(.restricted))

        @unknown default:
            publishState(.failed(.configurationFailed))
        }
    }

    public func stopRunning() {
        publishState(.stopping)

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.publishState(.idle)
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.publishState(.running)
                return
            }

            do {
                try self.configureSession()
                self.session.startRunning()
                self.publishState(.running)
            } catch let error as CameraSessionError {
                self.publishState(.failed(error))
            } catch {
                self.publishState(.failed(.configurationFailed))
            }
        }
    }


    public func visionOrientation() -> CGImagePropertyOrientation {
        FrameTransformPolicy.visionOrientation(
            for: interfaceOrientation,
            mirrored: mirrorVisionInput
        )
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
                position: cameraPosition
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
        
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CameraSessionError.configurationFailed
        }

        session.addOutput(output)
        session.commitConfiguration()
    }

    public func setInterfaceOrientation(_ io: UIInterfaceOrientation) {
        sessionQueue.async { [weak self] in
            self?.interfaceOrientation = io
        }
    }

    public func setMirrorInput(_ isMirrored: Bool) {
        sessionQueue.async { [weak self] in
            self?.mirrorVisionInput = isMirrored
        }
    }

    public func setCameraPosition(_ position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            self?.cameraPosition = position
        }
    }

    private func publishState(_ state: CameraSessionState) {
        sessionQueue.async { [weak self] in
            self?.stateSubject.send(state)
        }
    }
}



extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        let frame = CameraFrame(
            sampleBuffer: sampleBuffer,
            visionOrientation: visionOrientation()
        )
        frameSubject.send(frame)
    }
}
