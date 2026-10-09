// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation
import WebKit

///
/// `RecordedNavigationAction` is what `NavigationTypeProbe` kept of one navigation action its navigation delegate was asked to decide.
///
struct RecordedNavigationAction: Equatable, Sendable {
    ///
    /// `navigationType` is the action's `WKNavigationAction.navigationType`, which is what `SignOutRequest` judges.
    ///
    let navigationType: WKNavigationType

    ///
    /// `target` is the frame the action would load into.
    ///
    let target: NavigationActionTarget
}
