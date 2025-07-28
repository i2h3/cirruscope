import SwiftUI

///
/// A loading screen which covers the whole window.
///
struct ModalActivityView: View {
    private let text: LocalizedStringKey?

    /// 
    /// Initializes the view with a localized text.
    /// 
    /// - Parameter text: The text to display underneath the activity indicator.
    /// 
    init(_ text: LocalizedStringKey? = nil) {
        self.text = text
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            VStack {
                ProgressView()

                if let text {
                    Text(text)
                        .padding(.top)
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ModalActivityView("Preview")
}
