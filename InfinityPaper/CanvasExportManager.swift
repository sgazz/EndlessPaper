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
    
    /// Exports the visible canvas area.
    /// - Parameters:
    ///   - bounds: The canvas bounds
    ///   - contentOffset: The current scroll offset
    ///   - backgroundColor: The background color for export
    ///   - drawStrokes: Callback to draw strokes in the provided context
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
        
        let pageBounds = bounds
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
            
            if includeNoise && !transparent {
                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                ctx?.translateBy(x: margin, y: margin)
                drawNoise(ctx!, CGRect(origin: .zero, size: contentSize))
                ctx?.restoreGState()
            }
            
            let ctx = UIGraphicsGetCurrentContext()!
            ctx.saveGState()
            ctx.translateBy(x: margin - contentOffset.x, y: margin - contentOffset.y)
            drawStrokes(ctx)
            ctx.restoreGState()
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
    
    private func exportFileName(extension ext: String) -> String {
        let defaults = UserDefaults.standard
        let autoName = defaults.object(forKey: ExportKeys.autoName) != nil
            && defaults.bool(forKey: ExportKeys.autoName)
        let prefix = defaults.string(forKey: ExportKeys.prefix) ?? "InfinityPaper_"
        
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
