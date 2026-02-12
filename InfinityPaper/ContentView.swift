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
    private enum Layout {
        static let menuTriggerSize: CGFloat = 132
        static let menuTriggerMargin: CGFloat = 12
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
    private var noiseTile: UIImage?
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
    private var didShowSavedToastThisSession = false
    private var segmentWidth: CGFloat = 1
    private lazy var toastManager: CanvasToastManager = {
        CanvasToastManager(parentView: self, traitCollection: traitCollection)
    }()
    private let exportManager = CanvasExportManager()
    private let sessionManager = CanvasSessionManager()
    private let menuTriggerButton = UIButton(type: .custom)
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
        sessionManager.stopPeriodicSaveTimer()
        // Note: sessionManager handles its own NotificationCenter cleanup in deinit
    }

    override func draw(_ rect: CGRect) {
        guard needsRedraw, let context = UIGraphicsGetCurrentContext() else { return }
        
        // Background (no separate layer so it does not cover our strokes)
        let bgColor = backgroundColorTone.resolvedColor(with: traitCollection)
        context.setFillColor(bgColor.cgColor)
        context.fill(rect)
        
        // Draw noise texture
        noiseTile = CanvasRenderer.drawNoise(
            in: context,
            rect: rect,
            noiseTile: noiseTile,
            backgroundColor: backgroundColorTone,
            traitCollection: traitCollection
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let visibleIds = visibleSegmentIds()
        for id in visibleIds {
            guard let segment = segments[id] else { continue }
            for stroke in segment.strokes {
                CanvasRenderer.drawStroke(
                    toRenderStroke(stroke),
                    in: context,
                    contentOffset: contentOffset
                )
            }
        }

        if let stroke = currentStroke {
            CanvasRenderer.drawStroke(
                toRenderStroke(stroke),
                in: context,
                contentOffset: contentOffset
            )
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

    /// Converts internal Stroke to RenderStroke for rendering.
    private func toRenderStroke(_ stroke: Stroke) -> RenderStroke {
        RenderStroke(
            points: stroke.points,
            times: stroke.times,
            color: stroke.color,
            lineWidth: stroke.lineWidth
        )
    }

    private func toWorldPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x + contentOffset.x, y: viewPoint.y + contentOffset.y)
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
        sessionManager.registerForAppLifecycle(
            saveOnResign: { [weak self] in
                self?.persistSessionIfNeeded()
            },
            resumeOnActive: { [weak self] in
                self?.sessionManager.startPeriodicSaveTimerIfNeeded { [weak self] in
                    self?.saveSession()
                }
            }
        )
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
        
        sessionManager.saveSession(storedSession) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                if !self.didShowSavedToastThisSession {
                    self.didShowSavedToastThisSession = true
                    DispatchQueue.main.async {
                        self.showToast(text: "Saved", type: .success)
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.showToast(text: "Save failed", type: .error)
                }
            }
        }
    }

    func loadSession() {
        sessionManager.loadSession { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let storedSession):
                self.segments = Dictionary(uniqueKeysWithValues: storedSession.segments.map { stored in
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
                self.contentOffset = CGPoint(x: storedSession.contentOffset.x, y: storedSession.contentOffset.y)
                self.undoStack.removeAll()
                self.setNeedsDisplay()
            case .failure:
                // Session load failed - this is expected if no session exists yet
                break
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update background color to adapt to dark mode
        backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)
        
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
        toastManager.updateLayout(in: bounds)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            // Dark mode changed - update colors and redraw
            backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)
            noiseTile = nil // Invalidate noise tile cache to regenerate with new colors
            updateMenuTriggerButtonAppearance()
            toastManager.updateTraitCollection(traitCollection)
            radialMenu.updateColorsForDarkMode(graphiteColor: graphiteColor.resolvedColor(with: traitCollection))
            setNeedsDisplay()
        }
    }

    private func drawStrokesForExport(in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let visibleIds = visibleSegmentIds()
        for id in visibleIds {
            guard let segment = segments[id] else { continue }
            for stroke in segment.strokes {
                CanvasRenderer.drawStrokeWorld(toRenderStroke(stroke), in: context)
            }
        }
        if let stroke = currentStroke {
            CanvasRenderer.drawStrokeWorld(toRenderStroke(stroke), in: context)
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
        exportManager.exportVisible(
            bounds: bounds,
            contentOffset: contentOffset,
            backgroundColor: backgroundColorTone.resolvedColor(with: traitCollection),
            drawStrokes: { [weak self] context in
                self?.drawStrokesForExport(in: context)
            },
            drawNoise: { [weak self] context, rect in
                guard let self = self else { return }
                self.noiseTile = CanvasRenderer.drawNoise(
                    in: context,
                    rect: rect,
                    noiseTile: self.noiseTile,
                    backgroundColor: self.backgroundColorTone,
                    traitCollection: self.traitCollection
                )
            },
            presentShare: { [weak self] url in
                self?.presentShare(url: url)
            },
            showToast: { [weak self] text, type in
                self?.showToast(text: text, type: type)
            }
        )
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
        sessionManager.deleteSession()
        setNeedsDisplay()
    }

    private func showToast(text: String, type: ToastType = .info) {
        toastManager.show(text: text, type: type)
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
        _ = toastManager // Initialize toast manager
        registerForAppLifecycle()
        if sessionManager.shouldAutoloadOnLaunch() {
            loadSession()
        }
        applySavedBrushSettings()
        sessionManager.startPeriodicSaveTimerIfNeeded { [weak self] in
            self?.saveSession()
        }
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
        menuTriggerButton.backgroundColor = .clear
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
