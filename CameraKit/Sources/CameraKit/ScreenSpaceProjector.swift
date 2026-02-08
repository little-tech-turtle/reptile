//
//  ScreenSpaceProjector.swift
//  CameraKit
//
//  Created by TechTurtle on 01/02/2026.
//

import AVFoundation
import Vision

public final class ScreenSpaceProjector {
    public init(){}
    public func project(normalized: [VNHumanBodyPose3DObservation.JointName: NormalizedPoint], in previewLayer: AVCaptureVideoPreviewLayer) -> [VNHumanBodyPose3DObservation.JointName: CGPoint] {
        assert(Thread.isMainThread)
        
        var out: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:]
        out.reserveCapacity(normalized.count)
        
        for(joint,point) in normalized {
            let captureDevicePoint = CGPoint(x: point.x, y: point.y)
            out[joint] = previewLayer.layerPointConverted(fromCaptureDevicePoint: captureDevicePoint)
        }
        return out
    }
}
