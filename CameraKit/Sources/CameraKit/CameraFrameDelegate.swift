import CoreVideo

public protocol CameraFrameDelegate: AnyObject {
    func cameraSession(_ session: CameraSession, didOutputPixelBuffer pixelBuffer: CVPixelBuffer)
}
