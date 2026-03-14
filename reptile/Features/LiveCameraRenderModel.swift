import CameraKit
import CoreGraphics
import Vision

struct LiveCameraRenderModel {
    let statusText: String
    let joints: [VNHumanBodyPose3DObservation.JointName: CGPoint]
    let output: RepCounterOutput?
}
