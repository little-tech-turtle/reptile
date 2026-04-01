import CoreGraphics
import ImageIO
import AVFoundation
import UIKit

public enum FrameTransformPolicy {
    public static func previewMirrored(
        for cameraPosition: AVCaptureDevice.Position
    ) -> Bool {
        cameraPosition == .front
    }

    public static func visionMirroredInput(
        for _: AVCaptureDevice.Position
    ) -> Bool {
        false
    }

    public static func mirroredInput(
        for cameraPosition: AVCaptureDevice.Position
    ) -> Bool {
        previewMirrored(for: cameraPosition)
    }

    public static func visionOrientation(
        for interfaceOrientation: UIInterfaceOrientation,
        mirrored: Bool
    ) -> CGImagePropertyOrientation {
        let base: CGImagePropertyOrientation
        switch interfaceOrientation {
        case .portrait:
            base = .right
        case .portraitUpsideDown:
            base = .left
        case .landscapeLeft:
            base = .up
        case .landscapeRight:
            base = .down
        default:
            base = .right
        }

        guard mirrored else { return base }

        switch base {
        case .up:
            return .upMirrored
        case .down:
            return .downMirrored
        case .left:
            return .leftMirrored
        case .right:
            return .rightMirrored
        @unknown default:
            return base
        }
    }

    public static func previewRotationAngle(
        for interfaceOrientation: UIInterfaceOrientation
    ) -> CGFloat {
        switch interfaceOrientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        default:
            return 90
        }
    }
}
