import NextcloudKit
import SwiftNextcloudUI
import SwiftUI

///
/// Root view in every window.
///
struct ContentView: View {
    @Environment(Store.self) private var store

    ///
    /// The login status polling task.
    ///
    @State var poller: Task<Void, any Error>?

    var body: some View {
        ZStack {
            if store.account != nil {
                NextcloudView(store: store)
            } else {
                ServerAddressView(backgroundColor: .constant(Color.accent), brandImage: Image(systemName: "cloud.fill"), sharedAccounts: []) { host, user, password in
                    store.addAccount(host: host, user: user, password: password)
                } beginPolling: { url, dismiss in
                    let (_, serverInfoResult) = await NextcloudKit.shared.getServerStatusAsync(serverUrl: url.absoluteString)

                    switch serverInfoResult {
                        case .success:
                            let loginOptions = NKRequestOptions()
                            let (endpoint, loginAddress, token) = try await NextcloudKit.shared.getLoginFlowV2(serverUrl: url.absoluteString, options: loginOptions)
                            let options = NKRequestOptions()
                            var grantValues: (url: String, user: String, appPassword: String)?

                            poller = Task {
                                repeat {
                                    grantValues = await getResponse(endpoint: endpoint, token: token, options: options)
                                    try await Task.sleep(for: .seconds(1))
                                } while grantValues == nil

                                guard let grantValues else {
                                    return
                                }

                                guard let host = URL(string: grantValues.url) else {
                                    return
                                }

                                store.addAccount(host: host, user: grantValues.user, password: grantValues.appPassword)
                                dismiss()
                            }

                            return loginAddress
                        case .failure(let nKError):
                            throw nKError.error
                    }
                } cancelPolling: { _ in
                    guard let poller else {
                        return
                    }

                    poller.cancel()
                    self.poller = nil
                }
            }

            // This needs to cover up the web view until it has finished the logout navigation.
            if store.isLoggingOut {
                ModalActivityView("Logging  out...")
            }
        }
    }

    private func getResponse(endpoint: URL, token: String, options: NKRequestOptions) async -> (url: String, user: String, appPassword: String)? {

        return await withCheckedContinuation { continuation in
            NextcloudKit.shared.getLoginFlowV2Poll(token: token, endpoint: endpoint.absoluteString, options: options) { server, loginName, appPassword, _, error in
                if error == .success, let urlBase = server, let user = loginName, let appPassword {
                    continuation.resume(returning: (urlBase, user, appPassword))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

}

#Preview {
    ContentView()
}
