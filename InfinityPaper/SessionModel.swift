//
//  SessionModel.swift
//  InfinityPaper
//
//  Session types and persistence for production audit (testable, no UIKit).
//

import Foundation

// MARK: - Codable session types (no UIKit dependency)

struct StoredSession: Codable {
    var segments: [StoredSegment]
    var contentOffset: StoredPoint
    var savedAt: TimeInterval
}

struct StoredSegment: Codable {
    var id: Int
    var strokes: [StoredStroke]
}

struct StoredStroke: Codable {
    var points: [StoredPoint]
    var times: [TimeInterval]?
    var color: StoredColor
    var lineWidth: CGFloat
}

struct StoredPoint: Codable {
    var x: CGFloat
    var y: CGFloat
}

struct StoredColor: Codable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
}

// MARK: - Session persistence (sessionURL fallback + encode/decode)

enum SessionPersistence {
    static let sessionFileName = "session.json"

    /// Returns document directory URL, or temporary directory if document directory is unavailable.
    static func sessionURL(fileName: String = sessionFileName, fileManager: FileManager = .default) -> URL {
        let directories = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let directory = directories.first ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent(fileName)
    }

    static func encode(_ session: StoredSession) throws -> Data {
        try JSONEncoder().encode(session)
    }

    static func decode(from data: Data) throws -> StoredSession {
        try JSONDecoder().decode(StoredSession.self, from: data)
    }
}
