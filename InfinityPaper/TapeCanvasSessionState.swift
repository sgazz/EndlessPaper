//
//  TapeCanvasSessionState.swift
//  InfinityPaper
//
//  Segment-backed drawing storage, undo/redo bookkeeping, and spatial indexing
//  for the infinite tape canvas. Extracted from the main canvas view for clarity.
//

import UIKit

// MARK: - Models

struct TapeSessionStroke {
    var points: [CGPoint]
    var times: [TimeInterval]
    var color: UIColor
    var lineWidth: CGFloat
}

struct TapeSessionSegment {
    var id: Int
    var strokes: [TapeSessionStroke]
}

// MARK: - Session state

/// Owns persisted stroke data per horizontal segment, plus undo/redo stacks.
final class TapeCanvasSessionState {
    /// Bumped on every change that should eventually hit disk; avoids clearing the dirty flag if content changed mid-save.
    private(set) var persistenceToken: UInt64 = 0
    /// Whether there are changes not yet reflected in a successful save completion.
    private(set) var hasUnsavedChanges: Bool = false
    /// Redo holds full stroke copies; cap avoids unbounded memory after many undos without a new stroke.
    private static let maxRedoPayloadEntries = 256

    /// Source of truth for completed strokes (keyed by segment column index).
    var segments: [Int: TapeSessionSegment] = [:]
    /// Stack of (segmentId, strokeIndex) for completed strokes; used for Undo.
    var undoStack: [(segmentId: Int, strokeIndex: Int)] = []
    /// Full stroke payloads for redo.
    var redoPayloadStack: [(segmentId: Int, strokeIndex: Int, stroke: TapeSessionStroke)] = []

    func clear() {
        segments.removeAll()
        undoStack.removeAll()
        redoPayloadStack.removeAll()
        persistenceToken = 0
        hasUnsavedChanges = false
    }

    private func noteMutationForPersistence() {
        persistenceToken &+= 1
        hasUnsavedChanges = true
    }

    /// Call after a successful save when no newer mutations occurred since `tokenSnapshot`.
    func acknowledgePersistenceSave(succeededWithToken tokenSnapshot: UInt64) {
        guard tokenSnapshot == persistenceToken else { return }
        hasUnsavedChanges = false
    }

    func segmentId(forWorldX worldX: CGFloat, segmentWidth: CGFloat) -> Int {
        guard segmentWidth > 0 else { return 0 }
        return Int(floor(worldX / segmentWidth))
    }

    func visibleSegmentIds(contentOffset: CGPoint, boundsWidth: CGFloat, segmentWidth: CGFloat) -> [Int] {
        guard segmentWidth > 0 else { return [] }
        let minX = contentOffset.x
        let maxX = contentOffset.x + boundsWidth
        let startId = segmentId(forWorldX: minX, segmentWidth: segmentWidth) - 1
        let endId = segmentId(forWorldX: maxX, segmentWidth: segmentWidth) + 1
        return Array(startId...endId)
    }

    /// Ensures empty segment shells exist for visible columns; drops only **empty** segments far off-screen.
    /// Never removes segments that contain strokes — those are real drawing data.
    func updateSegmentsIfNeeded(contentOffset: CGPoint, boundsWidth: CGFloat, segmentWidth: CGFloat) {
        guard segmentWidth > 0 else { return }
        let visibleIds = Set(visibleSegmentIds(contentOffset: contentOffset, boundsWidth: boundsWidth, segmentWidth: segmentWidth))
        for id in visibleIds {
            if segments[id] == nil {
                segments[id] = TapeSessionSegment(id: id, strokes: [])
            }
        }
        let keepIds = visibleIds.union([segmentId(forWorldX: contentOffset.x, segmentWidth: segmentWidth)])
        let pruneCandidates = segments.keys.filter { !keepIds.contains($0) }
        for id in pruneCandidates {
            if segments[id]?.strokes.isEmpty == true {
                segments.removeValue(forKey: id)
            }
        }
    }

