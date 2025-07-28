import SwiftUI

@main
struct FramecloudApp: App {
    ///
    /// The global state object.
    ///
    let store = Store()

    ///
    /// The value for the user agent header to use in web requests.
    ///
    static let userAgent = "\(Bundle.main.infoDictionary!["CFBundleName"]!)/\(Bundle.main.infoDictionary!["CFBundleShortVersionString"]!)"

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(store)
    }
}
