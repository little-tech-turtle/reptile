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
    public let connection: AVCaptureConnection
    public let visionOrientation: CGImagePropertyOrientation
}
