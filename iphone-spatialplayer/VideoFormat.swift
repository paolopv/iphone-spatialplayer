// VideoFormat.swift
// SpatialPlayer
//
// Author: PaoloPV
// Describes the angular coverage and stereo layout of the video being played.

import Foundation

/// Whether the video covers the full sphere or only the front hemisphere.
///
/// - `full`: Standard 360° equirectangular — the camera can look in any direction.
/// - `half`: VR180 equirectangular — only the front 180° is captured.
///           Horizontal camera yaw is clamped to ±90° so the user never looks
///           at the black/undefined back hemisphere.
enum VideoAngle: String, CaseIterable, Identifiable {
    case full = "360°"
    case half = "180°"

    var id: String { rawValue }

    /// Maximum horizontal rotation from center (nil = unlimited).
    var yawLimit: Float? {
        switch self {
        case .full: nil
        case .half: .pi / 2
        }
    }
}

/// Stereo layout of the video frame (relevant for Cardboard mode).
///
/// - `mono`: Single image shown identically to both eyes.
/// - `sideBySide`: Left half of the frame = left eye, right half = right eye.
///   This is the standard VR180 stereo encoding (Google Spatial Media spec).
enum StereoLayout: String, CaseIterable, Identifiable {
    case mono       = "Mono"
    case sideBySide = "Side-by-Side Stereo"

    var id: String { rawValue }
}
