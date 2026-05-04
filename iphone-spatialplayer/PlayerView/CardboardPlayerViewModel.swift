// CardboardPlayerViewModel.swift
// SpatialPlayer
//
// Author: PaoloPV
// Drives Cardboard split-screen VR mode.
//
// ## How Cardboard stereo works
// The screen is split vertically in half. Each half shows the scene from a camera
// offset by half the Inter-Pupillary Distance (IPD) to the left or right.
// When inserted into a Cardboard headset, each eye sees only its half of the screen,
// creating a stereo depth illusion through parallax.
//
// ## Stereo video (Side-by-Side)
// For SBS-format video (left half = left eye, right half = right eye), we build two
// separate AVPlayerItems from the same asset. Each item has an AVMutableVideoComposition
// that crops the frame to the appropriate half before it reaches VideoMaterial.
// Both items are advanced in lock-step by seeking them to t=0 and calling play()
// at the same time, which gives effectively synchronised playback.
//
// ## Barrel distortion
// Cardboard lenses introduce barrel distortion that is ideally corrected with a
// post-processing Metal shader. That correction is not implemented here; the image
// will look slightly "zoomed in" through the lenses rather than edge-distorted.

import AVFoundation
import RealityKit
import simd

@MainActor @Observable
final class CardboardPlayerViewModel {

    // MARK: - Constants

    /// Standard inter-pupillary distance (63 mm). Each camera is offset by half this.
    static let ipd: Float = 0.063

    static var leftEyeOffset:  SIMD3<Float> { SIMD3<Float>(-ipd / 2, 0, 0) }
    static var rightEyeOffset: SIMD3<Float> { SIMD3<Float>( ipd / 2, 0, 0) }

    // MARK: - Public state

    /// For mono video, both eyes share the same player.
    /// For SBS stereo, this is the left-eye player.
    private(set) var leftPlayer  = AVPlayer()
    /// For mono, this is the same instance as `leftPlayer`.
    /// For SBS stereo, this carries the right-eye cropped composition.
    private(set) var rightPlayer = AVPlayer()

    private(set) var cameraRotation: simd_quatf = .identity

    // MARK: - Private state

    private let videoURL: URL
    private let angle: VideoAngle
    private let stereo: StereoLayout

    private let motionTracker = MotionTracker()
    private var motionTask: Task<Void, Never>?

    // MARK: - Init

    init(videoURL: URL, angle: VideoAngle, stereo: StereoLayout) {
        self.videoURL = videoURL
        self.angle    = angle
        self.stereo   = stereo
    }

    // MARK: - Playback

    /// Sets up the player(s) for the chosen stereo layout and starts playback.
    func play() {
        switch stereo {
        case .mono:
            // Single player: both eyes see identical frames.
            let item = AVPlayerItem(url: videoURL)
            leftPlayer.replaceCurrentItem(with: item)
            rightPlayer = leftPlayer          // share the same instance
            leftPlayer.play()

        case .sideBySide:
            // Two players from the same asset, each cropped to one horizontal half.
            // Cropping is done asynchronously once the video track dimensions are known.
            Task { await self.setupSBSPlayers() }
        }
    }

    func cleanup() {
        leftPlayer.pause()
        leftPlayer.replaceCurrentItem(with: nil)
        // Only pause rightPlayer separately if it's a different instance (SBS mode).
        if rightPlayer !== leftPlayer {
            rightPlayer.pause()
            rightPlayer.replaceCurrentItem(with: nil)
        }
    }

    // MARK: - Motion tracking

    func startMotionTracking() {
        motionTask = Task { [weak self] in
            guard let self else { return }
            for await deviceRotation in await motionTracker.rotations {
                applyRotation(deviceRotation)
            }
        }
    }

    func stopMotionTracking() {
        motionTask?.cancel()
        motionTask = nil
    }

    // MARK: - SBS setup

    /// Builds two AVPlayerItems from the same URL, each with a video composition
    /// that crops to the left or right half of the frame respectively.
    private func setupSBSPlayers() async {
        let asset = AVURLAsset(url: videoURL)

        do {
            // Load the video track to discover the frame dimensions.
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first else { return }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let duration    = try await asset.load(.duration)

            let halfWidth = naturalSize.width / 2

            // Left-eye item: crop to the LEFT half of the frame.
            // The video composition sets the render size to half the frame width,
            // so the output naturally shows only the left half.
            let leftItem  = makeEyeItem(
                asset: asset,
                videoTrack: videoTrack,
                naturalSize: naturalSize,
                halfWidth: halfWidth,
                duration: duration,
                isRight: false
            )

            // Right-eye item: translate the video –halfWidth on X before rendering,
            // which shifts the right half into the render window.
            let rightItem = makeEyeItem(
                asset: asset,
                videoTrack: videoTrack,
                naturalSize: naturalSize,
                halfWidth: halfWidth,
                duration: duration,
                isRight: true
            )

            // Swap in the cropped items and start both players simultaneously.
            leftPlayer.replaceCurrentItem(with: leftItem)
            rightPlayer.replaceCurrentItem(with: rightItem)

            // Seek both to t=0 before starting so they are frame-aligned.
            await leftPlayer.seek(to: .zero)
            await rightPlayer.seek(to: .zero)

            leftPlayer.play()
            rightPlayer.play()

        } catch {
            // If we can't load the asset, fall back to mono (same player on both eyes).
            let item = AVPlayerItem(url: videoURL)
            leftPlayer.replaceCurrentItem(with: item)
            rightPlayer = leftPlayer
            leftPlayer.play()
        }
    }

    /// Builds an `AVPlayerItem` that renders only one horizontal half of the source frame.
    private func makeEyeItem(
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        naturalSize: CGSize,
        halfWidth: CGFloat,
        duration: CMTime,
        isRight: Bool
    ) -> AVPlayerItem {
        let renderSize = CGSize(width: halfWidth, height: naturalSize.height)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

        if isRight {
            // Shift the video frame left by halfWidth so the right portion fills the render window.
            layerInstruction.setTransform(CGAffineTransform(translationX: -halfWidth, y: 0), at: .zero)
        }
        // Left eye: identity transform — the render size already crops to the left half.

        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize    = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)
        videoComposition.instructions  = [instruction]

        let item = AVPlayerItem(asset: asset)
        item.videoComposition = videoComposition
        return item
    }

    // MARK: - Rotation

    /// Applies device rotation with optional yaw clamping for 180° content.
    private func applyRotation(_ deviceRotation: simd_quatf) {
        guard let limit = angle.yawLimit else {
            cameraRotation = deviceRotation
            return
        }

        let forward = deviceRotation.act(SIMD3<Float>(0, 0, -1))
        let yaw     = max(-limit, min(limit, atan2(-forward.x, -forward.z)))
        let pitch   = asin(max(-1, min(1, forward.y)))

        let baseQuat = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: SIMD3<Float>(0, 1, 0))
                     * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        let rollQuat = baseQuat.inverse * deviceRotation
        let roll     = -2 * atan2(rollQuat.vector.z, rollQuat.vector.w)

        cameraRotation = simd_quatf(angle: yaw,   axis: SIMD3<Float>(0, 1, 0))
                       * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
                       * simd_quatf(angle: roll,  axis: SIMD3<Float>(0, 0, -1))
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
