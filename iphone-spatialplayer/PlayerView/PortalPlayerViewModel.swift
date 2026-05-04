// PortalPlayerViewModel.swift
// SpatialPlayer
//
// Author: PaoloPV
// Drives Portal mode: device motion controls camera orientation,
// and ARKit face tracking dynamically adjusts the FOV for life-size rendering.
// Supports 180° yaw clamping in the same way as Gimbal mode.

import ARKit
import AVFoundation
import RealityKit
import simd

@MainActor @Observable
final class PortalPlayerViewModel {

    // MARK: - Public state

    let player = AVPlayer()
    private(set) var cameraRotation: simd_quatf = .identity
    private(set) var fieldOfView: Float = 60

    // MARK: - Private state

    private let videoURL: URL
    private let angle: VideoAngle
    private let motionTracker = MotionTracker()
    private let faceTracker: FaceTracker
    private var motionTask: Task<Void, Never>?
    private var faceTrackingTask: Task<Void, Never>?

    // MARK: - Init

    init(videoURL: URL, angle: VideoAngle, screenHeightMeters: Float) {
        self.videoURL    = videoURL
        self.angle       = angle
        self.faceTracker = FaceTracker(screenHeightMeters: screenHeightMeters)
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
            for await rotation in await motionTracker.rotations {
                applyRotation(rotation)
            }
        }
    }

    func stopMotionTracking() {
        motionTask?.cancel()
        motionTask = nil
    }

    // MARK: - Face tracking

    func startFaceTracking() {
        faceTrackingTask = Task { [weak self] in
            guard let self else { return }
            for await fov in await faceTracker.fieldOfView {
                self.fieldOfView = fov
            }
        }
    }

    func stopFaceTracking() {
        faceTrackingTask?.cancel()
        faceTrackingTask = nil
    }

    // MARK: - Rotation

    /// Applies the device rotation, clamping yaw if the video is 180°.
    private func applyRotation(_ deviceRotation: simd_quatf) {
        guard let limit = angle.yawLimit else {
            // 360° — use the rotation directly.
            cameraRotation = deviceRotation
            return
        }

        // 180° — extract yaw and clamp it, then recompose.
        let forward   = deviceRotation.act(SIMD3<Float>(0, 0, -1))
        let yaw       = max(-limit, min(limit, atan2(-forward.x, -forward.z)))
        let pitch     = asin(max(-1, min(1, forward.y)))

        // Isolate roll.
        let baseQuat  = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: SIMD3<Float>(0, 1, 0))
                      * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let rollQuat  = baseQuat.inverse * deviceRotation
        let roll      = -2 * atan2(rollQuat.vector.z, rollQuat.vector.w)

        cameraRotation = simd_quatf(angle: yaw,   axis: SIMD3<Float>(0, 1, 0))
                       * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
                       * simd_quatf(angle: roll,  axis: SIMD3<Float>(0, 0, -1))
    }
}

// MARK: - Face Tracker

/// Actor that manages an ARSession for face tracking and streams calibrated FOV values.
actor FaceTracker {
    private nonisolated(unsafe) let session = ARSession()
    private let screenHeightMeters: Float
    private var delegate: Delegate?

    init(screenHeightMeters: Float) {
        self.screenHeightMeters = screenHeightMeters
    }

    /// Emits a new vertical FOV (degrees) whenever the tracked face moves.
    /// The stream ends immediately if TrueDepth face tracking is not supported.
    var fieldOfView: AsyncStream<Float> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            guard ARFaceTrackingConfiguration.isSupported else {
                continuation.finish()
                return
            }

            let delegate = Delegate(screenHeightMeters: screenHeightMeters, continuation: continuation)
            self.delegate = delegate
            session.delegate = delegate

            // Light estimation disabled — we only need face geometry.
            let config = ARFaceTrackingConfiguration()
            config.isLightEstimationEnabled = false
            session.run(config)

            continuation.onTermination = { [weak self] _ in
                self?.session.pause()
            }
        }
    }
}

// MARK: - Face Tracker Delegate

extension FaceTracker {
    /// Converts face anchor data into a calibrated vertical FOV.
    final class Delegate: NSObject, ARSessionDelegate {
        private let screenHeightMeters: Float
        private let continuation: AsyncStream<Float>.Continuation

        init(screenHeightMeters: Float, continuation: AsyncStream<Float>.Continuation) {
            self.screenHeightMeters = screenHeightMeters
            self.continuation       = continuation
        }

        /// Called by ARKit on every tracked-face update.
        ///
        /// ## FOV derivation
        /// 1. Average left and right eye world positions from `ARFaceAnchor`.
        /// 2. Add 7 mm for the optical centre behind the cornea.
        /// 3. The front camera is at the *top* of the screen, not the centre.
        ///    Correct for this using: `d_centre = √(d_camera² – (h/2)²)`.
        /// 4. `FOV = 2 × atan(h/2 / d_centre)` — the FOV that makes 1 m virtual = 1 m real.
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }

            let lWorld = face.transform * face.leftEyeTransform.columns.3
            let rWorld = face.transform * face.rightEyeTransform.columns.3
            let eyeCenter = (lWorld + rWorld) / 2.0

            let distanceFromCamera = length(SIMD3<Float>(eyeCenter.x, eyeCenter.y, eyeCenter.z)) + 0.007

            let halfH    = screenHeightMeters / 2.0
            let dSquared = distanceFromCamera * distanceFromCamera - halfH * halfH
            guard dSquared > 0 else { return }

            let fov = 2.0 * atan(halfH / sqrt(dSquared)) * 180.0 / .pi
            continuation.yield(fov)
        }
    }
}

// MARK: - Helpers

private extension simd_quatf {
    static var identity: simd_quatf { simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
}
