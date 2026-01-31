//
//  SessionPersistenceTests.swift
//  InfinityPaperTests
//
//  Unit tests for SessionPersistence and StoredSession encode/decode (production audit).
//  Add this file to the InfinityPaperTests target in Xcode if the target does not exist:
//  File → New → Target → Unit Testing Bundle → InfinityPaperTests.
//

import XCTest
@testable import InfinityPaper

final class SessionPersistenceTests: XCTestCase {

    // MARK: - sessionURL

    func testSessionURL_returnsURLWithCorrectFileName() {
        let url = SessionPersistence.sessionURL()
        XCTAssertEqual(url.lastPathComponent, "session.json")
    }

    func testSessionURL_withCustomFileName_usesFileName() {
        let url = SessionPersistence.sessionURL(fileName: "custom.json")
        XCTAssertEqual(url.lastPathComponent, "custom.json")
    }

    func testSessionURL_fallbackWhenDocumentDirectoryEmpty_usesTemporaryDirectory() {
        // When document directory list is empty, sessionURL falls back to temporaryDirectory
        let emptyManager = EmptyDocumentDirectoryFileManager()
        let url = SessionPersistence.sessionURL(fileManager: emptyManager)
        XCTAssertEqual(url.lastPathComponent, SessionPersistence.sessionFileName)
        XCTAssertTrue(url.path.contains(emptyManager.temporaryDirectory.path))
    }

    // MARK: - Encode / Decode

    func testStoredSession_encodeDecode_roundtrip() throws {
        let session = makeMinimalStoredSession()
        let data = try SessionPersistence.encode(session)
        let decoded = try SessionPersistence.decode(from: data)
        XCTAssertEqual(decoded.segments.count, session.segments.count)
        XCTAssertEqual(decoded.segments[0].id, session.segments[0].id)
        XCTAssertEqual(decoded.segments[0].strokes.count, session.segments[0].strokes.count)
        XCTAssertEqual(decoded.contentOffset.x, session.contentOffset.x)
        XCTAssertEqual(decoded.contentOffset.y, session.contentOffset.y)
        XCTAssertEqual(decoded.savedAt, session.savedAt)
    }

    func testStoredSession_emptySegments_encodeDecode() throws {
        let session = StoredSession(
            segments: [],
            contentOffset: StoredPoint(x: 10, y: 20),
            savedAt: 123.456
        )
        let data = try SessionPersistence.encode(session)
        let decoded = try SessionPersistence.decode(from: data)
        XCTAssertTrue(decoded.segments.isEmpty)
        XCTAssertEqual(decoded.contentOffset.x, 10)
        XCTAssertEqual(decoded.contentOffset.y, 20)
        XCTAssertEqual(decoded.savedAt, 123.456)
    }

    func testStoredSession_decodeInvalidData_throws() {
        let invalidData = Data([0, 1, 2, 3])
        XCTAssertThrowsError(try SessionPersistence.decode(from: invalidData))
    }

    // MARK: - Helpers

    private func makeMinimalStoredSession() -> StoredSession {
        let color = StoredColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let stroke = StoredStroke(
            points: [StoredPoint(x: 0, y: 0), StoredPoint(x: 10, y: 10)],
            times: [0, 0.1],
            color: color,
            lineWidth: 2
        )
        let segment = StoredSegment(id: 0, strokes: [stroke])
        return StoredSession(
            segments: [segment],
            contentOffset: StoredPoint(x: 0, y: 0),
            savedAt: Date().timeIntervalSince1970
        )
    }
}

// MARK: - FileManager stub for fallback test

private final class EmptyDocumentDirectoryFileManager: FileManager {
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        if directory == .documentDirectory {
            return []
        }
        return super.urls(for: directory, in: domainMask)
    }
}