    /// Axis-aligned bounds of all points; `nil` if nothing to draw.
    func rawWorldBoundingRect(currentStroke: TapeSessionStroke?) -> CGRect? {
        var minX: CGFloat = .infinity, minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity, maxY: CGFloat = -.infinity
        for segment in segments.values {
            for stroke in segment.strokes {
                for p in stroke.points {
                    minX = min(minX, p.x)
                    minY = min(minY, p.y)
                    maxX = max(maxX, p.x)
                    maxY = max(maxY, p.y)
                }
            }
        }
        if let stroke = currentStroke {
            for p in stroke.points {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite, maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    /// Expands bounds so caps, joins, and variable-width tails are not clipped on export.
    func worldBoundingRectForExport(currentStroke: TapeSessionStroke?) -> CGRect? {
        guard var rect = rawWorldBoundingRect(currentStroke: currentStroke) else { return nil }
        var maxLineWidth: CGFloat = 1
        for segment in segments.values {
            for stroke in segment.strokes {
                maxLineWidth = max(maxLineWidth, stroke.lineWidth)
            }
        }
        if let stroke = currentStroke {
            maxLineWidth = max(maxLineWidth, stroke.lineWidth)
        }
        // Renderer varies width up to ~1.15× and uses round caps; pad conservatively.
        let pad = maxLineWidth * 0.75 + 3
        rect = rect.insetBy(dx: -pad, dy: -pad)
        return rect
    }

    func buildStoredSession(contentOffset: CGPoint, savedAt: TimeInterval) -> StoredSession {
        let storedSegments = segments.values.map { segment in
            StoredSegment(
                id: segment.id,
                strokes: segment.strokes.map { stroke in
                    StoredStroke(
                        points: stroke.points.map { StoredPoint(x: $0.x, y: $0.y) },
                        times: stroke.times,
                        color: stroke.color.toStoredColor(),
                        lineWidth: stroke.lineWidth
                    )
                }
            )
        }
        return StoredSession(
            segments: storedSegments,
            contentOffset: StoredPoint(x: contentOffset.x, y: contentOffset.y),
            savedAt: savedAt
        )
    }

    func applyStoredSession(_ storedSession: StoredSession) {
        segments = Dictionary(uniqueKeysWithValues: storedSession.segments.map { stored in
            let strokes = stored.strokes.map { stroke in
                TapeSessionStroke(
                    points: stroke.points.map { CGPoint(x: $0.x, y: $0.y) },
                    times: stroke.times ?? [],
                    color: stroke.color.toUIColor(),
                    lineWidth: stroke.lineWidth
                )
            }
            return (stored.id, TapeSessionSegment(id: stored.id, strokes: strokes))
        })
        undoStack.removeAll()
        redoPayloadStack.removeAll()
        persistenceToken = 0
        hasUnsavedChanges = false
    }

    func commitCompletedStroke(segmentId: Int, stroke: TapeSessionStroke) {
        var segment = segments[segmentId] ?? TapeSessionSegment(id: segmentId, strokes: [])
        segment.strokes.append(stroke)
        segments[segmentId] = segment
        undoStack.append((segmentId, segment.strokes.count - 1))
        redoPayloadStack.removeAll()
        noteMutationForPersistence()
    }

    @discardableResult
    func undoLastStroke() -> Bool {
        guard let last = undoStack.popLast() else { return false }
        guard var segment = segments[last.segmentId], last.strokeIndex < segment.strokes.count else { return false }
        let removed = segment.strokes.remove(at: last.strokeIndex)
        if segment.strokes.isEmpty {
            segments.removeValue(forKey: last.segmentId)
        } else {
            segments[last.segmentId] = segment
        }
        redoPayloadStack.append((segmentId: last.segmentId, strokeIndex: last.strokeIndex, stroke: removed))
        while redoPayloadStack.count > Self.maxRedoPayloadEntries {
            redoPayloadStack.removeFirst()
        }
        noteMutationForPersistence()
        return true
    }

    @discardableResult
    func redoLastStroke() -> Bool {
        guard let item = redoPayloadStack.popLast() else { return false }
        var segment = segments[item.segmentId] ?? TapeSessionSegment(id: item.segmentId, strokes: [])
        let index = min(item.strokeIndex, segment.strokes.count)
        segment.strokes.insert(item.stroke, at: index)
        segments[item.segmentId] = segment
        undoStack.append((segmentId: item.segmentId, strokeIndex: index))
        noteMutationForPersistence()
        return true
    }
}

// MARK: - Color bridging (session persistence)

extension UIColor {
    func toStoredColor() -> StoredColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return StoredColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension StoredColor {
    func toUIColor() -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
