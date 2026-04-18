//
//  CanvasToolbarPlacement.swift
//  InfinityPaper
//
//  Dock edges, snapped centers, and hint padding for the floating drawing toolbar.
//

import SwiftUI

/// User-chosen dock for the drawing toolbar (persisted as raw string).
enum CanvasToolbarDock: String, CaseIterable, Identifiable, Sendable {
    case top
    case bottom
    case leading
    case trailing

    var id: String { rawValue }

    /// Leading/trailing docks use a vertical control column; top/bottom use a horizontal strip.
    var usesVerticalToolbarLayout: Bool {
        self == .leading || self == .trailing
    }

    /// Center of the toolbar when docked to this edge (`toolbarSize` should match current horizontal vs vertical layout).
    func dockedCenter(
        toolbarSize: CGSize,
        containerSize: CGSize,
        safeArea: EdgeInsets,
        margin: CGFloat
    ) -> CGPoint {
        let w = toolbarSize.width
        let h = toolbarSize.height
        let midX = containerSize.width / 2
        let midY = containerSize.height / 2

        switch self {
        case .top:
            return CGPoint(x: midX, y: safeArea.top + margin + h / 2)
        case .bottom:
            return CGPoint(
                x: midX,
                y: containerSize.height - safeArea.bottom - margin - h / 2
            )
        case .leading:
            return CGPoint(
                x: safeArea.leading + margin + w / 2,
                y: midY
            )
        case .trailing:
            return CGPoint(
                x: containerSize.width - safeArea.trailing - margin - w / 2,
                y: midY
            )
        }
    }

    /// Extra safe padding so first-use hint does not sit under the docked toolbar.
    func hintContentPadding(toolbarReserve: CGFloat) -> EdgeInsets {
        switch self {
        case .top:
            return EdgeInsets(top: toolbarReserve, leading: 0, bottom: 0, trailing: 0)
        case .bottom:
            return EdgeInsets(top: 0, leading: 0, bottom: toolbarReserve, trailing: 0)
        case .leading:
            return EdgeInsets(top: 0, leading: toolbarReserve, bottom: 0, trailing: 0)
        case .trailing:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: toolbarReserve)
        }
    }

    /// Popover arrow for color/width pickers: opens toward the canvas, away from the dock edge.
    var popoverArrowEdge: Edge {
        switch self {
        case .top: return .bottom
        case .bottom: return .top
        case .leading: return .trailing
        case .trailing: return .leading
        }
    }

    static func nearestDock(
        finalCenter: CGPoint,
        toolbarSize: CGSize,
        containerSize: CGSize,
        safeArea: EdgeInsets,
        margin: CGFloat
    ) -> CanvasToolbarDock {
        var best: CanvasToolbarDock = .top
        var bestDist = CGFloat.infinity
        for candidate in CanvasToolbarDock.allCases {
            let c = candidate.dockedCenter(
                toolbarSize: toolbarSize,
                containerSize: containerSize,
                safeArea: safeArea,
                margin: margin
            )
            let d = hypot(finalCenter.x - c.x, finalCenter.y - c.y)
            if d < bestDist {
                bestDist = d
                best = candidate
            }
        }
        return best
    }
}
