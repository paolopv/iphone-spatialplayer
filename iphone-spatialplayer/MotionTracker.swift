// MotionTracker.swift
// SpatialPlayer
//
// Author: PaoloPV
// Streams device orientation as quaternions at 60 Hz using CoreMotion.

import CoreMotion
import simd

/// Actor-isolated wrapper around CMMotionManager.
/// Yields `simd_quatf` values in RealityKit's Y-up coordinate space.
actor MotionTracker {
    // CMMotionManager is not Sendable, so we suppress the concurrency check here.
    // It is only ever accessed from the actor's executor.
    private nonisolated(unsafe) let motionManager = CMMotionManager()

    /// An AsyncStream that emits a new quaternion on every motion update.
    /// The stream ends if device motion is not available on this hardware.
    var rotations: AsyncStream<simd_quatf> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            guard motionManager.isDeviceMotionAvailable else {
                continuation.finish()
                return
            }

            // 60 Hz gives smooth rendering without excessive CPU usage.
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0

            // xArbitraryZVertical: gravity aligns with Z, which matches CoreMotion's default.
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .init()) { motion, _ in
                guard let motion else { return }

                let q = motion.attitude.quaternion
                // CoreMotion delivers quaternions in a Z-up frame.
                // Rotate –90° around X to arrive at RealityKit's Y-up frame.
                let rawQuat = simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
                let toYUp = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
                continuation.yield(toYUp * rawQuat)
            }

            // Stop the hardware sensor when the consumer cancels the stream.
            continuation.onTermination = { [weak self] _ in
                self?.motionManager.stopDeviceMotionUpdates()
            }
        }
    }
}
