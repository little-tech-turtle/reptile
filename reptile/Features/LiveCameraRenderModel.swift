import CameraKit
import CoreGraphics
import Vision

struct LiveCameraRenderModel {
    let statusText: String
    let joints: [VNHumanBodyPose3DObservation.JointName: CGPoint]
    let trackedJoints: Set<VNHumanBodyPose3DObservation.JointName>
    let exerciseID: String
    let output: RepCounterOutput?
}
