// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

import SwiftUI

/// `ActivityMessageView` is the widget with something to say instead of a feed: a headline, a sentence, and sometimes a footnote or a call to action.
///
/// The three states that use it are deliberately one view. They differ in wording and in whether they invite an action, not in shape, and writing them as one layout is what stops them drifting into three slightly different ideas of where a headline sits.
struct ActivityMessageView: View {
    /// `headline` is the short statement, read first.
    let headline: LocalizedStringKey

    /// `message` is the sentence under it, explaining or instructing.
    let message: LocalizedStringKey

    /// `callToAction` is the pill inviting somebody to open the app, shown only where there is something for them to do there.
    var callToAction: LocalizedStringKey?

    /// `footnote` is the dimmest line, at the foot of the card, for context that is worth having but not worth reading first.
    var footnote: Text?

    /// `style` is the resolved appearance to draw in.
    let style: ActivityStyle

    /// `body` draws the message.
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)

            Text(headline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.primaryText)

            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let callToAction {
                Text(callToAction)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(style.accent.opacity(0.12), in: .rect(cornerRadius: 8))
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            if let footnote {
                footnote
                    .font(.system(size: 8.5))
                    .foregroundStyle(style.quaternaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
