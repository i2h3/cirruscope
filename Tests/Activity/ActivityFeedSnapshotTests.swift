// SPDX-FileCopyrightText: 2026 Iva Horn
// SPDX-License-Identifier: MIT

@testable import Cirruscope
import Foundation
import Testing

///
/// `ActivityFeedSnapshotTests` pins how `ActivityFeedStore.Snapshot` decodes, the saved feed being the one thing the widget carries from one refresh to the next.
///
/// A snapshot that no longer decodes is treated as absent, which costs the widget its stale state, so a change to its shape has to keep decoding the snapshots an earlier build wrote. The server address is such a change: a snapshot from before it was recorded must still decode, its rows intact and its address `nil`, so that the rows draw their monograms rather than vanish.
/// The cases encode and decode in memory and never touch the App Group container `ActivityFeedStore` writes to.
///
struct ActivityFeedSnapshotTests {
    /// `row` is one activity of the shape a fetch produces, named so that whose avatar it is can be told apart.
    private static let row = ActivityRow(id: 7, verb: .changed, fileName: "Q3 Roadmap.md", directory: "Documents/Planning", actorID: "estelle", actorName: "Estelle", additionalCount: 0, date: Date(timeIntervalSince1970: 1_790_000_000))

    ///
    /// A snapshot saved now carries the server its rows came from back out, which is what the stale state's avatars look their photographs up under.
    ///
    @Test
    func `A snapshot keeps the server its rows came from`() throws {
        let snapshot = ActivityFeedStore.Snapshot(rows: [Self.row], fetchedAt: Date(timeIntervalSince1970: 1_790_000_100), serverAddress: URL(string: "https://cloud.example.com"))

        let decoded = try JSONDecoder().decode(ActivityFeedStore.Snapshot.self, from: JSONEncoder().encode(snapshot))

        #expect(decoded.rows == [Self.row])
        #expect(decoded.serverAddress == URL(string: "https://cloud.example.com"))
    }

    ///
    /// A snapshot written before the server address was recorded has no such key at all, and has to decode with its rows rather than be thrown away.
    ///
    @Test
    func `A snapshot saved before the server address was recorded still decodes`() throws {
        let snapshot = ActivityFeedStore.Snapshot(rows: [Self.row], fetchedAt: Date(timeIntervalSince1970: 1_790_000_100), serverAddress: URL(string: "https://cloud.example.com"))

        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "serverAddress")

        let decoded = try JSONDecoder().decode(ActivityFeedStore.Snapshot.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.rows == [Self.row])
        #expect(decoded.serverAddress == nil)
    }
}
