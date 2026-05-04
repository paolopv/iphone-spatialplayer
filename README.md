# iphone-spatialplayer

**iphone-spatialplayer** is an immersive 360°/180° spatial video player for iPhone. It turns your device into a motion-tracked VR viewer with three distinct playback modes, each leveraging different iPhone sensors to place you inside a video.

---

## Features

- Stream equirectangular 360° or 180° video over HLS (`.m3u8`) or HTTP
- Three playback modes: Gimbal, Portal, and Cardboard
- Gyroscope + accelerometer tracking at 60 Hz via CoreMotion
- Stereo side-by-side video support for VR headsets
- No external dependencies — pure Swift + Apple frameworks

---

## How It Works

The player renders video onto the inside of a sphere using RealityKit. The camera sits at the centre of the sphere, and motion tracking rotates the camera in response to how you physically move and orient the iPhone. The result is a seamless "look around" experience where the video surrounds you.

### Motion Tracking & Video Positioning

Device orientation is captured using CoreMotion's `CMMotionManager`, which streams quaternion data at 60 Hz. The raw quaternion is converted from CoreMotion's Z-up coordinate frame into RealityKit's Y-up frame by applying a −90° rotation around the X-axis. This quaternion drives the camera rotation inside the sphere every frame.

For 180° videos, the yaw is clamped to ±90° so the camera never rotates past the edge of the recorded hemisphere into undefined space.

---

## Playback Modes

### Gimbal Mode
The primary single-screen mode. The gyroscope drives full 360° (or 180°) camera rotation, and you can also drag on screen to pan the view. Drag deltas are rotated by the current device roll so swiping always feels natural regardless of how you're holding the phone. Works on any iPhone.

### Portal Mode
Uses ARKit face tracking (requires Face ID / TrueDepth camera) to turn the screen into a literal window into virtual space. The face anchor measures your eye-to-screen distance in real time. The field of view is calculated geometrically so that one virtual metre equals one real metre — the screen becomes a porthole you're looking through, not a scaled-down viewport.

### Cardboard Mode
Splits the screen vertically into left and right eye views for use with a Google Cardboard headset. Each half renders an independent RealityKit scene with cameras offset by ±31.5 mm (standard 63 mm IPD) to produce stereoscopic depth. For side-by-side stereo video, two `AVPlayerItem` instances crop the source video to their respective halves and are synchronised by seeking to `t=0` before playback begins.

> **Note: Cardboard mode is not fully working yet.** Lens barrel distortion correction is not implemented, so the image appears zoomed in through the headset lenses rather than filling them correctly with the right edge warping. A Metal post-processing pass would be needed to fix this.

---

## Video Formats

| Setting | Options |
|---|---|
| Coverage | 360° · 180° |
| Stereo Layout | Mono · Side-by-Side |

Input must be an equirectangular projection. HLS playlists (`.m3u8`) and direct HTTP video URLs are supported.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI |
| 3D Rendering | RealityKit |
| Video Playback | AVFoundation |
| Motion Tracking | CoreMotion |
| Face Tracking | ARKit |
| Spatial Math | SIMD / `simd_quatf` |

Requires iOS 18+ and Xcode 16+. Portal mode additionally requires a TrueDepth camera (iPhone X or later with Face ID).

---

## Project Structure

```
iphone-spatialplayer/
├── ContentView.swift               Landing UI — URL input, format pickers, mode selection
├── ViewMode.swift                  Mode enum and player view factory
├── VideoFormat.swift               Video angle and stereo layout enums
├── MotionTracker.swift             CoreMotion actor — 60 Hz quaternion stream
├── DevicePPI.swift                 Per-device screen metrics for Portal FOV calculation
├── iphone_spatialplayerApp.swift   App entry point
└── PlayerView/
    ├── GimbalPlayerView.swift
    ├── GimbalPlayerViewModel.swift
    ├── PortalPlayerView.swift
    ├── PortalPlayerViewModel.swift
    ├── CardboardPlayerView.swift
    └── CardboardPlayerViewModel.swift
```

---

## Permissions

The app requests the following permissions at runtime:

- **Camera** — used by Portal mode for ARKit face tracking to measure eye distance
- **Motion & Fitness** — used by all modes for gyroscope-based orientation tracking

---

## Known Limitations

- **Cardboard barrel distortion** — lens correction is not yet implemented; the image will appear zoomed in through Cardboard lenses
- **SBS sync drift** — two-player synchronisation for side-by-side stereo is based on seeking both to `t=0`; minor drift may occur under load
- **No adaptive drag sensitivity** — drag speed is fixed at 0.003 rad/px regardless of FOV or video coverage
