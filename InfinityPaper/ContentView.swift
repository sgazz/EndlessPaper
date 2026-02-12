//
//  ContentView.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import os
import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            TapeCanvasView()
            .ignoresSafeArea()
        }
    }
}

private struct TapeCanvasView: View {
    @State private var showAbout = false
    @State private var canvasView: TapeCanvasUIView?
    /// Fallback palette so Settings always shows colors even if canvas isn’t ready yet.
    private static let defaultPalette: [UIColor] = [
        UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9),
        UIColor(red: 0.12, green: 0.9, blue: 0.98, alpha: 0.95),
        UIColor(red: 1.0, green: 0.35, blue: 0.78, alpha: 0.95),
        UIColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 0.95),
        UIColor(red: 0.98, green: 0.42, blue: 0.12, alpha: 0.95),
        UIColor(red: 0.22, green: 1.0, blue: 0.85, alpha: 0.95)
    ]

    var body: some View {
        ZStack {
            TapeCanvasRepresentable(
                onRequestSettings: { DispatchQueue.main.async { showAbout = true } },
                onCanvasReady: { view in DispatchQueue.main.async { canvasView = view } }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAbout) {
            AboutView(onDismiss: { showAbout = false })
        }
    }
}

/// About screen (zen-friendly; replaces visible Settings entry).
private struct AboutView: View {
    var onDismiss: () -> Void

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build != nil ? "\(short) (\(build!))" : short
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Infinity Paper")
                .font(.title.weight(.medium))
            Text("Endless drawing canvas")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Hero&Peace© 2026")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
            Button("Done", action: onDismiss)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TapeCanvasRepresentable: UIViewRepresentable {
    var onRequestSettings: () -> Void
    var onCanvasReady: (TapeCanvasUIView) -> Void

    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView()
        // Background color will be set by the view's backgroundColorTone property
        view.onRequestSettings = onRequestSettings
        onCanvasReady(view)
        return view
    }

    func updateUIView(_ uiView: TapeCanvasUIView, context: Context) {
        uiView.onRequestSettings = onRequestSettings
    }
}

private final class TapeCanvasUIView: UIView {
    /// Centralized design tokens for consistent UI styling across the app.
    private enum DesignTokens {
        // Corner radius
        static let cornerRadiusSmall: CGFloat = 8
        static let cornerRadiusMedium: CGFloat = 10
        static let cornerRadiusLarge: CGFloat = 12
        static let cornerRadiusRound: CGFloat = 80 // For radial menu
        
        // Shadows
        static let shadowOpacityLight: Float = 0.1
        static let shadowOpacityMedium: Float = 0.25
        static let shadowRadiusSmall: CGFloat = 2
        static let shadowRadiusMedium: CGFloat = 10
        static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
        
        // Animations
        static let animationDurationFast: TimeInterval = 0.15
        static let animationDurationMedium: TimeInterval = 0.2
        static let animationDurationSlow: TimeInterval = 0.3
        static let springDamping: CGFloat = 0.72
        static let springVelocity: CGFloat = 0.6
        
        /// Applies standard shadow styling to a view layer.
        static func applyShadow(to layer: CALayer, opacity: Float = shadowOpacityLight, radius: CGFloat = shadowRadiusMedium) {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = opacity
            layer.shadowRadius = radius
            layer.shadowOffset = shadowOffset
        }
    }

    private enum Layout {
        static let menuTriggerSize: CGFloat = 132
        static let menuTriggerMargin: CGFloat = 12
        static let toastBottomOffset: CGFloat = 96
        static let toastWidthMax: CGFloat = 220
        static let toastHorizontalMargin: CGFloat = 32
        static let noiseTileSize: CGFloat = 96
        static let toastVisibleDuration: TimeInterval = 1.2
        static let strokeSmoothingAlpha: CGFloat = 0.18
    }

    private enum Defaults {
        static let baseLineWidth: CGFloat = 2.2
    }

    private struct Stroke {
        var points: [CGPoint]
        var times: [TimeInterval]
        var color: UIColor
        var lineWidth: CGFloat
    }

    private struct Segment {
        var id: Int
        var strokes: [Stroke]
    }

