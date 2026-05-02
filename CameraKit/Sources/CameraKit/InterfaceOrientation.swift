import Foundation

#if canImport(UIKit)
import UIKit
public typealias CameraKitInterfaceOrientation = UIInterfaceOrientation
#else
public enum CameraKitInterfaceOrientation: Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}
#endif
