// GimbalPlayerViewModel.swift
// SpatialPlayer
//
// Author: PaoloPV
// Camera rotation logic for Gimbal mode.
// Combines device motion with drag offsets using a yaw-pitch-roll gimbal model.
// For 180° video, total yaw is clamped to ±90° so the user cannot look behind the content.

import AVFoundation
import CoreGraphics
import RealityKit
import simd

@MainActor @Observable
final class GimbalPlayerViewModel {

    // MARK: - Public state

    let player = AVPlayer()
    private(set) var cameraRotation: simd_quatf = .identity

    // MARK: - Private state

    private let videoURL: URL
    private let angle: VideoAngle

    private let motionTracker = MotionTracker()
    private var motionTask: Task<Void, Never>?

    /// Radians of rotation applied per screen-space pixel dragged.
    private let dragSensitivity: Float = 0.003

    /// Accumulated yaw and pitch added on top of device orientation via drag.
    private var yawOffset: Float = 0
    private var pitchOffset: Float = 0

    private var lastDeviceRotation: simd_quatf = .identity
    private var lastDragValue: CGSize = .zero

    /// Device roll, isolated from the full device rotation quaternion.
    /// Used to align drag axes with the physical screen axes.
    private var deviceRoll: Float = 0

    // MARK: - Init

    init(videoURL: URL, angle: VideoAngle) {
        self.videoURL = videoURL
        self.angle    = angle
    }

    // MARK: - Playback

    func play() {
        player.replaceCurrentItem(with: AVPlayerItem(url: videoURL))
        player.play()
    }

    func cleanup() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Motion tracking

    func startMotionTracking() {
        motionTask = Task { [weak self] in
            guard let self else { return }
            for await deviceRotation in await motionTracker.rotations {
                updateCameraRotation(with: deviceRotation)
            }
        }
    }

    func stopMotionTracking() {
        motionTask?.cancel()
        motionTask = nil
    }

    // MARK: - Drag gesture

    /// Accumulates a drag delta onto the yaw/pitch offsets.
    ///
    /// The screen-space delta is rotated by `deviceRoll` first so that
    /// dragging "up" always tilts the view upward regardless of device tilt.
    func handleDrag(translation: CGSize) {
        let delta = CGSize(
            width:  translation.width  - lastDragValue.width,
            height: translation.height - lastDragValue.height
        )
        lastDragValue = translation

        let rollTransform = CGAffineTransform(rotationAngle: CGFloat(deviceRoll))
        let worldDelta    = CGPoint(x: delta.width, y: delta.height).applying(rollTransform)

        yawOffset   += Float(worldDelta.x) * dragSensitivity
        pitchOffset += Float(worldDelta.y) * dragSensitivity

        // If 180° mode, clamp the drag yaw offset so the total yaw can't exceed ±90°.
        if let limit = angle.yawLimit {
            let deviceYaw = extractYaw(from: lastDeviceRotation)
            yawOffset = max(-limit - deviceYaw, min(limit - deviceYaw, yawOffset))
        }

        updateCameraRotation(with: lastDeviceRotation)
    }

    func handleDragEnd() {
        lastDragValue = .zero
    }

    // MARK: - Rotation math

    /// Recomputes `cameraRotation` from the latest device orientation and drag offsets.
    ///
    /// The model is a gimbal head:
    ///  1. Extract yaw and pitch by projecting the forward vector.
    ///  2. Isolate roll by subtracting the yaw-pitch gimbal from the full rotation.
    ///  3. Add drag offsets; apply the `yawLimit` from `VideoAngle` for 180° content.
    ///  4. Compose: yaw × pitch × roll.
    private func updateCameraRotation(with deviceRotation: simd_quatf) {
        lastDeviceRotation = deviceRotation

        let forward     = deviceRotation.act(SIMD3<Float>(0, 0, -1))
        let deviceYaw   = atan2(-forward.x, -forward.z)
        let devicePitch = asin(max(-1, min(1, forward.y)))

        // Isolate roll: what remains after removing the yaw-pitch component.
        let yawQuat    = simd_quatf(angle: deviceYaw,   axis: SIMD3<Float>(0, 1, 0))
        let pitchQuat  = simd_quatf(angle: devicePitch, axis: SIMD3<Float>(1, 0, 0))
        let rollQuat   = (yawQuat * pitchQuat).inverse * deviceRotation
        deviceRoll = -2 * atan2(rollQuat.vector.z, rollQuat.vector.w)

        // Total yaw: clamp to ±yawLimit for 180° video, unlimited for 360°.
        var totalYaw = deviceYaw + yawOffset
        if let limit = angle.yawLimit {
            totalYaw = max(-limit, min(limit, totalYaw))
        }

        let totalPitch = max(-.pi / 2, min(.pi / 2, devicePitch + pitchOffset))

        let totalYawQuat   = simd_quatf(angle: totalYaw,   axis: SIMD3<Float>(0, 1, 0))
        let totalPitchQuat = simd_quatf(angle: totalPitch, axis: SIMD3<Float>(1, 0, 0))
        let totalRollQuat  = simd_quatf(angle: deviceRoll, axis: SIMD3<Float>(0, 0, -1))

        cameraRotation = totalYawQuat * totalPitchQuat * totalRollQuat
    }

    /// Extracts the yaw angle from a quaternion by projecting its forward vector.
    private func extractYaw(from q: simd_quatf) -> Float {
        let forward = q.act(SIMD3<Float>(0, 0, -1))
        return atan2(-forward.x, -forward.z)
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stopMotionTracking()
            self?.cleanup()
        }
    }
}

// MARK: - Helpers

private extension simd_quatf {
    static var identity: simd_quatf { simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
}