    private var segments: [Int: Segment] = [:]
    private var currentStroke: Stroke?
    private var currentStrokeSegmentId: Int?
    /// Stack of (segmentId, strokeIndex) for completed strokes; used for Undo (Sparkles).
    private var undoStack: [(segmentId: Int, strokeIndex: Int)] = []
    private var contentOffset: CGPoint = .zero
    private var displayLink: CADisplayLink?
    private var autoScrollLink: CADisplayLink?
    private var lastTouchLocation: CGPoint?
    private let autoScrollSpeed: CGFloat = 90
    private var decelVelocity: CGFloat = 0
    private let decelRate: CGFloat = 0.92
    private let velocityStopThreshold: CGFloat = 4
    /// Adaptive background color that responds to system dark mode.
    private var backgroundColorTone: UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                // Dark mode: dark gray background
                UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1.0)
            } else {
                // Light mode: light beige background
                UIColor(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0)
            }
        }
    }
    private var baseStrokeColor: UIColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
    /// Adaptive graphite color for UI elements (lighter in dark mode for visibility).
    private var graphiteColor: UIColor {
        UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                // Dark mode: lighter gray for visibility
                UIColor(white: 0.85, alpha: 0.9)
            } else {
                // Light mode: dark graphite
                UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
            }
        }
    }
    private var baseLineWidth: CGFloat = Defaults.baseLineWidth
    private var isEraser: Bool = false
    private var noiseTile: UIImage?
    /// Background layer for static background (performance optimization).
    private lazy var backgroundLayer: CALayer = {
        let layer = CALayer()
        layer.zPosition = -1000
        return layer
    }()
    /// Flag to track if redraw is needed (performance optimization).
    private var needsRedraw: Bool = true
    private let primaryColorPalette: [UIColor] = [
        UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9),   // graphite
        UIColor(red: 0.12, green: 0.9, blue: 0.98, alpha: 0.95),   // neon cyan 2
        UIColor(red: 1.0, green: 0.35, blue: 0.78, alpha: 0.95),   // neon pink
        UIColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 0.95),   // neon violet
        UIColor(red: 0.98, green: 0.42, blue: 0.12, alpha: 0.95),  // neon orange
        UIColor(red: 0.22, green: 1.0, blue: 0.85, alpha: 0.95)    // neon mint
    ]
    private let achievementColorPalette: [UIColor] = [
        UIColor(red: 0.65, green: 0.77, blue: 0.95, alpha: 0.95),  // pastel blue
        UIColor(red: 0.96, green: 0.73, blue: 0.82, alpha: 0.95),  // pastel pink
        UIColor(red: 0.96, green: 0.85, blue: 0.66, alpha: 0.95),  // pastel peach
        UIColor(red: 0.73, green: 0.9, blue: 0.77, alpha: 0.95),   // pastel mint
        UIColor(red: 0.84, green: 0.78, blue: 0.93, alpha: 0.95),  // pastel lavender
        UIColor(red: 0.88, green: 0.92, blue: 0.98, alpha: 0.95)   // pastel ice
    ]
    private var lastPaletteIndex: Int?
    private var telemetry = Telemetry()
    private let sessionLogger = Logger(subsystem: "InfinityPaper", category: "Session")
    private enum SessionKeys {
        static let autosaveMode = "settings.session.autosaveMode"
        static let autoloadOnLaunch = "settings.session.autoload"
    }

    private enum ExportKeys {
        static let format = "settings.export.format"
        static let resolution = "settings.export.resolution"
        static let margin = "settings.export.margin"
        static let includeNoise = "settings.export.includeNoise"
        static let transparent = "settings.export.transparent"
        static let autoName = "settings.export.autoName"
        static let prefix = "settings.export.prefix"
    }
    private static let periodicSaveInterval: TimeInterval = 60
    private var periodicSaveTimer: Timer?
    private var didShowSavedToastThisSession = false
    private var segmentWidth: CGFloat = 1
    private let toastLabel = UILabel()
    private var toastTimer: Timer?
    private let menuTriggerButton = UIButton(type: .custom)

    /// Toast message types with distinct visual styles.
    private enum ToastType {
        case success
        case error
        case warning
        case info

        var backgroundColor: UIColor {
            UIColor { traitCollection in
                let isDark = traitCollection.userInterfaceStyle == .dark
                switch self {
                case .success:
                    return isDark
                        ? UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.95)
                        : UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 0.95)
                case .error:
                    return isDark
                        ? UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.95)
                        : UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.95)
                case .warning:
                    return isDark
                        ? UIColor(red: 0.95, green: 0.65, blue: 0.1, alpha: 0.95)
                        : UIColor(red: 0.95, green: 0.65, blue: 0.1, alpha: 0.95)
                case .info:
                    return isDark
                        ? UIColor(white: 0.2, alpha: 0.95)
                        : UIColor(white: 0.95, alpha: 0.95)
                }
            }
        }

        var textColor: UIColor {
            UIColor.white.withAlphaComponent(0.95)
        }
    }
    private let menuTriggerKeyX = "menuTrigger.center.x"
    private let menuTriggerKeyY = "menuTrigger.center.y"
    private lazy var radialMenu = RadialMenuController(
        host: self,
        graphiteColor: graphiteColor,
        colorSubPalette: primaryColorPalette,
        setBaseStrokeColor: { [weak self] color in self?.baseStrokeColor = color },
        cycleLineWidth: { [weak self] in self?.cycleLineWidth() },
        onClearLastSession: { [weak self] in self?.confirmAndClearSession() },
        onExport: { [weak self] in self?.exportVisible() },
        onSettings: { [weak self] in self?.onRequestSettings?() ?? self?.showToast(text: "Settings", type: .info) },
        onSparkles: { [weak self] in self?.handleSparklesTap() },
        onPaletteIndexChanged: { [weak self] index in
            self?.applyPalette(index: index)
        }
    )
    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        return recognizer
    }()
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()
    private lazy var menuTriggerPan: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handleMenuTriggerPan(_:)))
    }()

    /// Set by the SwiftUI representable when the user taps the About (info) button in the radial menu.
    var onRequestSettings: (() -> Void)?

    /// Exposed for Settings: current brush color.
    var exposedBaseStrokeColor: UIColor { baseStrokeColor }
    /// Exposed for Settings: current line width.
    var exposedBaseLineWidth: CGFloat { baseLineWidth }
    /// Exposed for Settings: primary palette, or primary + achievement palette after the bounce Easter egg has been unlocked.
    var exposedPrimaryPalette: [UIColor] {
        radialMenu.isAchievementPaletteUnlocked
            ? primaryColorPalette + achievementColorPalette
            : primaryColorPalette
    }

    /// Called from Settings: set brush color.
    func setBaseStrokeColorFromSettings(_ color: UIColor) { baseStrokeColor = color }
    /// Called from Settings: set line width.
    func setBaseLineWidthFromSettings(_ width: CGFloat) { baseLineWidth = width }
    /// Called from Settings: show clear confirmation, then clear and toast.
    func confirmAndClearSessionFromSettings() { confirmAndClearSession() }
    /// Called from Settings: load the last saved session.
    func loadSessionFromSettings() { loadSession(); setNeedsDisplay() }
    /// Called from Settings: reset trigger button and radial menu position to default (top‑left area).
    func resetRadialMenuPositionFromSettings() {
        let defaultCenter = CGPoint(
            x: safeAreaInsets.left + Layout.menuTriggerMargin + Layout.menuTriggerSize / 2,
            y: safeAreaInsets.top + Layout.menuTriggerMargin + Layout.menuTriggerSize / 2
        )
        let clamped = clampMenuTrigger(point: defaultCenter)
        menuTriggerButton.center = clamped
        saveMenuTriggerPosition()
        radialMenu.setMenuCenterAndSave(clamped)
        setNeedsLayout()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureCommon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCommon()
    }

    deinit {
        stopPeriodicSaveTimer()
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ rect: CGRect) {
        guard needsRedraw, let context = UIGraphicsGetCurrentContext() else { return }
        
        // Draw noise texture on top of background layer
        drawNoise(in: context, rect: rect)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let visibleIds = visibleSegmentIds()
        for id in visibleIds {
            guard let segment = segments[id] else { continue }
            for stroke in segment.strokes {
                drawStroke(stroke, in: context)
            }
        }

        if let stroke = currentStroke {
            drawStroke(stroke, in: context)
        }
        
        needsRedraw = false
    }
    
    override func setNeedsDisplay() {
        needsRedraw = true
        super.setNeedsDisplay()
    }
    
    override func setNeedsDisplay(_ rect: CGRect) {
        needsRedraw = true
        super.setNeedsDisplay(rect)
    }

    private func drawStroke(_ stroke: Stroke, in context: CGContext) {
        guard stroke.points.count > 1 else { return }
        context.setStrokeColor(stroke.color.cgColor)
        drawStrokeSegments(stroke, in: context, transform: toViewPoint(_:))
    }

    private func drawStrokeWorld(_ stroke: Stroke, in context: CGContext) {
        guard stroke.points.count > 1 else { return }
        context.setStrokeColor(stroke.color.cgColor)
        drawStrokeSegments(stroke, in: context, transform: { $0 })
    }

    private func drawStrokeSegments(
        _ stroke: Stroke,
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

    private func smoothedPoints(for points: [CGPoint], passes: Int) -> [CGPoint] {
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

    private func targetWidthScale(for stroke: Stroke, index: Int) -> CGFloat {
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

    private func toWorldPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x + contentOffset.x, y: viewPoint.y + contentOffset.y)
    }

    private func toViewPoint(_ worldPoint: CGPoint) -> CGPoint {
        CGPoint(x: worldPoint.x - contentOffset.x, y: worldPoint.y - contentOffset.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        if radialMenu.isMenuVisible { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        stopDeceleration()
        let location = touch.location(in: self)
        lastTouchLocation = location
        let color = baseStrokeColor
        currentStroke = Stroke(
            points: [toWorldPoint(location)],
            times: [touch.timestamp],
            color: color,
            lineWidth: baseLineWidth
        )
        currentStrokeSegmentId = segmentId(forWorldX: toWorldPoint(location).x)
        startAutoScrollIfNeeded()
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        let location = touch.location(in: self)
        lastTouchLocation = location
        currentStroke?.points.append(toWorldPoint(location))
        currentStroke?.times.append(touch.timestamp)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let stroke = currentStroke, let segmentId = currentStrokeSegmentId else { return }
        var segment = segments[segmentId] ?? Segment(id: segmentId, strokes: [])
        segment.strokes.append(stroke)
        segments[segmentId] = segment
        undoStack.append((segmentId, segment.strokes.count - 1))
        telemetry.recordStroke(points: stroke.points.count)
        currentStroke = nil
        currentStrokeSegmentId = nil
        lastTouchLocation = nil
        stopAutoScroll()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentStroke = nil
        currentStrokeSegmentId = nil
        lastTouchLocation = nil
        stopAutoScroll()
        setNeedsDisplay()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopDeceleration()
        case .changed:
            let translation = recognizer.translation(in: self)
            contentOffset.x -= translation.x
            telemetry.recordPan(deltaX: translation.x)
            recognizer.setTranslation(.zero, in: self)
            updateSegmentsIfNeeded()
            setNeedsDisplay()
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self)
            decelVelocity = velocity.x
            startDeceleration()
        default:
            break
        }
    }

    private func startDeceleration() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDeceleration))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDeceleration() {
        displayLink?.invalidate()
        displayLink = nil
        decelVelocity = 0
    }

    @objc private func handleDeceleration() {
        guard displayLink != nil else { return }
        let dt = CGFloat(displayLink?.duration ?? 1.0 / 60.0)
        if abs(decelVelocity) < velocityStopThreshold {
            stopDeceleration()
            return
        }
        contentOffset.x -= decelVelocity * dt
        telemetry.recordPan(deltaX: decelVelocity * dt)
        decelVelocity *= pow(decelRate, dt * 60)
        updateSegmentsIfNeeded()
        setNeedsDisplay()
    }

    private func startAutoScrollIfNeeded() {
        guard autoScrollLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleAutoScroll))
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
    }

    @objc private func handleAutoScroll() {
        guard let lastTouchLocation, currentStroke != nil else {
            stopAutoScroll()
            return
        }
        let dt = CGFloat(autoScrollLink?.duration ?? 1.0 / 60.0)
        contentOffset.x += autoScrollSpeed * dt
        let worldPoint = toWorldPoint(lastTouchLocation)
        currentStroke?.points.append(worldPoint)
        currentStroke?.times.append(CACurrentMediaTime())
        updateSegmentsIfNeeded()
        setNeedsDisplay()
    }

    private func registerForAppLifecycle() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func shouldAutoloadOnLaunch() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SessionKeys.autoloadOnLaunch) != nil else { return true }
        return defaults.bool(forKey: SessionKeys.autoloadOnLaunch)
    }

    private func currentAutosaveMode() -> AutosaveMode {
        let raw = UserDefaults.standard.string(forKey: SessionKeys.autosaveMode) ?? AutosaveMode.onBackground.rawValue
        return AutosaveMode(rawValue: raw) ?? .onBackground
    }

    private func startPeriodicSaveTimerIfNeeded() {
        stopPeriodicSaveTimer()
        guard currentAutosaveMode() == .periodic else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.periodicSaveInterval, repeats: true) { [weak self] _ in
            self?.saveSession()
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicSaveTimer = timer
    }

    private func stopPeriodicSaveTimer() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
    }

    @objc private func appWillResignActive() {
        persistSessionIfNeeded()
        stopPeriodicSaveTimer()
    }

    @objc private func appDidBecomeActive() {
        startPeriodicSaveTimerIfNeeded()
    }

    func persistSessionIfNeeded() {
        saveSession()
    }

    private func saveSession() {
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
        let storedSession = StoredSession(
            segments: storedSegments,
            contentOffset: StoredPoint(x: contentOffset.x, y: contentOffset.y),
            savedAt: Date().timeIntervalSince1970
        )
        do {
            let data = try SessionPersistence.encode(storedSession)
            try data.write(to: SessionPersistence.sessionURL(), options: Data.WritingOptions.atomic)
            if !didShowSavedToastThisSession {
                didShowSavedToastThisSession = true
                DispatchQueue.main.async { [weak self] in
                    self?.showToast(text: "Saved", type: .success)
                }
            }
        } catch {
            let errorMessage = "Session save failed: \(error.localizedDescription)"
            sessionLogger.error("Session save failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.showToast(text: "Save failed", type: .error)
            }
        }
    }

    func loadSession() {
        do {
            let data = try Data(contentsOf: SessionPersistence.sessionURL())
            let storedSession = try SessionPersistence.decode(from: data)
            segments = Dictionary(uniqueKeysWithValues: storedSession.segments.map { stored in
                let strokes = stored.strokes.map { stroke in
                    Stroke(
                        points: stroke.points.map { CGPoint(x: $0.x, y: $0.y) },
                        times: stroke.times ?? [],
                        color: stroke.color.toUIColor(),
                        lineWidth: stroke.lineWidth
                    )
                }
                return (stored.id, Segment(id: stored.id, strokes: strokes))
            })
            contentOffset = CGPoint(x: storedSession.contentOffset.x, y: storedSession.contentOffset.y)
            undoStack.removeAll()
            setNeedsDisplay()
        } catch {
            sessionLogger.debug("Session load skipped or failed: \(error.localizedDescription)")
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update background color to adapt to dark mode
        backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)
        
        // Setup background layer for performance (static background)
        if backgroundLayer.superlayer == nil {
            layer.insertSublayer(backgroundLayer, at: 0)
        }
        backgroundLayer.frame = bounds
        backgroundLayer.backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection).cgColor
        
        segmentWidth = max(1, bounds.width * 1.5)
        updateSegmentsIfNeeded()
        radialMenu.layout(in: bounds)
        let defaultCenter = CGPoint(
            x: safeAreaInsets.left + Layout.menuTriggerMargin + Layout.menuTriggerSize / 2,
            y: safeAreaInsets.top + Layout.menuTriggerMargin + Layout.menuTriggerSize / 2
        )
        menuTriggerButton.frame.size = CGSize(width: Layout.menuTriggerSize, height: Layout.menuTriggerSize)
        menuTriggerButton.center = clampMenuTrigger(point: loadMenuTriggerPosition() ?? defaultCenter)
        menuTriggerButton.layer.cornerRadius = menuTriggerButton.bounds.width / 2
        updateMenuTriggerButtonAppearance()
        let toastWidth = min(bounds.width - Layout.toastHorizontalMargin, Layout.toastWidthMax)
        toastLabel.frame = CGRect(
            x: (bounds.width - toastWidth) / 2,
            y: bounds.height - Layout.toastBottomOffset,
            width: toastWidth,
            height: 36
        )
        updateToastAppearance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            // Dark mode changed - update colors and redraw
            backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)
            backgroundLayer.backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection).cgColor
            noiseTile = nil // Invalidate noise tile cache to regenerate with new colors
            updateMenuTriggerButtonAppearance()
            updateToastAppearance()
            radialMenu.updateColorsForDarkMode(graphiteColor: graphiteColor.resolvedColor(with: traitCollection))
            setNeedsDisplay()
        }
    }

    private func drawNoise(in context: CGContext, rect: CGRect) {
        if noiseTile == nil {
            noiseTile = makeNoiseTile(size: Layout.noiseTileSize)
        }
        guard let noiseTile else { return }
        UIColor(patternImage: noiseTile).setFill()
        context.fill(rect)
    }

    private func drawStrokesForExport(in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let visibleIds = visibleSegmentIds()
        for id in visibleIds {
            guard let segment = segments[id] else { continue }
            for stroke in segment.strokes {
                drawStrokeWorld(stroke, in: context)
            }
        }
        if let stroke = currentStroke {
            drawStrokeWorld(stroke, in: context)
        }
    }

    private func makeNoiseTile(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let resolvedBg = backgroundColorTone.resolvedColor(with: traitCollection)
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

    private func segmentId(forWorldX worldX: CGFloat) -> Int {
        guard segmentWidth > 0 else { return 0 }
        return Int(floor(worldX / segmentWidth))
    }

    private func visibleSegmentIds() -> [Int] {
        guard segmentWidth > 0 else { return [] }
        let minX = contentOffset.x
        let maxX = contentOffset.x + bounds.width
        let startId = segmentId(forWorldX: minX) - 1
        let endId = segmentId(forWorldX: maxX) + 1
        return Array(startId...endId)
    }

    private func updateSegmentsIfNeeded() {
        guard segmentWidth > 0 else { return }
        let visibleIds = Set(visibleSegmentIds())
        for id in visibleIds {
            if segments[id] == nil {
                segments[id] = Segment(id: id, strokes: [])
            }
        }
        let keepIds = Set(visibleIds.union([segmentId(forWorldX: contentOffset.x)]))
        let pruneIds = segments.keys.filter { !keepIds.contains($0) }
        for id in pruneIds {
            segments.removeValue(forKey: id)
        }
    }


    func showMenuAtCenter() {
        menuTriggerButton.isHidden = true
        radialMenu.showMenu(at: menuTriggerButton.center)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        radialMenu.handleTap(at: location)
        if !radialMenu.isMenuVisible {
            menuTriggerButton.isHidden = false
        }
    }

    @objc private func handleSparklesTap() {
        undoLastStroke()
    }

    /// Removes the most recently completed stroke (Undo). No-op if nothing to undo.
    private func undoLastStroke() {
        guard let last = undoStack.popLast() else { return }
        guard var segment = segments[last.segmentId],
              last.strokeIndex < segment.strokes.count else { return }
        segment.strokes.remove(at: last.strokeIndex)
        if segment.strokes.isEmpty {
            segments.removeValue(forKey: last.segmentId)
        } else {
            segments[last.segmentId] = segment
        }
        setNeedsDisplay()
        showToast(text: "Undo", type: .warning)
    }

    private func exportVisible() {
        let defaults = UserDefaults.standard
        let formatRaw = defaults.string(forKey: ExportKeys.format) ?? ExportFormat.pdf.rawValue
        let format = ExportFormat(rawValue: formatRaw) ?? .pdf
        if format == .png {
            exportVisiblePNG()
        } else {
            exportVisiblePDF()
        }
    }

    private func exportFileName(extension ext: String) -> String {
        let defaults = UserDefaults.standard
        let autoName = defaults.object(forKey: ExportKeys.autoName) != nil && defaults.bool(forKey: ExportKeys.autoName)
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

    private func exportVisiblePDF() {
        let defaults = UserDefaults.standard
        let margin = defaults.object(forKey: ExportKeys.margin) != nil ? CGFloat(defaults.double(forKey: ExportKeys.margin)) : 0
        let pageBounds = bounds
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(backgroundColorTone.cgColor)
            cgContext.fill(pageBounds)
            cgContext.translateBy(x: -contentOffset.x + margin, y: -contentOffset.y + margin)
            drawStrokesForExport(in: cgContext)
        }

        let name = exportFileName(extension: "pdf")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(url: tempURL)
            showToast(text: "PDF exported", type: .success)
        } catch {
            let errorMessage = "Failed to export PDF: \(error.localizedDescription)"
            sessionLogger.error("Export PDF write failed: \(error.localizedDescription)")
            showToast(text: "Export failed", type: .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func exportVisiblePNG() {
        let defaults = UserDefaults.standard
        let resolution = defaults.object(forKey: ExportKeys.resolution) != nil ? CGFloat(defaults.double(forKey: ExportKeys.resolution)) : 2.0
        let margin = defaults.object(forKey: ExportKeys.margin) != nil ? CGFloat(defaults.double(forKey: ExportKeys.margin)) : 0
        let includeNoise = defaults.object(forKey: ExportKeys.includeNoise) == nil || defaults.bool(forKey: ExportKeys.includeNoise)
        let transparent = defaults.object(forKey: ExportKeys.transparent) != nil && defaults.bool(forKey: ExportKeys.transparent)

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
                backgroundColorTone.setFill()
                UIGraphicsGetCurrentContext()?.fill(rect)
            }
            if includeNoise && !transparent {
                let ctx = UIGraphicsGetCurrentContext()
                ctx?.saveGState()
                ctx?.translateBy(x: margin, y: margin)
                drawNoise(in: ctx!, rect: CGRect(origin: .zero, size: contentSize))
                ctx?.restoreGState()
            }
            let ctx = UIGraphicsGetCurrentContext()!
            ctx.saveGState()
            ctx.translateBy(x: margin - contentOffset.x, y: margin - contentOffset.y)
            drawStrokesForExport(in: ctx)
            ctx.restoreGState()
        }

        guard let data = image.pngData() else {
            let errorMessage = "Failed to generate PNG data"
            sessionLogger.error("Export PNG data failed")
            showToast(text: "Export failed", type: .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let name = exportFileName(extension: "png")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(url: tempURL)
            showToast(text: "PNG exported", type: .success)
        } catch {
            let errorMessage = "Failed to export PNG: \(error.localizedDescription)"
            sessionLogger.error("Export PNG write failed: \(error.localizedDescription)")
            showToast(text: "Export failed", type: .error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func presentShare(url: URL) {
        guard let controller = findViewController() else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = self
        let menuCenter = radialMenu.menuCenter
        activity.popoverPresentationController?.sourceRect = CGRect(x: menuCenter.x, y: menuCenter.y, width: 1, height: 1)
        controller.present(activity, animated: true)
    }

    func confirmAndClearSession() {
        guard let controller = findViewController() else { return }
        let alert = UIAlertController(
            title: "Clear drawing?",
            message: "This will remove all strokes in current session. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.clearLastDrawingSession()
            self?.showToast(text: "Session cleared", type: .warning)
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        controller.present(alert, animated: true)
    }

    private func clearLastDrawingSession() {
        // Clear all segments and current stroke; reset telemetry, undo stack, and redraw.
        segments.removeAll()
        currentStroke = nil
        currentStrokeSegmentId = nil
        undoStack.removeAll()
        telemetry = Telemetry()
        didShowSavedToastThisSession = false
        try? FileManager.default.removeItem(at: SessionPersistence.sessionURL())
        setNeedsDisplay()
    }

    private func configureToast() {
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.layer.cornerRadius = DesignTokens.cornerRadiusMedium
        toastLabel.layer.masksToBounds = true
        toastLabel.alpha = 0
        updateToastAppearance()
        addSubview(toastLabel)
    }

    private func updateToastAppearance(for type: ToastType? = nil) {
        let toastType = type ?? .info
        toastLabel.textColor = toastType.textColor
        toastLabel.backgroundColor = toastType.backgroundColor.resolvedColor(with: traitCollection)
    }

    private func showToast(text: String, type: ToastType = .info) {
        toastTimer?.invalidate()
        toastLabel.text = text
        updateToastAppearance(for: type)
        bringSubviewToFront(toastLabel)
        
        // Animate based on type: error/warning get slight scale animation
        let animationDuration: TimeInterval = 0.15
        let scale: CGFloat = (type == .error || type == .warning) ? 1.05 : 1.0
        
        toastLabel.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        toastLabel.alpha = 0
        
        UIView.animate(withDuration: DesignTokens.animationDurationFast, delay: 0, options: [.curveEaseOut]) {
            self.toastLabel.alpha = 1
            self.toastLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
        } completion: { _ in
            UIView.animate(withDuration: DesignTokens.animationDurationFast * 0.67) {
                self.toastLabel.transform = .identity
            }
        }
        
        toastTimer = Timer.scheduledTimer(withTimeInterval: Layout.toastVisibleDuration, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: DesignTokens.animationDurationMedium) {
                self?.toastLabel.alpha = 0
                self?.toastLabel.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            }
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                return vc
            }
            responder = next
        }
        return nil
    }

    private enum SettingsKeys {
        static let baseColorIndex = "settings.baseColorIndex"
        static let baseLineWidth = "settings.baseLineWidth"
    }

    private func configureCommon() {
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(tapRecognizer)
        configureMenuTriggerButton()
        _ = radialMenu
        radialMenu.syncPaletteIndex()
        configureToast()
        registerForAppLifecycle()
        if shouldAutoloadOnLaunch() {
            loadSession()
        }
        applySavedBrushSettings()
        startPeriodicSaveTimerIfNeeded()
    }

    /// Applies brush color and line width from UserDefaults (set in Settings) so they persist across launches.
    private func applySavedBrushSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKeys.baseColorIndex) != nil {
            let idx = defaults.integer(forKey: SettingsKeys.baseColorIndex)
            if idx < primaryColorPalette.count {
                baseStrokeColor = primaryColorPalette[idx]
            } else if radialMenu.isAchievementPaletteUnlocked,
                      (idx - primaryColorPalette.count) < achievementColorPalette.count {
                baseStrokeColor = achievementColorPalette[idx - primaryColorPalette.count]
            } else {
                let safeIdx = min(max(0, idx), primaryColorPalette.count - 1)
                baseStrokeColor = primaryColorPalette[safeIdx]
            }
        }
        if defaults.object(forKey: SettingsKeys.baseLineWidth) != nil {
            baseLineWidth = CGFloat(defaults.double(forKey: SettingsKeys.baseLineWidth))
        }
    }

    private func cycleLineWidth() {
        switch baseLineWidth {
        case ..<3:
            baseLineWidth = 4.2
        case ..<5:
            baseLineWidth = 6.2
        default:
            baseLineWidth = Defaults.baseLineWidth
        }
    }

    private func applyPalette(index: Int) {
        let palette = index == 0 ? primaryColorPalette : achievementColorPalette
        radialMenu.updateColorPalette(palette)
        if let lastPaletteIndex, lastPaletteIndex != index {
            let message = index == 0 ? "Original colors restored" : "New colors unlocked"
            showToast(text: message, type: .success)
        }
        lastPaletteIndex = index
    }

    private func clampMenuTrigger(point: CGPoint) -> CGPoint {
        let size = Layout.menuTriggerSize
        let half = size / 2
        let minX = safeAreaInsets.left + half + 8
        let maxX = bounds.width - safeAreaInsets.right - half - 8
        let minY = safeAreaInsets.top + half + 8
        let maxY = bounds.height - safeAreaInsets.bottom - half - 8
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    private func loadMenuTriggerPosition() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: menuTriggerKeyX) != nil,
              defaults.object(forKey: menuTriggerKeyY) != nil else { return nil }
        let x = defaults.double(forKey: menuTriggerKeyX)
        let y = defaults.double(forKey: menuTriggerKeyY)
        return CGPoint(x: x, y: y)
    }

    private func saveMenuTriggerPosition() {
        let defaults = UserDefaults.standard
        defaults.set(menuTriggerButton.center.x, forKey: menuTriggerKeyX)
        defaults.set(menuTriggerButton.center.y, forKey: menuTriggerKeyY)
    }

    // MARK: - Accessibility (Canvas)

    override var isAccessibilityElement: Bool {
        get { true }
        // This view represents the interactive drawing canvas; ignore external setters.
        set { }
    }

    override var accessibilityLabel: String? {
        get { "Infinity Paper canvas" }
        set { }
    }

    override var accessibilityHint: String? {
        get {
            "Two-finger pan to move the tape. Double-tap the Infinity button to open the radial menu for tools."
        }
        set { }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [.allowsDirectInteraction, .updatesFrequently] }
        set { }
    }

    private func configureMenuTriggerButton() {
        menuTriggerButton.layer.cornerRadius = menuTriggerButton.bounds.width / 2
        menuTriggerButton.layer.shadowColor = nil
        menuTriggerButton.layer.shadowOpacity = 0
        menuTriggerButton.layer.shadowRadius = 0
        menuTriggerButton.layer.shadowOffset = .zero
        menuTriggerButton.layer.masksToBounds = true
        if let image = UIImage(named: "InfinityPaper") {
            menuTriggerButton.setImage(image, for: .normal)
            menuTriggerButton.imageView?.contentMode = .scaleAspectFit
        } else {
            menuTriggerButton.setTitle("∞", for: .normal)
            menuTriggerButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .largeTitle)
            menuTriggerButton.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        menuTriggerButton.accessibilityLabel = "Open radial menu"
        menuTriggerButton.accessibilityHint = "Double-tap to open the radial menu. Drag to move the button."
        menuTriggerButton.accessibilityTraits.insert(.button)
        menuTriggerButton.addAction(UIAction { [weak self] _ in
            self?.showMenuAtCenter()
        }, for: .touchUpInside)
        menuTriggerButton.addGestureRecognizer(menuTriggerPan)
        menuTriggerButton.isUserInteractionEnabled = true
        updateMenuTriggerButtonAppearance()
        addSubview(menuTriggerButton)
    }

    private func updateMenuTriggerButtonAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        menuTriggerButton.backgroundColor = isDark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.white.withAlphaComponent(0.08)
        if menuTriggerButton.title(for: .normal) != nil {
            menuTriggerButton.setTitleColor(
                isDark ? UIColor.white.withAlphaComponent(0.9) : UIColor.black.withAlphaComponent(0.8),
                for: .normal
            )
        }
    }

    @objc private func handleMenuTriggerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        let current = menuTriggerButton.center
        let next = CGPoint(x: current.x + translation.x, y: current.y + translation.y)
        menuTriggerButton.center = clampMenuTrigger(point: next)
        recognizer.setTranslation(.zero, in: self)
        if recognizer.state == .ended || recognizer.state == .cancelled {
            saveMenuTriggerPosition()
        }
    }
}

private struct Telemetry {
    private(set) var strokeCount: Int = 0
    private(set) var pointCount: Int = 0
    private(set) var panDistance: CGFloat = 0

    mutating func recordStroke(points: Int) {
        strokeCount += 1
        pointCount += points
    }

    mutating func recordPan(deltaX: CGFloat) {
        panDistance += abs(deltaX)
    }
}

private extension UIColor {
    func toStoredColor() -> StoredColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return StoredColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension StoredColor {
    func toUIColor() -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
