import XCTest
@testable import GridFixCore

/// Shared verbatim with Android's TakInteropFixturesTest. Expectations come
/// from the peer implementation, rather than our own XML encoder.
final class TAKInteropFixturesTests: XCTestCase {
    private struct Manifest: Decodable {
        let ownUid: String
        let now: String
        let coordinateTolerance: Double
        let cases: [String: Expected]
    }
    private struct Expected: Decodable {
        let kind: String
        let uid: String?
        let callsign: String?
        let affiliation: String?
        let contact: Bool?
        let creator: String?
        let points: [[Double]]?
        let closed: Bool?
        let staleAt: String?
        let target: String?
    }
    private func resource(_ name: String, ext: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext)))
    }
    private func date(_ text: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: text) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: text))
    }
    func testSharedAndroidGoldenEventsDirectAndFragmentedStream() throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: resource("expected", ext: "json"))
        let now = try date(manifest.now)
        XCTAssertEqual(manifest.cases.count, 14, "Review new peer fixtures explicitly")
        for (file, expected) in manifest.cases.sorted(by: { $0.key < $1.key }) {
            let data = try resource(String(file.dropLast(4)), ext: "xml")
            let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
            let parsed = TAKCoT.parse(xml, ownUID: manifest.ownUid, now: now)
            switch expected.kind {
            case "item":
                guard case let .item(item) = parsed else { XCTFail("Missing item: \(file)"); continue }
                XCTAssertEqual(item.id, expected.uid, file)
                XCTAssertEqual(item.callsign, expected.callsign, file)
                XCTAssertEqual(item.affiliation, expected.affiliation, file)
                XCTAssertEqual(item.isContact, expected.contact, file)
                XCTAssertEqual(item.creator, expected.creator, file)
                XCTAssertEqual(item.closed, expected.closed, file)
                let points = try XCTUnwrap(expected.points)
                XCTAssertEqual(item.points.count, points.count, file)
                for (actual, point) in zip(item.points, points) {
                    XCTAssertEqual(actual.lat, point[0], accuracy: manifest.coordinateTolerance, file)
                    XCTAssertEqual(actual.lon, point[1], accuracy: manifest.coordinateTolerance, file)
                }
                // Android's manifest represents milliseconds; iOS may preserve
                // more of a seven-digit fraction, which remains wire-compatible.
                XCTAssertEqual(Int64((item.staleAt.timeIntervalSince1970 * 1000).rounded(.down)),
                               Int64((try date(XCTUnwrap(expected.staleAt)).timeIntervalSince1970 * 1000).rounded(.down)), file)
            case "delete": XCTAssertEqual(parsed, .delete(try XCTUnwrap(expected.target)), file)
            case "ignored":
                if file == "android-presence.xml" { XCTAssertNil(parsed, file) }
                else { XCTAssertEqual(parsed, .other, file) }
            case "refused": XCTAssertNil(parsed, file)
            default: XCTFail("Unknown shared expectation: \(expected.kind)")
            }
            // One-byte reads also exercise declarations and the split É byte.
            var stream = TAKCoTStream()
            if expected.kind == "refused" {
                XCTAssertThrowsError(try data.forEach { _ = try stream.feed(Data([$0])) }, file)
            } else {
                var frames: [String] = []
                for byte in data { frames += try stream.feed(Data([byte])) }
                XCTAssertEqual(frames.count, 1, file)
                if let frame = frames.first {
                    XCTAssertEqual(TAKCoT.parse(frame, ownUID: manifest.ownUid, now: now), parsed, file)
                }
            }
        }
    }
    func testConcatenatedSharedDeclarationsAndUnicodeRetainEventOrder() throws {
        let files = ["android-position", "ios-style-marker", "android-line", "android-delete"]
        let events = try files.map { try resource($0, ext: "xml") }
        var stream = TAKCoTStream()
        let frames = try stream.feed(events.reduce(into: Data()) { $0.append($1) })
        XCTAssertEqual(frames.count, files.count)
        let now = try date("2026-10-25T15:30:00Z")
        for (frame, original) in zip(frames, events) {
            XCTAssertEqual(TAKCoT.parse(frame, ownUID: "MGRSGPS-OWN-TEST", now: now),
                           TAKCoT.parse(try XCTUnwrap(String(data: original, encoding: .utf8)),
                                        ownUID: "MGRSGPS-OWN-TEST", now: now))
        }
    }
}
