// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

/// `WebPageInsets` is one measurement of how much of the web view the app's own interface covers, in the order `window.Cirruscope.applySafeAreaInsets` takes its four arguments.
struct WebPageInsets: Equatable, Sendable {
    /// The margin covered at the top of the web view, in points.
    let top: CGFloat

    /// The margin covered at the physically right edge of the web view, in points.
    let right: CGFloat

    /// The margin covered at the bottom of the web view, in points.
    let bottom: CGFloat

    /// The margin covered at the physically left edge of the web view, in points.
    let left: CGFloat

    /// Creates a measurement from SwiftUI's layout-direction-relative edges.
    init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat, isRightToLeft: Bool) {
        self.top = Self.sanitized(top)
        self.bottom = Self.sanitized(bottom)
        left = Self.sanitized(isRightToLeft ? trailing : leading)
        right = Self.sanitized(isRightToLeft ? leading : trailing)
    }

    /// The JavaScript statement that invokes `function` with this measurement.
    func invocation(of function: String) -> String {
        "\(function)(\(top), \(right), \(bottom), \(left));"
    }

    /// Reduces a measured value to the finite, non-negative number the script can be handed.
    private static func sanitized(_ value: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : 0
    }
}
