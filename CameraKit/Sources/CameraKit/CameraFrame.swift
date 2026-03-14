//
//  CameraFrame.swift
//  CameraKit
//
//  Created by TechTurtle on 01/02/2026.
//

import AVFoundation
import ImageIO

public struct CameraFrame {
    public let sampleBuffer: CMSampleBuffer
    public let visionOrientation: CGImagePropertyOrientation

    public init(
        sampleBuffer: CMSampleBuffer,
        visionOrientation: CGImagePropertyOrientation
    ) {
        self.sampleBuffer = sampleBuffer
        self.visionOrientation = visionOrientation
    }
}
