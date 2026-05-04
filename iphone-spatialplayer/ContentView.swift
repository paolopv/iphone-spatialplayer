// ContentView.swift
// SpatialPlayer
//
// Author: PaoloPV
// Landing screen: URL input, video format pickers, and mode selection.

import SwiftUI

// Built-in Apple 360° Lighthouse demo — used when no custom URL is entered.
private let defaultHLSURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/immersive-media/360Lighthouse/mvp.m3u8"

struct ContentView: View {
    @State private var selectedMode: ViewMode?

    // Video source
    @State private var urlString: String = defaultHLSURL
    @State private var urlIsInvalid = false

    // Format options — these are passed straight through to the player views.
    @State private var videoAngle: VideoAngle  = .full
    @State private var stereoLayout: StereoLayout = .mono

    var body: some View {
        ZStack {
            backgroundGradient

            if selectedMode == nil {
                menuView
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }

            if let mode = selectedMode, let url = validatedURL {
                PlayerViewContainer(selectedMode: $selectedMode) {
                    mode.playerView(url: url, angle: videoAngle, stereo: stereoLayout)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.4), value: selectedMode)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(white: 0.06), Color(white: 0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var menuView: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                urlInputSection
                formatSection
                modeSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: 540)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.badge.waveform.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 4)

            Text("Porthole")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Immersive Video Player")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: URL input

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Video Stream URL", icon: "link")

            HStack(spacing: 10) {
                TextField("https://…/playlist.m3u8", text: $urlString)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit { validateURL() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                urlIsInvalid ? Color.red.opacity(0.8) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                    .modifier(ShakeEffect(trigger: urlIsInvalid))

                // Paste from clipboard
                iconButton("doc.on.clipboard") {
                    if let clip = UIPasteboard.general.string {
                        urlString = clip
                        urlIsInvalid = false
                    }
                }

                // Reset to built-in demo
                iconButton("arrow.counterclockwise") {
                    urlString = defaultHLSURL
                    urlIsInvalid = false
                }
            }

            if urlIsInvalid {
                Label("Enter a valid HLS or HTTP video URL", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.85))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Format pickers

    /// Video format options — angle and stereo layout.
    /// These change the rendering geometry and which half of the frame each eye sees.
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Video Format", icon: "film.stack")

            // 360° vs 180° — affects yaw clamping in all modes.
            VStack(alignment: .leading, spacing: 8) {
                Text("Coverage")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))

                Picker("Coverage", selection: $videoAngle) {
                    ForEach(VideoAngle.allCases) { angle in
                        Text(angle.rawValue).tag(angle)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Mono vs Side-by-Side stereo — only meaningful in Cardboard mode,
            // but shown here so the user sets it before launching.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Stereo Layout")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                    Text("Cardboard only")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                Picker("Stereo Layout", selection: $stereoLayout) {
                    ForEach(StereoLayout.allCases) { layout in
                        Text(layout.rawValue).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: Mode cards

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Choose a Mode", icon: "play.circle")

            ForEach(ViewMode.allCases) { mode in
                ModeCard(mode: mode) {
                    guard validatedURL != nil else { triggerInvalidURL(); return }
                    selectedMode = mode
                }
                .disabled(!mode.isAvailable)
            }
        }
    }

    // MARK: - Helpers

    private var validatedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }

    private func validateURL() {
        if validatedURL == nil { triggerInvalidURL() }
    }

    private func triggerInvalidURL() {
        withAnimation(.spring(duration: 0.3)) { urlIsInvalid = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { urlIsInvalid = false }
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(12)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Mode Card

private struct ModeCard: View {
    let mode: ViewMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: mode.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(mode.isAvailable ? .white : .white.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .background(
                        mode.isAvailable
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(mode.title)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(mode.isAvailable ? .white : .white.opacity(0.35))

                        if !mode.isAvailable {
                            Text("Not Available")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.08), in: Capsule())
                        }
                    }

                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(mode.isAvailable ? 0.55 : 0.25))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if mode.isAvailable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(16)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Player Container

/// Wraps the active player view and shows a translucent close button on tap.
struct PlayerViewContainer<Content: View>: View {
    @Binding var selectedMode: ViewMode?
    @ViewBuilder let content: () -> Content
    @State private var showOverlay = false

    var body: some View {
        ZStack(alignment: .top) {
            content()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() }
                }

            if showOverlay {
                closeButton
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 56)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
    }

    private var closeButton: some View {
        Button { selectedMode = nil } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shake Effect

/// Horizontal shake animation used to signal an invalid URL.
private struct ShakeEffect: ViewModifier {
    var trigger: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: trigger ? -6 : 0)
            .animation(
                trigger
                    ? .easeInOut(duration: 0.07).repeatCount(4, autoreverses: true)
                    : .default,
                value: trigger
            )
    }
}
