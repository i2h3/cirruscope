// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `NextcloudLoginPageTests` covers `NextcloudLoginPage`, which decides whether an address the web view is navigating to is the connected server's sign-in form and, if so, what the request behind it had been for.
///
/// It is pure address arithmetic with no web view involved, which is what makes it testable; what the app then does with the answer belongs to `NextcloudNavigationDecider` and is not covered here.
/// Both directions matter, and for different reasons. Recognizing too little means the user is shown a sign-in form they cannot complete, since signing in happens natively rather than in the page. Recognizing too much is worse: every match cancels a navigation the user asked for and spends the one silent retry that stands between an expired cookie and being signed out of the app, so a file someone named "login" must not be mistaken for the form.
/// The redirect target is the third risk and the sharpest. It comes off the address bar rather than from the server's own routing — any link a page can render may carry it — and whatever it names is where an app password is about to be sent.
///
struct NextcloudLoginPageTests {
    ///
    /// A server installed at the root of its host, which is how most instances are reached.
    ///
    private static let server = URL(string: "https://cloud.example.com")!

    ///
    /// The same server installed below a path, which is what puts a web root in front of every route it answers.
    ///
    private static let subpathServer = URL(string: "https://cloud.example.com/nextcloud")!

    @Test(arguments: [
        "https://cloud.example.com/login",
        "https://cloud.example.com/index.php/login",
        "https://cloud.example.com/login/",
        "https://cloud.example.com/login?redirect_url=/index.php/apps/files/",
    ])
    func `The sign-in form is recognized however the instance spells it`(address: String) throws {
        // Whether "/index.php" appears is per-instance configuration rather than anything the app chooses, and the
        // redirect that reaches the app carries a query, so all of these are the one page.
        let url = try #require(URL(string: address))

        #expect(NextcloudLoginPage.matches(url, on: Self.server))
    }

    @Test
    func `The sign-in form of an instance below a path is recognized at that path`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/index.php/login"))

        #expect(NextcloudLoginPage.matches(url, on: Self.subpathServer))
    }

    @Test
    func `A web root written with a trailing slash still recognizes its own sign-in form`() throws {
        // The canonical address the app stores carries no trailing slash, but one is not a different server either.
        let serverAddress = try #require(URL(string: "https://cloud.example.com/nextcloud/"))
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/login"))

        #expect(NextcloudLoginPage.matches(url, on: serverAddress))
    }

    @Test(arguments: [
        "https://cloud.example.com/login",
        "https://cloud.example.com/nextcloudx/login",
    ])
    func `A sign-in form outside the instance's own web root is not the instance's own`(address: String) throws {
        // The first is a second installation at the host's root, the second a neighbour whose path merely begins
        // with the same letters. Neither is the server this app is connected to.
        let url = try #require(URL(string: address))

        #expect(NextcloudLoginPage.matches(url, on: Self.subpathServer) == false)
    }

    @Test(arguments: [
        "https://cloud.example.com/remote.php/dav/files/iva/login",
        "https://cloud.example.com/other/login",
    ])
    func `An address that merely ends in the word is not the sign-in form`(address: String) throws {
        // A file or folder a user named "login" is reached through a route of its own, so anchoring the match at the
        // web root is what keeps opening it from being cancelled and charged against the silent retry.
        let url = try #require(URL(string: address))

        #expect(NextcloudLoginPage.matches(url, on: Self.server) == false)
    }

    @Test(arguments: [
        "https://cloud.example.com/login/flow",
        "https://cloud.example.com/login/confirm",
    ])
    func `The other pages below the sign-in route are left alone`(address: String) throws {
        // Password confirmation and the Login Flow grant screens are pages the user is meant to see and complete;
        // silently re-requesting what lies behind them would help nobody and would take them off screen.
        let url = try #require(URL(string: address))

        #expect(NextcloudLoginPage.matches(url, on: Self.server) == false)
    }

    @Test(arguments: [
        "http://cloud.example.com/login",
        "https://cloud.example.com:8443/login",
        "https://evil.example/login",
    ])
    func `A sign-in form on another origin is not the connected server's`(address: String) throws {
        // Scheme and port are part of the answer, not just the host: a cleartext listener or another service on the
        // same machine is a different origin, and treating it as the server would aim a retry at it.
        let url = try #require(URL(string: address))

        #expect(NextcloudLoginPage.matches(url, on: Self.server) == false)
    }

    @Test
    func `The redirect target survives the server's own encoding of it`() throws {
        // Nextcloud escapes "&" and "=" inside the parameter but leaves "?" and "/" alone, so the address it hands
        // back contains a second literal question mark and the original query arrives re-assembled.
        let url = try #require(URL(string: "https://cloud.example.com/index.php/login?redirect_url=/index.php/apps/files/?dir%3D/x%26y%3D1"))

        #expect(NextcloudLoginPage.redirectTarget(of: url, on: Self.server)?.absoluteString == "https://cloud.example.com/index.php/apps/files/?dir=/x&y=1")
    }

    @Test
    func `An escape in the original address is not decoded away`() throws {
        // The server escapes what was already escaped, so "%20" reaches the app as "%2520" and has to come back out
        // as "%20" rather than as a space, which would not survive being made into a URL again.
        let url = try #require(URL(string: "https://cloud.example.com/login?redirect_url=/index.php/apps/files/?dir%3D/My%2520Folder"))

        #expect(NextcloudLoginPage.redirectTarget(of: url, on: Self.server)?.absoluteString == "https://cloud.example.com/index.php/apps/files/?dir=/My%20Folder")
    }

    @Test
    func `The redirect target of an instance below a path stays below it`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/nextcloud/index.php/login?redirect_url=/nextcloud/index.php/apps/files/"))

        #expect(NextcloudLoginPage.redirectTarget(of: url, on: Self.subpathServer)?.absoluteString == "https://cloud.example.com/nextcloud/index.php/apps/files/")
    }

    @Test
    func `A sign-in form naming no destination has none`() throws {
        let url = try #require(URL(string: "https://cloud.example.com/login"))

        #expect(NextcloudLoginPage.redirectTarget(of: url, on: Self.server) == nil)
    }

    @Test(arguments: [
        "https://cloud.example.com/login?redirect_url=https%3A%2F%2Fevil.example%2Fx",
        "https://cloud.example.com/login?redirect_url=%2F%2Fevil.example%2Fx",
        "https://cloud.example.com/login?redirect_url=http%3A%2F%2Fcloud.example.com%2Fx",
        "https://cloud.example.com/login?redirect_url=https%3A%2F%2Fcloud.example.com%3A8443%2Fx",
    ])
    func `A destination off the connected server is refused rather than requested`(address: String) throws {
        // This is the parameter's whole risk. It reaches the app straight off the address bar, long before the
        // server's own handling of it would run, and what it names is where an app password would be sent. The last
        // two are the ones a host comparison alone would wave through.
        let url = try #require(URL(string: address))

        #expect(NextcloudLoginPage.redirectTarget(of: url, on: Self.server) == nil)
    }

    @Test
    func `A destination that is the sign-in form again is refused`() throws {
        // Reloading it would be a redirect intercepted into a reload of itself, and the caller has somewhere better
        // to fall back to.
        let url = try #require(URL(string: "https://cloud.example.com/login?redirect_url=%2Findex.php%2Flogin"))

        #expect(NextcloudLoginPage.redirectTarget(of: url, on: Self.server) == nil)
    }
}
