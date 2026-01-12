//
//  SkeeletonOverlayView.swift
//  reptile
//
//  Created by TechTurtle on 04/01/2026.
//

import UIKit
import Vision

final class SkeletonOverlayView: UIView {
    
    var joints: [VNHumanBodyPose3DObservation.JointName: CGPoint] = [:] {
        didSet {setNeedsDisplay()}
    }
    
    override func draw(_ rect: CGRect) {
        guard !joints.isEmpty else {return}
        
        let path = UIBezierPath()
        path.lineWidth = 3
        
        func addBone(_ a: VNHumanBodyPose3DObservation.JointName,
                     _ b: VNHumanBodyPose3DObservation.JointName){
            guard let p1 = joints[a], let p2 = joints[b] else {return}
            path.move(to:p1)
            path.addLine(to:p2)
            
        }
        
        // Torso
        addBone(.spine, .root)
        addBone(.leftShoulder, .rightShoulder)
        addBone(.leftHip, .rightHip)

        // Arms
        addBone(.leftShoulder, .leftElbow)
        addBone(.leftElbow, .leftWrist)

        addBone(.rightShoulder, .rightElbow)
        addBone(.rightElbow, .rightWrist)

        // Legs
        addBone(.leftHip, .leftKnee)
        addBone(.leftKnee, .leftAnkle)

        addBone(.rightHip, .rightKnee)
        addBone(.rightKnee, .rightAnkle)
        
        UIColor.white.setStroke()
        path.stroke()
        
        for (_, point) in joints {
            let r : CGFloat = 4
            let rect = CGRect(x: point.x - r,
                              y: point.y - r,
                              width: 2 * r,
                              height: 2 * r)
            let circle = UIBezierPath(ovalIn: rect)
            UIColor.white.setFill()
            circle.fill()
        }
    
    }
}
