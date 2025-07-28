import SwiftUI
import Foundation

@main
struct FramecloudApp: App {
    ///
    /// The global state object.
    ///
    let store = Store()

    ///
    /// The value for the user agent header to use in web requests.
    ///
    static let userAgent: String = {
        let appName = Bundle.main.infoDictionary!["CFBundleName"]! as! String
        let appVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! String
        
        // Create a Safari-like user agent with WebKit identification
        #if os(macOS)
        let platform = "Macintosh; Intel Mac OS X 10_15_7"
        #elseif os(iOS)
        let platform = "iPhone; CPU iPhone OS 17_0 like Mac OS X"
        #else
        let platform = "Unknown"
        #endif
        
        return "Mozilla/5.0 (\(platform)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15 \(appName)/\(appVersion)"
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(store)
    }
}
