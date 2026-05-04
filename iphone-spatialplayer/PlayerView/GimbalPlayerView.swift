// GimbalPlayerView.swift
// SpatialPlayer
//
// Author: PaoloPV
// RealityKit view for Gimbal mode.
// Camera is driven by device tilt and drag gestures.

import RealityKit
import SwiftUI

struct GimbalPlayerView: View {
    let videoURL: URL
    let angle: VideoAngle

    @State private var viewModel: GimbalPlayerViewModel

    init(videoURL: URL, angle: VideoAngle) {
        self.videoURL = videoURL
        self.angle    = angle
        _viewModel = State(initialValue: GimbalPlayerViewModel(videoURL: videoURL, angle: angle))
    }

    var body: some View {
        RealityView { content in
            // Inside-out sphere: negative X scale flips normals so the texture faces inward.
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 5.0),
                materials: [VideoMaterial(avPlayer: viewModel.player)]
            )
            sphere.scale = SIMD3<Float>(-1, 1, 1)

            // Virtual perspective camera. 90° FOV approximates natural hand-held viewing.
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 90

            content.camera = .virtual
            content.add(sphere)
            content.add(camera)

        } update: { content in
            guard let camera = content.entities.lazy.compactMap({ $0 as? PerspectiveCamera }).first else { return }
            camera.transform.rotation = viewModel.cameraRotation
        }
        .gesture(dragGesture)
        .onAppear {
            viewModel.play()
            viewModel.startMotionTracking()
        }
        .onDisappear {
            viewModel.stopMotionTracking()
            viewModel.cleanup()
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in viewModel.handleDrag(translation: value.translation) }
            .onEnded   { _     in viewModel.handleDragEnd() }
    }
}
