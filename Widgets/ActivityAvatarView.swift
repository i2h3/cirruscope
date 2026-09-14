// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `ActivityAvatarView` is the circle at the head of an activity row: whoever acted, badged with what they did.
///
/// The circle is the actor's profile photograph when the server has one, and their initials on a colour of their own when it does not — `ServerAvatars` caches only photographs precisely so that a missing one lands here as the monogram the design specifies rather than as the monogram Nextcloud draws.
/// The badge sits on the circle's corner and has to read over a photograph as well as over a flat fill, which is what the ring is for. The ring takes the *card's* colour rather than white, so on a dark card it reads as a cut-out rather than as a white outline the design never asks for.
/// A tinted or clear Home Screen, and the Lock Screen, hand the widget an accented or vibrant rendering rather than full colour. There the system throws away every colour and keeps only the alpha, flattening each opaque fill to a single white — which would leave the circle and its badge as blank white discs with their monogram and glyph tinted invisibly into them. So in those modes the symbols and the ring are punched out of the fills as transparency instead of drawn in a second colour the system has already discarded, and the photograph is desaturated so it maps to a shaded portrait rather than a white disc. `compositingGroup()` is what lets one view's transparency cut into another's fill beneath it.
struct ActivityAvatarView: View {
    /// `row` is the activity this circle belongs to, which supplies both the actor and the verb.
    let row: ActivityRow

    /// `diameter` is the circle's size, which the design varies per layout — 21 points on iOS small, 22 on medium, 23 on large.
    let diameter: CGFloat

    /// `style` is the resolved appearance to draw in.
    let style: ActivityStyle

    /// `renderingMode` is how the system is drawing the widget: full colour on a plain Home Screen, and an accented or vibrant template on a tinted or clear one and on the Lock Screen.
    @Environment(\.widgetRenderingMode)
    private var renderingMode

    /// `badgeDiameter` is the badge's size.
    private var badgeDiameter: CGFloat {
        diameter / 1.6
    }

    /// `body` composes the circle and its badge.
    var body: some View {
        circle
            .frame(width: diameter, height: diameter)
            .overlay(alignment: .bottomTrailing) {
                badge.offset(x: diameter / 4, y: diameter / 4)
            }
            // Without this the badge's overhang is clipped by the row's bounds on the trailing edge of a narrow layout.
            .frame(width: diameter, height: diameter, alignment: .center)
            // Composing the circle and badge as one layer is what lets a punched-out symbol or ring cut through to the
            // glass behind rather than merely erasing back to the fill it sits on.
            .compositingGroup()
    }

    /// `isTemplated` is whether the system is tinting the widget to a single colour, which is every mode but full colour.
    private var isTemplated: Bool {
        renderingMode != .fullColor
    }

    /// `circle` is the photograph when one is cached, and the monogram when none is.
    @ViewBuilder
    private var circle: some View {
        if let actorID = row.actorID, let image = ServerAvatars.shared.image(forUserID: actorID, serverAddress: serverAddress) {
            Image(decorative: image, scale: 1)
                .resizable()
                // Left alone, an accented rendering would flatten the photograph to a solid white disc. Desaturating it
                // maps its luminance to the alpha channel instead, so it reads as the shaded portrait it is. This is an
                // `Image` modifier, so it has to sit before the shape modifiers below turn it into a plain view.
                .widgetAccentedRenderingMode(.desaturated)
                .aspectRatio(contentMode: .fill)
                .clipShape(.circle)
        } else {
            Circle()
                .fill(isTemplated ? Color.white : style.avatarFill(for: row.actorName ?? ""))
                .overlay {
                    monogram
                        .foregroundStyle(.white)
                        // On a tinted fill the white monogram would vanish into it, so it is cut out of the disc as
                        // transparency the glass shows through instead.
                        .blendMode(isTemplated ? .destinationOut : .normal)
                }
        }
    }

    /// `monogram` is the actor's initials, or a figure standing in for them where there are none to draw.
    ///
    /// The server names no actor at all for your own activities — the sentence it renders is "You changed …", with no participant to resolve — so the rows that are yours have no name to take initials from. That used to leave an empty disc, which reads as a portrait that failed to load rather than as a fact about the row, and it became the only thing marking those rows once the subtitle stopped naming anybody.
    @ViewBuilder
    private var monogram: some View {
        if row.initials.isEmpty {
            Image(systemName: "person.fill")
                .font(.system(size: diameter * 0.42))
        } else {
            Text(verbatim: row.initials)
                .font(.system(size: diameter * 0.45, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    /// `badge` is the verb marker on the circle's corner.
    private var badge: some View {
        ZStack {
            // On a tinted fill the badge and the circle both flatten to the same white and merge where they overlap.
            // Clearing a ring of the circle beneath the badge restores the separation the drawn ring gives in full colour.
            if isTemplated {
                Circle()
                    .frame(width: badgeDiameter + 4, height: badgeDiameter + 4)
                    .blendMode(.destinationOut)
            }

            Circle()
                .fill(isTemplated ? Color.white : style.badgeColor(for: row.verb))
                .overlay {
                    if !isTemplated {
                        Circle().strokeBorder(style.cardBackground, lineWidth: 1)
                    }
                }
                .overlay {
                    Image(systemName: row.verb.imageSystemName)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        // As with the monogram, the glyph is punched out of a tinted badge rather than drawn white on white.
                        .blendMode(isTemplated ? .destinationOut : .normal)
                }
                .frame(width: badgeDiameter, height: badgeDiameter)
        }
    }

    /// `serverAddress` is the instance the cached photograph would have been stored under, or a placeholder when no account is configured.
    ///
    /// A widget drawing rows always has an account, those rows having come from one. The fallback exists because this is a view and cannot fail: with no account there is also no cached photograph, so it resolves to the monogram either way.
    private var serverAddress: URL {
        Keychain.accounts().first?.server ?? URL(string: "https://localhost")!
    }
}

extension ActivityVerb {
    var imageSystemName: String {
        switch self {
            case .created: "plus"
            case .changed: "arrow.trianglehead.2.clockwise.rotate.90"
            case .deleted: "xmark"
            case .restored: "arrow.counterclockwise"
        }
    }
}
