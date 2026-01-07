//
//  LiveCameraView.swift
//  reptile
//
//  Created by TechTurtle on 05/01/2026.
//

import SwiftUI

struct LiveCameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LiveCameraViewController {
        LiveCameraViewController()
    }

    func updateUIViewController(_ uiViewController: LiveCameraViewController,
                                context: Context) {
        // No dynamic updates needed for now.
    }
}
