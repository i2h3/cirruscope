// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

/// `MediaCaptureDecisionTests` covers `MediaCaptureDecision`, which decides which pages are given the camera and the microphone without a prompt of the web view's own.
///
/// The stakes are asymmetric, so most cases are ones that must not be granted: a plain-HTTP or differently-ported service on the server's own machine, which the host comparison this replaced waved through, and a frame from another origin inside the server's page.
/// The rest pin that the server itself is still recognized however WebKit spells it.
/// That spelling is measured rather than written down here: `SecurityOriginProbe` loads a document at each address in a real `WKWebView`, and the decision is asked about the origin WebKit reports for it.
/// The time limit is what turns a report that never arrives into a failure rather than a run that never ends, and it is generous because a case alone takes seconds but shares the main actor with every other suite: in a full iOS run on a busy machine every case here took forty.
@MainActor
@Suite(.timeLimit(.minutes(5)))
struct MediaCaptureDecisionTests {
    /// `server` is the connected server the cases without a server of their own are judged against.
    private static let server = URL(string: "https://cloud.example.com")!

    /// `decision(page:frame:server:)` is the decision for a request from a document loaded at `page`, from a frame in a document loaded at `frame`, or from the page itself when that is `nil`, in an app connected to `server`.
    private func decision(page: String, frame: String? = nil, server: URL = Self.server) async throws -> MediaCaptureDecision {
        let pageOrigin = try await SecurityOriginProbe.reportedOrigin(ofDocumentAt: #require(URL(string: page)))
        var frameOrigin = pageOrigin

        if let frame {
            frameOrigin = try await SecurityOriginProbe.reportedOrigin(ofDocumentAt: #require(URL(string: frame)))
        }

        return MediaCaptureDecision.forRequest(page: pageOrigin, frame: frameOrigin, connectedTo: server)
    }

    @Test(arguments: [
        ("https://cloud.example.com/apps/spreed/", "https://cloud.example.com"),
        ("https://Cloud.Example.COM/call/abc123", "https://cloud.example.com"),
        ("https://cloud.example.com/", "https://Cloud.Example.com"),
        ("https://cloud.example.com:443/", "https://cloud.example.com"),
        ("https://cloud.example.com/", "https://cloud.example.com:443"),
        ("https://cloud.example.com:8443/", "https://cloud.example.com:8443"),
        ("http://cloud.example.com/", "http://cloud.example.com"),
        ("https://[::1]:8443/", "https://[::1]:8443"),
        ("https://bücher.example/", "https://xn--bcher-kva.example"),
        ("https://cloud.example.com/apps/spreed/", "https://cloud.example.com/nextcloud"),
    ])
    func `A page on the server's origin is granted, however either is spelled`(page: String, server: String) async throws {
        // The server's side is spelled as `ServerAddress` stores it: the case of the host as typed, a port only where
        // one was given, an internationalized name in its ASCII form, and the web root of an instance installed in a
        // subdirectory, which is a path and so no part of an origin.
        let serverAddress = try #require(URL(string: server))

        #expect(try await decision(page: page, server: serverAddress) == .grant)
    }

    @Test(arguments: [
        ("http://cloud.example.com/", "https://cloud.example.com"),
        ("https://cloud.example.com/", "http://cloud.example.com"),
        ("https://cloud.example.com:8443/", "https://cloud.example.com"),
        ("https://cloud.example.com/", "https://cloud.example.com:8443"),
        ("https://talk.cloud.example.com/", "https://cloud.example.com"),
        ("https://cloud.example.com.example.net/", "https://cloud.example.com"),
        ("https://nextcloud.com/", "https://cloud.example.com"),
    ])
    func `A page on another origin is prompted for, including one that merely shares the server's host`(page: String, server: String) async throws {
        // The first four are why this is an origin test: a plain-HTTP listener and a differently-ported service on the
        // server's own machine are other sites, and a rule written on hosts handed both the camera without asking.
        let serverAddress = try #require(URL(string: server))

        #expect(try await decision(page: page, server: serverAddress) == .prompt)
    }

    @Test(arguments: [
        "https://cloud.example.com:8443/",
        "http://cloud.example.com/",
        "https://nextcloud.com/",
    ])
    func `A frame from another origin inside the server's page is prompted for`(frame: String) async throws {
        // A frame is not held to the rule that keeps navigations on the server, so this is the case the navigation rule
        // cannot prevent and only this decision can.
        #expect(try await decision(page: "https://cloud.example.com/apps/spreed/", frame: frame) == .prompt)
    }

    @Test
    func `A frame on the server's origin inside another origin's page is prompted for`() async throws {
        #expect(try await decision(page: "https://nextcloud.com/", frame: "https://cloud.example.com/apps/spreed/") == .prompt)
    }

    @Test
    func `A sandboxed frame inside the server's page is prompted for`() async throws {
        // Measured, not assumed: a sandboxed frame's origin is opaque, and WebKit reports it as an empty scheme and
        // host, which spell no address at all.
        let address = try #require(URL(string: "https://cloud.example.com/apps/spreed/"))
        let page = await SecurityOriginProbe.reportedOrigin(ofDocumentAt: address)
        let frame = await SecurityOriginProbe.reportedOriginOfSandboxedFrame(inDocumentAt: address)

        #expect(frame.scheme.isEmpty)
        #expect(frame.host.isEmpty)
        #expect(MediaCaptureDecision.forRequest(page: page, frame: frame, connectedTo: Self.server) == .prompt)
    }

    @Test
    func `Nothing is granted while no server is connected`() async throws {
        let address = try #require(URL(string: "https://cloud.example.com/apps/spreed/"))
        let origin = await SecurityOriginProbe.reportedOrigin(ofDocumentAt: address)

        #expect(MediaCaptureDecision.forRequest(page: origin, frame: origin, connectedTo: nil) == .prompt)
    }
}
