// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

///
/// An opaque cover that fades over whatever it is overlaid on for as long as something is loading, so a wait reads as one rather than as an empty screen.
///
/// It hides rather than annotates, which is the whole of its purpose: what sits behind a web view mid-load is either nothing at all or the page being replaced, and both are worse to look at than a spinner. `systemBackground` is what the app's own chrome is drawn against, so the cover matches the interface rather than the content — a web view showing a page themed by someone else's server will still meet a colour boundary as this lifts, and nothing here can know the theme of a page that has not loaded.
/// It swallows taps for the same reason it is opaque. A target under the finger belongs to whatever is being replaced, and following it would start a second load nobody asked for.
/// The fade is symmetric and deliberately not brief. A load short enough to finish before the cover has arrived reads as the page dimming and coming back rather than as a hard cut to a spinner and out again, and the price is the other end of it — the cover is still fading down over a page that has in fact already arrived.
/// The `ZStack` is what the animation hangs off: a transition needs a container that outlives the view it animates, and applying the animation to the call site's own chain instead would put every other change that view makes through it too.
///
struct LoadingOverlay: View {
    ///
    /// Whether there is something to wait for, which is the whole of what decides if this is on screen.
    ///
    let isLoading: Bool

    ///
    /// How long the cover takes to fade in, and to fade back out, in seconds.
    ///
    /// Long enough that a load finishing almost at once never resolves into a spinner, and short enough not to be the wait itself. One value for both directions, so the two cannot come to feel different from each other.
    ///
    private static let blendDuration: TimeInterval = 0.4

    var body: some View {
        ZStack {
            if isLoading {
                // A default spinner is 20 points across, which is a small thing to have to find in the middle of a
                // whole screen of nothing else.
                ProgressView()
                    .controlSize(.extraLarge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    // Hit tested as its whole rectangle rather than as the spinner alone.
                    .contentShape(.rect)
                    // Opacity alone: a cover the size of its host has nothing to scale or slide that would not read
                    // as the host itself moving.
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Self.blendDuration), value: isLoading)
    }
}

// A colour behind it, because a cover is only worth looking at against something it covers, and a tap to toggle,
// because the fade is the part worth seeing and a static preview never shows it.
#Preview {
    @Previewable @State
    var isLoading = true

    Color.orange
        .ignoresSafeArea()
        .overlay {
            LoadingOverlay(isLoading: isLoading)
        }
        .onTapGesture {
            isLoading.toggle()
        }
}
