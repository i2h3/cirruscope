// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// `ActivityRedactedView` is the feed's shape without its content: grey circles and bars where rows would be.
///
/// It is what the widget shows before anything has been fetched, and what the system asks for when it wants the outline without the data — on a locked screen, or while the gallery is being browsed. Drawing the real layout with the values removed, rather than a spinner or an empty card, is what makes a widget feel like it is already there rather than still arriving.
/// The bar widths vary per row and are fixed rather than random. A redacted row that changed width between draws would read as content loading in, which is precisely what it is not.
struct ActivityRedactedView: View {
    /// `rowCount` is how many placeholder rows to draw, which matches what the size being drawn would really hold.
    let rowCount: Int

    /// `style` is the resolved appearance to draw in.
    let style: ActivityStyle

    /// `widths` are the proportions the design gives the bars, cycled through so successive rows differ as real ones would.
    private let widths: [(title: CGFloat, subtitle: CGFloat)] = [(0.82, 0.56), (0.64, 0.44), (0.74, 0.38)]

    /// `body` draws the rows.
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< rowCount, id: \.self) { index in
                row(widths[index % widths.count])
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// `row(_:)` is one redacted row: a circle, a wider bar, and a narrower one beneath it.
    private func row(_ width: (title: CGFloat, subtitle: CGFloat)) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(style.placeholderStrong)
                .frame(width: 21, height: 21)

            VStack(alignment: .leading, spacing: 4) {
                bar(height: 8, fraction: width.title, fill: style.placeholderStrong)
                bar(height: 6, fraction: width.subtitle, fill: style.placeholderWeak)
            }

            Spacer(minLength: 0)
        }
    }

    /// `bar(height:fraction:fill:)` is one placeholder bar, sized as a fraction of the width available to it.
    private func bar(height: CGFloat, fraction: CGFloat, fill: AnyShapeStyle) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: height / 2)
                .fill(fill)
                .frame(width: geometry.size.width * fraction, height: height)
        }
        .frame(height: height)
    }
}
