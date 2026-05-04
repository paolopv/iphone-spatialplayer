// DevicePPI.swift
// SpatialPlayer
//
// Author: PaoloPV
// Resolves the physical pixel density and screen height for the current device.
// Used by Portal mode to calculate a geometrically accurate field of view.

import UIKit

/// Returns the pixel density (PPI) for the current device model.
///
/// We query the machine identifier at runtime so no per-device target
/// conditionals are needed. All models capable of running iOS 26 are listed.
func getDevicePPI() -> Float {
    var systemInfo = utsname()
    uname(&systemInfo)
    let modelID = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(validatingCString: $0) ?? "Unknown"
        }
    }

    switch modelID {
    // ── 326 PPI ──────────────────────────────────────────────────────────────
    // iPhone 11 (last device at this density still meeting iOS 26 requirements)
    case "iPhone12,1":
        return 326

    // ── 458 PPI ──────────────────────────────────────────────────────────────
    // iPhone 11 Pro / Pro Max, 12 Pro Max, 13 Pro Max, 14 Plus
    case "iPhone12,3", "iPhone12,5",
         "iPhone13,4",
         "iPhone14,3",
         "iPhone14,8":
        return 458

    // ── 460 PPI ──────────────────────────────────────────────────────────────
    // iPhone 12, 12 Pro, 13, 13 Pro, 14, 14 Pro/Max, 15 series, 16 series
    case "iPhone13,2", "iPhone13,3",
         "iPhone14,5", "iPhone14,2",
         "iPhone14,7",
         "iPhone15,2", "iPhone15,3",
         "iPhone15,4", "iPhone15,5",
         "iPhone16,1", "iPhone16,2",
         "iPhone17,1", "iPhone17,2",
         "iPhone17,3", "iPhone17,4":
        return 460

    // ── 476 PPI ──────────────────────────────────────────────────────────────
    // iPhone mini models (12 mini, 13 mini)
    case "iPhone13,1", "iPhone14,4":
        return 476

    // ── 264 PPI ──────────────────────────────────────────────────────────────
    // iPad Pro with Face ID (all generations that support iOS 26)
    case let id where id.hasPrefix("iPad13,"),
         let id where id.hasPrefix("iPad14,"),
         let id where id.hasPrefix("iPad16,"):
        return 264

    // Simulator — use a typical OLED density so Portal mode works in previews.
    case "x86_64", "arm64":
        return 460

    // Unknown future hardware — assume a common high-density display.
    default:
        return 460
    }
}

/// Returns the physical height of the device screen in meters.
///
/// Uses the active foreground window scene's screen instead of the
/// deprecated `UIScreen.main` singleton.
@MainActor
func getScreenHeightMeters() -> Float {
    // Prefer the active foreground window scene; fall back to any connected scene.
    // UIScreen.main is deprecated on iOS 26 — we never use it.
    let screen = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first(where: { $0.activationState == .foregroundActive })?.screen
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen

    guard let screen else {
        // No window scene available yet (e.g. very early launch).
        // Return a typical 6.1" iPhone screen height as a safe default.
        return 0.144
    }

    let heightPixels = Float(screen.bounds.height * screen.nativeScale)
    let heightInches = heightPixels / getDevicePPI()
    return heightInches * 0.0254  // 1 inch = 0.0254 m
}
