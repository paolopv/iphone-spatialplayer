// CardboardPlayerView.swift
// SpatialPlayer
//
// Author: PaoloPV
// Split-screen VR view for use with a Google Cardboard headset.
//
// Layout (landscape):
//   ┌─────────────────────────────────────────────┐
//   │   Left Eye (–IPD/2)   │   Right Eye (+IPD/2) │
//   │      RealityView       │      RealityView      │
//   └─────────────────────────────────────────────┘
//
// Each eye is a separate RealityView with its own sphere and camera.
// The cameras share the same rotation quaternion but are offset on the X axis
// by ±IPD/2 (31.5 mm) to create horizontal parallax — the basis of stereo depth.
//
// For mono video, both eyes share the same AVPlayer instance.
// For Side-by-Side stereo video, each eye uses a separate AVPlayer whose
// AVMutableVideoComposition crops the frame to the appropriate half.
//
// Note: Lens barrel distortion correction is not applied here.
// Through Cardboard lenses the image will appear slightly barrel-distorted
// unless a Metal post-process pass is added.

import AVFoundation
import RealityKit
import SwiftUI
import UIKit

struct CardboardPlayerView: View {
    let videoURL: URL
    let angle: VideoAngle
    let stereo: StereoLayout

    @State private var viewModel: CardboardPlayerViewModel

    init(videoURL: URL, angle: VideoAngle, stereo: StereoLayout) {
        self.videoURL = videoURL
        self.angle    = angle
        self.stereo   = stereo
        _viewModel = State(initialValue: CardboardPlayerViewModel(
            videoURL: videoURL,
            angle: angle,
            stereo: stereo
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // ── Left Eye ────────────────────────────────────────────────
                EyeView(
                    player:         viewModel.leftPlayer,
                    rotation:       viewModel.cameraRotation,
                    cameraOffset:   CardboardPlayerViewModel.leftEyeOffset
                )
                .frame(width: (geometry.size.width - 2) / 2, height: geometry.size.height)
                .clipped()

                // Nose bridge — prevents light from the opposite eye leaking through.
                Color.black.frame(width: 2)

                // ── Right Eye ───────────────────────────────────────────────
                EyeView(
                    player:         viewModel.rightPlayer,
                    rotation:       viewModel.cameraRotation,
                    cameraOffset:   CardboardPlayerViewModel.rightEyeOffset
                )
                .frame(width: (geometry.size.width - 2) / 2, height: geometry.size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
        // Lock to landscape while Cardboard is active so the split runs side-to-side.
        .onAppear {
            lockOrientation(to: .landscape)
            viewModel.play()
            viewModel.startMotionTracking()
        }
        .onDisappear {
            lockOrientation(to: .portrait)
            viewModel.stopMotionTracking()
            viewModel.cleanup()
        }
    }

    // MARK: - Orientation lock

    /// Requests the window scene to switch to the given orientation family.
    private func lockOrientation(to orientations: UIInterfaceOrientationMask) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        windowScene.requestGeometryUpdate(preferences)
    }
}

// MARK: - Single-Eye Renderer

/// A RealityKit view that renders the 360° sphere from one eye's perspective.
/// The camera is placed at `cameraOffset` and oriented by `rotation`.
private struct EyeView: View {
    let player: AVPlayer
    let rotation: simd_quatf
    let cameraOffset: SIMD3<Float>

    var body: some View {
        RealityView { content in
            // Inside-out sphere: negative X scale so the texture faces inward.
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 5.0),
                materials: [VideoMaterial(avPlayer: player)]
            )
            sphere.scale = SIMD3<Float>(-1, 1, 1)

            // 95° FOV — slightly wider than Gimbal mode to better fill the lens view.
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 95

            content.camera = .virtual
            content.add(sphere)
            content.add(camera)

        } update: { content in
            guard let camera = content.entities.lazy.compactMap({ $0 as? PerspectiveCamera }).first else { return }
            // Rotation is shared between both eyes; position provides the IPD offset.
            camera.transform.rotation    = rotation
            camera.transform.translation = cameraOffset
        }
    }
}
