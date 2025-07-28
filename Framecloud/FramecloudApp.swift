import SwiftUI

@main
struct FramecloudApp: App {
    ///
    /// The global state object.
    ///
    let store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(store)
    }
}
