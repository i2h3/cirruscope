// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import Foundation

/// `PageTitle` shortens the title a Nextcloud page gives itself to the part worth showing in the app's own interface.
enum PageTitle {
    /// `separator` is the string Nextcloud joins a title's components with.
    private static let separator = " - "

    /// `withoutSiteName(_:)` is `title` with its trailing instance-name component removed, or `title` unchanged when there is no such component to remove.
    ///
    /// Positional rather than matched against the instance's real name, because the name is not known where this is used: the server reports it on the theming capability, but neither app stores it. Dropping the last component instead needs nothing but the title.
    /// The cost of that is an instance whose own name contains the separator, which is then only partly removed. That is a worse title rather than a wrong one, and it is the reason this returns the input untouched whenever the result would be empty or there is only one component: a title is a label, and no rule for shortening it is worth showing the user nothing.
    static func withoutSiteName(_ title: String) -> String {
        let components = title.components(separatedBy: Self.separator)

        guard components.count >= 2 else {
            return title
        }

        let shortened = components.dropLast().joined(separator: Self.separator)

        guard shortened.isEmpty == false else {
            return title
        }

        return shortened
    }
}
