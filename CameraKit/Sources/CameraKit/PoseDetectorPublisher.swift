//
//  PoseDetectorStream.swift
//  CameraKit
//
//  Created by TechTurtle on 01/02/2026.
//

import Vision
import AVFoundation
import Combine
import OSLog

private let logger = Logger(subsystem: "CameraKit", category: "poseDetection")

public final class PoseDetectorPublisher: @unchecked Sendable {
    private let request = VNDetectHumanBodyPose3DRequest()
    private let handler = VNSequenceRequestHandler()
    
    private let visionQueue = DispatchQueue(label: "pose.detector.stream.vision")
    
    private let gate = DispatchSemaphore(value: 1)
    
    private let subject = PassthroughSubject<PoseFrame,Never>()
    public var poses: AnyPublisher<PoseFrame,Never>{
        subject.eraseToAnyPublisher()
    }
    
    public init(){}
    
    private final class PixelBufferBox: @unchecked Sendable {
        let value: CVImageBuffer

        init(_ value: CVImageBuffer) {
            self.value = value
        }
    }

    @inline(__always)
    private func assertOnVisionQueue() {
        dispatchPrecondition(condition: .onQueue(visionQueue))
    }

    public func ingest(_ frame: CameraFrame) {
        guard gate.wait(timeout: .now()) == .success else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            gate.signal()
            return
        }

        let timeStamp = CMSampleBufferGetPresentationTimeStamp(frame.sampleBuffer)
        let orientation = frame.visionOrientation

        let pixelBufferBox = PixelBufferBox(pixelBuffer)

        visionQueue.async { [weak self, timeStamp, orientation, pixelBufferBox] in
            guard let self else { return }
            self.assertOnVisionQueue()

            defer { self.gate.signal() }

            autoreleasepool {
                do {
                    try self.handler.perform([self.request], on: pixelBufferBox.value, orientation: orientation)
                    guard let obs = self.request.results?.first else { return }

                    let joints = PoseSpaceMapper.extractNormalizedJoints(from: obs)
                    let pos3D = PoseSpaceMapper.extract3DPositions(from: obs)
                    self.subject.send(PoseFrame(timestamp: timeStamp, joints: joints, positions3D: pos3D))
                } catch {
                    logger.error("Vision request failed: \(error.localizedDescription)")
                }
            }
        }
    }

    public func finish() {
        visionQueue.async { [weak self] in
            guard let self else { return }
            self.assertOnVisionQueue()
            self.subject.send(completion: .finished)
        }
    }

}
