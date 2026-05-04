// PortalPlayerView.swift
// SpatialPlayer
//
// Author: PaoloPV
// RealityKit view for Portal mode.
// Face tracking adjusts the FOV so the sphere appears at true life-size scale,
// turning the display into a window into the virtual space.

import RealityKit
import SwiftUI

struct PortalPlayerView: View {
    let videoURL: URL
    let angle: VideoAngle

    @State private var viewModel: PortalPlayerViewModel

    init(videoURL: URL, angle: VideoAngle) {
        self.videoURL = videoURL
        self.angle    = angle
        _viewModel = State(initialValue: PortalPlayerViewModel(
            videoURL: videoURL,
            angle: angle,
            screenHeightMeters: getScreenHeightMeters()
        ))
    }

    var body: some View {
        RealityView { content in
            // Same inside-out sphere as Gimbal mode.
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 5.0),
                materials: [VideoMaterial(avPlayer: viewModel.player)]
            )
            sphere.scale = SIMD3<Float>(-1, 1, 1)

            // FOV starts at a sensible default and is updated continuously
            // by face tracking as the user moves closer or further from the screen.
            let camera = PerspectiveCamera()

            content.camera = .virtual
            content.add(sphere)
            content.add(camera)

        } update: { content in
            guard let camera = content.entities.lazy.compactMap({ $0 as? PerspectiveCamera }).first else { return }
            camera.transform.rotation          = viewModel.cameraRotation
            camera.camera.fieldOfViewInDegrees = viewModel.fieldOfView
        }
        .onAppear {
            viewModel.play()
            viewModel.startMotionTracking()
            viewModel.startFaceTracking()
        }
        .onDisappear {
            viewModel.stopMotionTracking()
            viewModel.stopFaceTracking()
            viewModel.cleanup()
        }
    }
}
