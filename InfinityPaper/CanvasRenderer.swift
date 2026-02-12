//
//  CanvasRenderer.swift
//  InfinityPaper
//
//  Provides rendering utilities for drawing strokes and noise texture.
//

import UIKit

/// Stroke structure for rendering.
struct RenderStroke {
    var points: [CGPoint]
    var times: [TimeInterval]
    var color: UIColor
    var lineWidth: CGFloat
}

/// Provides rendering utilities for canvas drawing operations.
final class CanvasRenderer {
    private enum Layout {
        static let strokeSmoothingAlpha: CGFloat = 0.18
        static let noiseTileSize: CGFloat = 96
    }
    
    /// Draws a stroke in view coordinates (applying content offset transform).
    /// - Parameters:
    ///   - stroke: The stroke to draw
    ///   - context: The graphics context
    ///   - contentOffset: The current scroll offset
    static func drawStroke(
        _ stroke: RenderStroke,
        in context: CGContext,
        contentOffset: CGPoint
    ) {
        guard stroke.points.count > 1 else { return }
        context.setStrokeColor(stroke.color.cgColor)
        drawStrokeSegments(
            stroke,
            in: context,
            transform: { point in
                CGPoint(x: point.x - contentOffset.x, y: point.y - contentOffset.y)
            }
        )
    }
    
    /// Draws a stroke in world coordinates (no transform).
    /// - Parameters:
    ///   - stroke: The stroke to draw
    ///   - context: The graphics context
    static func drawStrokeWorld(
        _ stroke: RenderStroke,
        in context: CGContext
    ) {
        guard stroke.points.count > 1 else { return }
        context.setStrokeColor(stroke.color.cgColor)
        drawStrokeSegments(stroke, in: context, transform: { $0 })
    }
    
    /// Draws stroke segments with smoothing, width scaling, and tail effects.
    /// - Parameters:
    ///   - stroke: The stroke to draw
    ///   - context: The graphics context
    ///   - transform: Transform function to apply to points (e.g., view or world coordinates)
    private static func drawStrokeSegments(
        _ stroke: RenderStroke,
        in context: CGContext,
        transform: (CGPoint) -> CGPoint
    ) {
        let smoothed = smoothedPoints(for: stroke.points, passes: 2).map(transform)
        guard smoothed.count > 1 else { return }
        
        let tailCount = min(20, max(0, smoothed.count - 1))
        let tailStart = max(0, smoothed.count - 1 - tailCount)
        let minScale: CGFloat = 0.15
        
        var filteredScale: CGFloat = 1.0
        let smoothingAlpha = Layout.strokeSmoothingAlpha
        for i in 1..<smoothed.count {
            let start = smoothed[i - 1]
            let end = smoothed[i]
            let targetScale = targetWidthScale(for: stroke, index: i)
            filteredScale = filteredScale + (targetScale - filteredScale) * smoothingAlpha
            let width = stroke.lineWidth * filteredScale
            let tailScale: CGFloat
            if i >= tailStart && tailCount > 0 {
                let t = CGFloat(smoothed.count - 1 - i) / CGFloat(tailCount)
                let eased = t * t * (3 - 2 * t)
                tailScale = max(minScale, eased * eased)
            } else {
                tailScale = 1.0
            }
            context.setLineWidth(max(0.4, width * tailScale))
            context.beginPath()
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }
    
    /// Smooths points using a simple averaging filter.
    /// - Parameters:
    ///   - points: The points to smooth
    ///   - passes: Number of smoothing passes
    /// - Returns: Smoothed points
    static func smoothedPoints(for points: [CGPoint], passes: Int) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var current = points
        for _ in 0..<passes {
            var next = current
            for i in 1..<(current.count - 1) {
                let prev = current[i - 1]
                let curr = current[i]
                let nextPoint = current[i + 1]
                next[i] = CGPoint(
                    x: prev.x * 0.25 + curr.x * 0.5 + nextPoint.x * 0.25,
                    y: prev.y * 0.25 + curr.y * 0.5 + nextPoint.y * 0.25
                )
            }
            current = next
        }
        return current
    }
    
    /// Calculates width scale based on drawing speed.
    /// - Parameters:
    ///   - stroke: The stroke
    ///   - index: The point index
    /// - Returns: Width scale factor (0.6 to 1.15)
    private static func targetWidthScale(for stroke: RenderStroke, index: Int) -> CGFloat {
        guard stroke.times.count > index else { return 1.0 }
        let dt = max(0.0001, stroke.times[index] - stroke.times[index - 1])
        let p0 = stroke.points[index - 1]
        let p1 = stroke.points[index]
        let distance = hypot(p1.x - p0.x, p1.y - p0.y)
        let speed = distance / CGFloat(dt)
        let minSpeed: CGFloat = 30
        let maxSpeed: CGFloat = 1200
        let normalized = min(1, max(0, (speed - minSpeed) / (maxSpeed - minSpeed)))
        let thick = 1.15
        let thin = 0.6
        return thick - (thick - thin) * normalized
    }
    
    /// Draws noise texture in the specified rect.
    /// - Parameters:
    ///   - context: The graphics context
    ///   - rect: The rectangle to fill with noise
    ///   - noiseTile: The cached noise tile image (will be created if nil)
    ///   - backgroundColor: Background color for noise generation
    ///   - traitCollection: Trait collection for dark mode detection
    /// - Returns: Updated noise tile (for caching)
    static func drawNoise(
        in context: CGContext,
        rect: CGRect,
        noiseTile: UIImage?,
        backgroundColor: UIColor,
        traitCollection: UITraitCollection
    ) -> UIImage? {
        let tile = noiseTile ?? makeNoiseTile(
            size: Layout.noiseTileSize,
            backgroundColor: backgroundColor,
            traitCollection: traitCollection
        )
        UIColor(patternImage: tile).setFill()
        context.fill(rect)
        return tile
    }
    
    /// Creates a noise tile image.
    /// - Parameters:
    ///   - size: Tile size
    ///   - backgroundColor: Background color
    ///   - traitCollection: Trait collection for dark mode detection
    /// - Returns: Noise tile image
    static func makeNoiseTile(
        size: CGFloat,
        backgroundColor: UIColor,
        traitCollection: UITraitCollection
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let resolvedBg = backgroundColor.resolvedColor(with: traitCollection)
        let isDark = traitCollection.userInterfaceStyle == .dark
        return renderer.image { ctx in
            let base = resolvedBg.withAlphaComponent(0.02)
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            
            for _ in 0..<250 {
                let x = CGFloat.random(in: 0..<size)
                let y = CGFloat.random(in: 0..<size)
                let alpha = CGFloat.random(in: 0.015...0.05)
                // In dark mode, use lighter dots; in light mode, use darker dots
                let dotColor = isDark
                    ? UIColor(white: 1.0, alpha: alpha)
                    : UIColor(white: 0.0, alpha: alpha)
                ctx.cgContext.setFillColor(dotColor.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
            }
        }
    }
}
