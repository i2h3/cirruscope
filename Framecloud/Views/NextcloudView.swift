import SwiftUI
import WebKit

///
/// A WebView wrapper which encapsulates initial page load and manages a ModalActivityView overlay depending on what is going on.
///
struct NextcloudView: View {
    private let events: any AsyncSequence<WebPage.NavigationEvent, any Error>
    private let store: Store

    @State private var initialNavigation = true
    @State private var page: WebPage

    init(store: Store) {
        self.store = store

        let scriptLocation = Bundle.main.url(forResource: "Framecloud", withExtension: "js")!
        let scriptContent = try! String(contentsOf: scriptLocation, encoding: .utf8)

        let userScript = WKUserScript(source: scriptContent, injectionTime: .atDocumentEnd, forMainFrameOnly: false)

        let userContentController = WKUserContentController()
        userContentController.addUserScript(userScript)

        userContentController.add(ScriptMessageHandler(), name: "framecloud")

        var configuration = WebPage.Configuration()
        configuration.userContentController =  userContentController

        let page = WebPage(configuration: configuration)
        page.isInspectable = true
        self.page = page
        self.events = page.navigations
    }

    var body: some View {
        ZStack {
            WebView(page)
                .webViewMagnificationGestures(.disabled)

            if initialNavigation {
                ModalActivityView("Loading...")
            }
        }
        .onAppear {
            loadInitialRequest()
            startObservingLogout()
        }
    }

    ///
    /// Load the initial web page to display.
    ///
    func loadInitialRequest() {
        if let request = store.makeInitialRequest() {
            let events = page.load(request)

            Task {
                for try await event in events {
                    switch event {
                        case .finished:
                            finishInitialNavigation()
                        default:
                            break
                    }
                }
            }
        }
    }

    ///
    /// Check for navigation events related to the logout.
    ///
    func startObservingLogout() {
        Task {
            for try await event in events {
                guard let url = page.url else {
                    continue
                }

                print("Observed navigation event \(event) with URL \(url.absoluteString)")

                switch event {
                    case .startedProvisionalNavigation:
                        guard url.path.hasSuffix("/logout") else {
                            continue
                        }

                        store.beginLogout()

                    case .finished:
                        guard store.isLoggingOut else {
                            continue
                        }

                        store.finishLogout()
                    default:
                        break
                }
            }
        }
    }

    func finishInitialNavigation() {
        guard initialNavigation else {
            return
        }

        initialNavigation = false
    }
}
