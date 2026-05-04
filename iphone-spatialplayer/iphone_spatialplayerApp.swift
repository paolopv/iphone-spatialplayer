// SpatialPlayerApp.swift
// SpatialPlayer
//
// Author: PaoloPV
// iOS 26+ only — leverages modern SwiftUI scene lifecycle.

import SwiftUI

@main
struct SpatialPlayerApp: App {
    var body: some Scene {
        // Single window group; ContentView owns all navigation state.
        WindowGroup {
            ContentView()
        }
    }
}
