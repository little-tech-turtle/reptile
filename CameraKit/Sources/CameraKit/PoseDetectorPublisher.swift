//
//  PoseDetectorStream.swift
//  CameraKit
//
//  Created by TechTurtle on 01/02/2026.
//

import Vision
import AVFoundation
import Combine

public final class PoseDetectorPublisher{
    private let request = VNDetectHumanBodyPose3DRequest()
    private let handler = VNSequenceRequestHandler()
    
    private let visionQueue = DispatchQueue(label: "pose.detector.stream.vision")
    
    private let gate = DispatchSemaphore(value: 1)
    
    private let subject = PassthroughSubject<PoseFrame,Never>()
    public var poses: AnyPublisher<PoseFrame,Never>{
        subject.eraseToAnyPublisher()
    }
    
    public init(){}
    
    public func ingest (_ frame: CameraFrame) {
        guard gate.wait(timeout: .now()) == .success else {return}
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            gate.signal()
            return
        }
        
        let timeStamp = CMSampleBufferGetPresentationTimeStamp(frame.sampleBuffer)
        let orientation = frame.visionOrientation
        
        visionQueue.async { [weak self] in
            guard let self else {return}
            defer {self.gate.signal()}
            autoreleasepool{
                do {
                    try self.handler.perform([self.request], on: pixelBuffer, orientation:orientation)
                    guard let obs = self.request.results?.first else {return}
                    
                    let joints = PoseSpaceMapper.extractNormalizedJoints(from: obs)
                    self.subject.send(PoseFrame(timestamp:timeStamp,joints:joints))
                    
                } catch {
                    print ("Vision error:", error)
                }
            }
            
        }
    }
    
    public func finish() {
        subject.send(completion: .finished)
    }
    
}
