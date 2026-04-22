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
import ImageIO

private let logger = Logger(subsystem: "CameraKit", category: "poseDetection")

protocol PoseVisionExecuting: AnyObject {
    func detectPoses(
        in sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> [VNHumanBodyPose3DObservation]
}

final class VisionPoseExecutor: PoseVisionExecuting {
    private let request = VNDetectHumanBodyPose3DRequest()
    private let handler = VNSequenceRequestHandler()

    func detectPoses(
        in sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> [VNHumanBodyPose3DObservation] {
        try handler.perform([request], on: sampleBuffer, orientation: orientation)
        return request.results ?? []
    }
}

public final class PoseDetectorPublisher: @unchecked Sendable {
    private let visionExecutor: any PoseVisionExecuting
    private var poseStabilizer: PoseFrameStabilizer

    private let visionQueue = DispatchQueue(label: "pose.detector.stream.vision")

    private let gate = DispatchSemaphore(value: 1)

    private let subject = PassthroughSubject<PoseFrame, Never>()
    public var poses: AnyPublisher<PoseFrame, Never> {
        subject.eraseToAnyPublisher()
    }

    public init() {
        self.visionExecutor = VisionPoseExecutor()
        self.poseStabilizer = PoseFrameStabilizer()
    }

    init(
        visionExecutor: any PoseVisionExecuting,
        poseStabilizer: PoseFrameStabilizer = PoseFrameStabilizer()
    ) {
        self.visionExecutor = visionExecutor
        self.poseStabilizer = poseStabilizer
    }

    private final class SampleBufferBox: @unchecked Sendable {
        let value: CMSampleBuffer

        init(_ value: CMSampleBuffer) {
            self.value = value
        }
    }

    @inline(__always)
    private func assertOnVisionQueue() {
        dispatchPrecondition(condition: .onQueue(visionQueue))
    }

    public func ingest(_ frame: CameraFrame) {
        guard gate.wait(timeout: .now()) == .success else { return }
        guard CMSampleBufferGetImageBuffer(frame.sampleBuffer) != nil else {
            gate.signal()
            return
        }

        let timeStamp = CMSampleBufferGetPresentationTimeStamp(frame.sampleBuffer)
        let orientation = frame.visionOrientation
        let sampleBufferBox = SampleBufferBox(frame.sampleBuffer)

        visionQueue.async { [weak self, timeStamp, orientation, sampleBufferBox] in
            guard let self else { return }
            self.assertOnVisionQueue()

            defer { self.gate.signal() }

            autoreleasepool {
                do {
                    let observations = try self.visionExecutor.detectPoses(
                        in: sampleBufferBox.value,
                        orientation: orientation
                    )

                    guard let observation = Self.bestObservation(from: observations) else { return }

                    let rawJoints = PoseSpaceMapper.extractNormalizedJoints(from: observation)
                    let rawPositions3D = PoseSpaceMapper.extract3DPositions(from: observation)
                    let stabilized = self.poseStabilizer.stabilize(
                        joints: rawJoints,
                        positions3D: rawPositions3D,
                        observationConfidence: observation.confidence
                    )

                    self.subject.send(
                        PoseFrame(
                            timestamp: timeStamp,
                            joints: stabilized.joints,
                            positions3D: stabilized.positions3D,
                            diagnostics: stabilized.diagnostics
                        )
                    )
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

    private static func bestObservation(
        from observations: [VNHumanBodyPose3DObservation]
    ) -> VNHumanBodyPose3DObservation? {
        observations.max { lhs, rhs in
            lhs.confidence < rhs.confidence
        }
    }
}
