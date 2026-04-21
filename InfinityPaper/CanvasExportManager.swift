//
//  CanvasExportManager.swift
//  InfinityPaper
//
//  Manages PDF and PNG export operations for the canvas.
//

import UIKit
import OSLog

/// Manages export operations for the canvas.
final class CanvasExportManager {
    private let logger = Logger(subsystem: "com.infinitypaper", category: "Export")

    /// Removes characters unsafe for file names; returns a non-empty prefix suitable for export names.
    static func sanitizedExportPrefix(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        let scalars = trimmed.unicodeScalars.filter { !invalid.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
        if cleaned.isEmpty { return "InfinityPaper_" }
        return cleaned
    }
    
    /// Longest edge in **logical** points after `format.scale`; avoids multi‑hundred‑MB bitmaps on huge sessions.
    private static let exportFullMaxPixelSide: CGFloat = 8192

    private enum ExportKeys {
        static let format = "settings.export.format"
        static let resolution = "settings.export.resolution"
        static let margin = "settings.export.margin"
        static let includeNoise = "settings.export.includeNoise"
        static let transparent = "settings.export.transparent"
        static let autoName = "settings.export.autoName"
        static let prefix = "settings.export.prefix"
    }
    
    /// Callback type for drawing strokes during export.
    typealias DrawStrokesCallback = (CGContext) -> Void
    
    /// Callback type for drawing noise during export.
    typealias DrawNoiseCallback = (CGContext, CGRect) -> Void
    
    /// Exports the entire drawing in `worldBounds` (already padded for stroke width by the caller).
    /// For viewport-only export, use `exportVisible`.
    func exportFull(
        worldBounds: CGRect,
        backgroundColor: UIColor,
        drawStrokesWorld: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = UserDefaults.standard
        let formatRaw = defaults.string(forKey: ExportKeys.format) ?? ExportFormat.pdf.rawValue
        let format = ExportFormat(rawValue: formatRaw) ?? .pdf

        if format == .png {
            let resolution = defaults.object(forKey: ExportKeys.resolution) != nil
                ? CGFloat(defaults.double(forKey: ExportKeys.resolution))
                : 2.0
            let includeNoise = defaults.object(forKey: ExportKeys.includeNoise) == nil
                || defaults.bool(forKey: ExportKeys.includeNoise)
            let transparent = defaults.object(forKey: ExportKeys.transparent) != nil
                && defaults.bool(forKey: ExportKeys.transparent)
            exportFullPNG(
                backgroundColor: backgroundColor,
                worldBounds: worldBounds,
                resolution: resolution,
                includeNoise: includeNoise,
                transparent: transparent,
                drawStrokesWorld: drawStrokesWorld,
                presentShare: presentShare,
                showToast: showToast
            )
        } else {
            exportFullPDF(
                backgroundColor: backgroundColor,
                worldBounds: worldBounds,
                drawStrokesWorld: drawStrokesWorld,
                presentShare: presentShare,
                showToast: showToast
            )
        }
    }

    /// Exports the currently visible viewport (honors scroll `contentOffset`). Full-canvas export uses `exportFull`.
    /// - Parameters:
    ///   - bounds: The view bounds (viewport size)
    ///   - contentOffset: The current scroll offset in world space
    ///   - backgroundColor: The background color for export
    ///   - drawStrokes: Callback to draw strokes in the provided context (viewport coordinates)
    ///   - drawNoise: Callback to draw noise in the provided context and rect
    ///   - presentShare: Callback to present the share sheet with the exported file URL
    ///   - showToast: Callback to show toast messages
    func exportVisible(
        bounds: CGRect,
        contentOffset: CGPoint,
        backgroundColor: UIColor,
        drawStrokes: @escaping DrawStrokesCallback,
        drawNoise: @escaping DrawNoiseCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = UserDefaults.standard
        let formatRaw = defaults.string(forKey: ExportKeys.format) ?? ExportFormat.pdf.rawValue
        let format = ExportFormat(rawValue: formatRaw) ?? .pdf

        if format == .png {
            exportVisiblePNG(
                bounds: bounds,
                contentOffset: contentOffset,
                backgroundColor: backgroundColor,
                drawStrokes: drawStrokes,
                drawNoise: drawNoise,
                presentShare: presentShare,
                showToast: showToast
            )
        } else {
            exportVisiblePDF(
                bounds: bounds,
                contentOffset: contentOffset,
                backgroundColor: backgroundColor,
                drawStrokes: drawStrokes,
                presentShare: presentShare,
                showToast: showToast
            )
        }
    }
    
    // MARK: - Private
    
    private func exportVisiblePDF(
        bounds: CGRect,
        contentOffset: CGPoint,
        backgroundColor: UIColor,
        drawStrokes: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = UserDefaults.standard
        let margin = defaults.object(forKey: ExportKeys.margin) != nil
            ? CGFloat(defaults.double(forKey: ExportKeys.margin))
            : 0
        
        let pageBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: bounds.width + 2 * margin,
                height: bounds.height + 2 * margin
            )
        )
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(backgroundColor.cgColor)
            cgContext.fill(pageBounds)
            cgContext.translateBy(x: -contentOffset.x + margin, y: -contentOffset.y + margin)
            drawStrokes(cgContext)
        }
        
        let name = exportFileName(extension: "pdf")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(tempURL)
            showToast("PDF exported", .success)
        } catch {
            logger.error("Export PDF write failed: \(error.localizedDescription)")
            showToast("Export failed", .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    private func exportVisiblePNG(
        bounds: CGRect,
        contentOffset: CGPoint,
        backgroundColor: UIColor,
        drawStrokes: @escaping DrawStrokesCallback,
        drawNoise: @escaping DrawNoiseCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = UserDefaults.standard
        let resolution = defaults.object(forKey: ExportKeys.resolution) != nil
            ? CGFloat(defaults.double(forKey: ExportKeys.resolution))
            : 2.0
        let margin = defaults.object(forKey: ExportKeys.margin) != nil
            ? CGFloat(defaults.double(forKey: ExportKeys.margin))
            : 0
        let includeNoise = defaults.object(forKey: ExportKeys.includeNoise) == nil
            || defaults.bool(forKey: ExportKeys.includeNoise)
        let transparent = defaults.object(forKey: ExportKeys.transparent) != nil
            && defaults.bool(forKey: ExportKeys.transparent)
        
        let contentSize = bounds.size
        let imageSize = CGSize(width: contentSize.width + 2 * margin, height: contentSize.height + 2 * margin)
        let format = UIGraphicsImageRendererFormat()
        format.scale = resolution
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: imageSize)
            if transparent {
                UIColor.clear.setFill()
                UIGraphicsGetCurrentContext()?.fill(rect)
            } else {
                backgroundColor.setFill()
                UIGraphicsGetCurrentContext()?.fill(rect)
            }
            
            if includeNoise && !transparent, let noiseCtx = UIGraphicsGetCurrentContext() {
                noiseCtx.saveGState()
                noiseCtx.translateBy(x: margin, y: margin)
                drawNoise(noiseCtx, CGRect(origin: .zero, size: contentSize))
                noiseCtx.restoreGState()
            }

            if let strokeCtx = UIGraphicsGetCurrentContext() {
                strokeCtx.saveGState()
                strokeCtx.translateBy(x: margin - contentOffset.x, y: margin - contentOffset.y)
                drawStrokes(strokeCtx)
                strokeCtx.restoreGState()
            }
        }
        
        guard let data = image.pngData() else {
            logger.error("Export PNG data failed")
            showToast("Export failed", .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        
        let name = exportFileName(extension: "png")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(tempURL)
            showToast("PNG exported", .success)
        } catch {
            logger.error("Export PNG write failed: \(error.localizedDescription)")
            showToast("Export failed", .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    private func exportFullPDF(
        backgroundColor: UIColor,
        worldBounds: CGRect,
        drawStrokesWorld: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: worldBounds.size))
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(backgroundColor.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: worldBounds.size))
            cgContext.translateBy(x: -worldBounds.origin.x, y: -worldBounds.origin.y)
            drawStrokesWorld(cgContext)
        }
        
        let name = exportFileName(extension: "pdf")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(tempURL)
            showToast("Full PDF exported", .success)
        } catch {
            logger.error("Export full PDF write failed: \(error.localizedDescription)")
            showToast("Export failed", .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    private func exportFullPNG(
        backgroundColor: UIColor,
        worldBounds: CGRect,
        resolution: CGFloat,
        includeNoise: Bool,
        transparent: Bool,
        drawStrokesWorld: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let imageSize = CGSize(width: worldBounds.size.width, height: worldBounds.size.height)
        let format = UIGraphicsImageRendererFormat()
        let longLogical = max(imageSize.width, imageSize.height)
        let effectiveScale: CGFloat
        if longLogical > 0, longLogical * resolution > Self.exportFullMaxPixelSide {
            effectiveScale = max(1, (Self.exportFullMaxPixelSide / longLogical).rounded(.down))
            if effectiveScale + 0.001 < resolution {
                logger.debug("Full PNG export: scale reduced \(resolution) → \(effectiveScale) to cap bitmap size")
            }
        } else {
            effectiveScale = resolution
        }
        format.scale = effectiveScale
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        
        let image = renderer.image { _ in
            let rect = CGRect(origin: .zero, size: imageSize)
            if transparent {
                UIColor.clear.setFill()
                UIGraphicsGetCurrentContext()?.fill(rect)
            } else {
                backgroundColor.setFill()
                UIGraphicsGetCurrentContext()?.fill(rect)
            }
            
            // Skip noise for full export according to instruction

            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.saveGState()
            ctx.translateBy(x: -worldBounds.origin.x, y: -worldBounds.origin.y)
            drawStrokesWorld(ctx)
            ctx.restoreGState()
        }
        
        guard let data = image.pngData() else {
            logger.error("Export full PNG data failed")
            showToast("Export failed", .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        
        let name = exportFileName(extension: "png")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(tempURL)
            showToast("Full PNG exported", .success)
        } catch {
            logger.error("Export full PNG write failed: \(error.localizedDescription)")
            showToast("Export failed", .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    private func exportFileName(extension ext: String) -> String {
        let defaults = UserDefaults.standard
        let autoName = defaults.object(forKey: ExportKeys.autoName) != nil
            ? defaults.bool(forKey: ExportKeys.autoName)
            : true
        let prefix = Self.sanitizedExportPrefix(defaults.string(forKey: ExportKeys.prefix))
        
        if autoName {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            formatter.timeZone = TimeZone.current
            let stamp = formatter.string(from: Date())
            return "\(prefix)\(stamp).\(ext)"
        }
        
        return "InfinityPaper.\(ext)"
    }
}

