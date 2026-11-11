// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI
import WidgetKit

/// `WidgetsBundle` is the extension's entry point, listing every widget the extension offers.
@main
struct WidgetsBundle: WidgetBundle {
    /// `body` lists the widgets on offer, in the order the widget gallery presents them.
    var body: some Widget {
        ActivityWidget()
    }
}
