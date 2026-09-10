// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `WebViewDestinationTests` covers `WebViewDestination`, which decides whether an address the embedded web view is navigating to is the web view's to display or the system's to open.
///
/// It is the rule that confines the web view to one server, and the stakes are asymmetric. Answering `webView` for an address that is not the connected server's leaves another site displayed inside the app's own window, carrying the account's session and borrowing the trust of the app's chrome. Answering `system` for one that is the server's, or for one only a document can make sense of, throws the user out of the app mid-task or hands the operating system something meaningless.
/// Half the cases below are therefore addresses that must *not* move: the server's own pages however they are spelled, and the schemes a document uses on itself. The other half are the ones a host comparison alone would wave through, which is what the two apps used to do.
///
struct WebViewDestinationTests {
    ///
    /// The connected server every case below is judged against.
    ///
    private static let server = URL(string: "https://cloud.example.com")!

    @Test(arguments: [
        "https://cloud.example.com",
        "https://cloud.example.com/apps/files/",
        "https://cloud.example.com/index.php/apps/spreed/",
        "https://cloud.example.com/apps/files/?dir=/Photos#top",
    ])
    func `The connected server's own pages stay in the web view`(address: String) throws {
        let url = try #require(URL(string: address))

        #expect(WebViewDestination.of(url, connectedTo: Self.server) == .webView)
    }

    @Test(arguments: [
        "about:blank",
        "data:text/html,<p>hi</p>",
        "blob:https://cloud.example.com/2b8f",
        "javascript:void(0)",
        "file:///etc/passwd",
    ])
    func `A scheme only a document can make sense of stays with WebKit`(address: String) throws {
        // None of these addresses anything another application could act on, and `file:` is one a remote page has no
        // business sending anyone to at all. Offering any of them to the system would be meaningless at best.
        let url = try #require(URL(string: address))

        #expect(WebViewDestination.of(url, connectedTo: Self.server) == .webView)
    }

    @Test(arguments: [
        "https://nextcloud.com/",
        "http://cloud.example.com/apps/files/",
        "https://cloud.example.com:8443/apps/files/",
    ])
    func `Another origin goes to the system, including one that merely shares the host`(address: String) throws {
        // The last two are the whole reason this is an origin test rather than a host test: a plain-HTTP listener and
        // a differently-ported service on the server's own machine are different sites, and a rule written on hosts
        // would display both inside the app with the account's session attached.
        let url = try #require(URL(string: address))

        #expect(WebViewDestination.of(url, connectedTo: Self.server) == .system)
    }

    @Test(arguments: [
        "mailto:someone@example.com",
        "tel:+441632960960",
        "sms:+441632960960",
        "facetime:someone@example.com",
        "maps://?q=Berlin",
    ])
    func `An address for another application goes to the system`(address: String) throws {
        // These are what the rule exists to let through. Whether the machine can actually open one is a question
        // about the machine, asked by each app of its own platform, and not decided here.
        let url = try #require(URL(string: address))

        #expect(WebViewDestination.of(url, connectedTo: Self.server) == .system)
    }

    @Test
    func `An address below a subpath install is the server's, and one beside it is not`() throws {
        let serverAddress = try #require(URL(string: "https://cloud.example.com/nextcloud"))
        let inside = try #require(URL(string: "https://cloud.example.com/nextcloud/apps/files/"))
        let alongside = try #require(URL(string: "https://cloud.example.com/something-else/"))

        // Origin is the whole test, so a neighbour on the same origin stays in the web view too. It is not the
        // instance, but it is not somewhere the account's session can leak to either.
        #expect(WebViewDestination.of(inside, connectedTo: serverAddress) == .webView)
        #expect(WebViewDestination.of(alongside, connectedTo: serverAddress) == .webView)
    }
}
