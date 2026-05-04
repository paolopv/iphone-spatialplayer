// ViewMode.swift
// SpatialPlayer
//
// Author: PaoloPV
// Defines all playback modes the app supports and builds their player views.

import ARKit
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    /// Gyroscope + drag gesture — works on any iPhone.
    case gimbal
    /// Face-tracking "window" — requires a front TrueDepth camera.
    case portal
    /// Split-screen stereo VR — designed for use with a Cardboard headset.
    case cardboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gimbal:    "Gimbal"
        case .portal:    "Portal"
        case .cardboard: "Cardboard"
        }
    }

    var subtitle: String {
        switch self {
        case .gimbal:    "Rotate your device or drag to look around"
        case .portal:    "Hold up your phone — the screen becomes a VR window"
        case .cardboard: "Insert into a Cardboard headset for split-screen stereo VR"
        }
    }

    /// SF Symbol used on the mode selection card.
    var icon: String {
        switch self {
        case .gimbal:    "gyroscope"
        case .portal:    "faceid"
        case .cardboard: "visionpro"
        }
    }

    /// Portal mode requires a front TrueDepth camera for face tracking.
    var isAvailable: Bool {
        switch self {
        case .gimbal, .cardboard: true
        case .portal:             ARFaceTrackingConfiguration.isSupported
        }
    }

    /// Cardboard mode settings are not meaningful for Portal (face-tracked FOV) or Gimbal.
    var supportsCardboardSettings: Bool { self == .cardboard }

    /// Builds the player view for the chosen mode.
    /// - Parameters:
    ///   - url:    The HLS or HTTP video URL to stream.
    ///   - angle:  360° full sphere or 180° front hemisphere.
    ///   - stereo: Mono or Side-by-Side stereo layout (Cardboard only).
    @MainActor @ViewBuilder
    func playerView(url: URL, angle: VideoAngle, stereo: StereoLayout) -> some View {
        switch self {
        case .gimbal:
            GimbalPlayerView(videoURL: url, angle: angle)
        case .portal:
            PortalPlayerView(videoURL: url, angle: angle)
        case .cardboard:
            CardboardPlayerView(videoURL: url, angle: angle, stereo: stereo)
        }
    }
}
