//
//  ContentView.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

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
    @AppStorage("firstUseOrientationDismissed") private var firstUseOrientationDismissed = false
    @State private var orientationHintOpacity: Double = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            TapeCanvasRepresentable(
                onRequestSettings: { DispatchQueue.main.async { showAbout = true } },
                onCanvasReady: { _ in }
            )
            .ignoresSafeArea()

            if !firstUseOrientationDismissed {
                VStack(spacing: 10) {
                    Text(NSLocalizedString("first_use.lead", comment: "First session one-line hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("first_use.body", comment: "First session second line"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button(NSLocalizedString("first_use.dismiss", comment: "Dismiss first-use hint")) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            orientationHintOpacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                            firstUseOrientationDismissed = true
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .opacity(orientationHintOpacity)
                .allowsHitTesting(true)
                .transition(.opacity)
            }
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
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(NSLocalizedString("app.name", comment: "App name"))
                .font(.title.weight(.medium))
            Text(NSLocalizedString("app.tagline", comment: "Tagline"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Text(NSLocalizedString("about.purpose", comment: "About emotional positioning"))
                .font(.footnote)
                .foregroundStyle(.secondary.opacity(0.95))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .fixedSize(horizontal: false, vertical: true)
            Text(NSLocalizedString("about.sub", comment: "About secondary line"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(String(format: NSLocalizedString("app.version_format", comment: "Version format"), appVersion))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Hero&Peace© 2026")
                .font(.caption2)
                .foregroundStyle(.tertiary.opacity(0.85))
            Spacer()
            Button(NSLocalizedString("action.done", comment: "Done"), action: onDismiss)
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
        static let menuTriggerSize: CGFloat = 88
        static let menuTriggerMargin: CGFloat = 10
    }

    private enum Defaults {
        static let baseLineWidth: CGFloat = 2.2
    }

    private let sessionState = TapeCanvasSessionState()
    private var currentStroke: TapeSessionStroke?
    private var currentStrokeSegmentId: Int?
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
        setBaseStrokeColor: { [weak self] color, index in
            guard let self = self else { return }
            let isDark = self.traitCollection.userInterfaceStyle == .dark
            self.baseStrokeColor = (isDark && index == 0) ? .white : color
        },
        cycleLineWidth: { [weak self] in self?.cycleLineWidth() },
        onClearLastSession: { [weak self] in self?.confirmAndClearSession() },
        onExport: { [weak self] in self?.exportVisible() },
        onSettings: { [weak self] in self?.onRequestSettings?() ?? self?.showToast(text: NSLocalizedString("toast.settings", comment: "Settings"), type: .info) },
        onSparkles: { [weak self] in self?.handleSparklesTap() },
        onRedo: { [weak self] in self?.handleRedoTap() },
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
    func loadSessionFromSettings() {
        loadSession()
    }
    /// Called from Settings: reset trigger button and radial menu position to default (top‑left area).
    func resetRadialMenuPositionFromSettings() {
        let clamped = clampMenuTrigger(point: defaultMenuTriggerCenter())
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

        let visibleIds = sessionState.visibleSegmentIds(contentOffset: contentOffset, boundsWidth: bounds.width, segmentWidth: segmentWidth)
        for id in visibleIds {
            guard let segment = sessionState.segments[id] else { continue }
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

    /// Converts a tape stroke to `RenderStroke` for rendering.
    private func toRenderStroke(_ stroke: TapeSessionStroke) -> RenderStroke {
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

    /// Appends touch samples using `coalescedTouches` when available so fast strokes stay curved between display frames.
    /// Timestamps are spaced monotonically between the last stored time and `touch.timestamp` so width/speed stays stable.
    private func appendStrokeSamplesFromTouch(_ touch: UITouch, event: UIEvent?) {
        guard var stroke = currentStroke else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        let n = samples.count
        let lastT = stroke.times.last ?? touch.timestamp
        let endT = max(touch.timestamp, lastT + 1e-4)
        let span = endT - lastT

        for i in 0..<n {
            let p = toWorldPoint(samples[i].location(in: self))
            if let lp = stroke.points.last {
                let dist = hypot(p.x - lp.x, p.y - lp.y)
                if dist < 0.02, i < n - 1 { continue }
            }
            let t: TimeInterval
            if n == 1 {
                t = endT
            } else {
                t = lastT + span * Double(i + 1) / Double(n)
            }
            stroke.points.append(p)
            stroke.times.append(t)
        }
        currentStroke = stroke
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        if radialMenu.isMenuVisible { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        stopDeceleration()
        let location = touch.location(in: self)
        lastTouchLocation = location
        let color = baseStrokeColor
        currentStroke = TapeSessionStroke(
            points: [toWorldPoint(location)],
            times: [touch.timestamp],
            color: color,
            lineWidth: baseLineWidth
        )
        currentStrokeSegmentId = sessionState.segmentId(forWorldX: toWorldPoint(location).x, segmentWidth: segmentWidth)
        startAutoScrollIfNeeded()
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        let location = touch.location(in: self)
        lastTouchLocation = location
        appendStrokeSamplesFromTouch(touch, event: event)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, touches.count == 1 {
            appendStrokeSamplesFromTouch(touch, event: event)
        }
        guard let stroke = currentStroke, let segmentId = currentStrokeSegmentId else { return }
        sessionState.commitCompletedStroke(segmentId: segmentId, stroke: stroke)
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
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
        guard var stroke = currentStroke else {
            stopAutoScroll()
            return
        }
        let lastT = stroke.times.last ?? CACurrentMediaTime()
        let stamp = lastT + Double(dt)
        stroke.points.append(worldPoint)
        stroke.times.append(stamp)
        currentStroke = stroke
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
        let storedSession = sessionState.buildStoredSession(
            contentOffset: contentOffset,
            savedAt: Date().timeIntervalSince1970
        )

        sessionManager.saveSession(storedSession) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if !self.didShowSavedToastThisSession {
                    self.didShowSavedToastThisSession = true
                    self.showToast(text: NSLocalizedString("toast.saved", comment: "Saved"), type: .success)
                }
            case .failure:
                self.showToast(text: NSLocalizedString("toast.save_failed", comment: "Save failed"), type: .error)
            }
        }
    }

    func loadSession() {
        sessionManager.loadSession { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let storedSession):
                self.sessionState.applyStoredSession(storedSession)
                self.contentOffset = CGPoint(x: storedSession.contentOffset.x, y: storedSession.contentOffset.y)
                self.setNeedsDisplay()
                self.radialMenu.updateActionAvailability(undoEnabled: !self.sessionState.undoStack.isEmpty, redoEnabled: !self.sessionState.redoPayloadStack.isEmpty)
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
        menuTriggerButton.frame.size = CGSize(width: Layout.menuTriggerSize, height: Layout.menuTriggerSize)
        menuTriggerButton.center = clampMenuTrigger(point: loadMenuTriggerPosition() ?? defaultMenuTriggerCenter())
        menuTriggerButton.layer.cornerRadius = menuTriggerButton.bounds.width / 2
        updateMenuTriggerButtonAppearance()
        toastManager.updateLayout(in: bounds)
        bringSubviewToFront(menuTriggerButton)
    }

    /// Shared light/dark refresh; invoked when `userInterfaceStyle` changes via `registerForTraitChanges`.
    private func handleUserInterfaceStyleChange(previous: UITraitCollection?) {
        if traitCollection.userInterfaceStyle != previous?.userInterfaceStyle {
            // Dark mode changed - update colors and redraw
            backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)
            noiseTile = nil // Invalidate noise tile cache to regenerate with new colors
            updateMenuTriggerButtonAppearance()
            toastManager.updateTraitCollection(traitCollection)
            let isDark = traitCollection.userInterfaceStyle == .dark
            radialMenu.updateColorsForDarkMode(
                graphiteColor: graphiteColor.resolvedColor(with: traitCollection),
                firstColorMenuTint: isDark ? .white : nil
            )
            applySavedBrushSettings()
            setNeedsDisplay()
        }
    }

    private func drawStrokesForExport(in context: CGContext) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let visibleIds = sessionState.visibleSegmentIds(contentOffset: contentOffset, boundsWidth: bounds.width, segmentWidth: segmentWidth)
        for id in visibleIds {
            guard let segment = sessionState.segments[id] else { continue }
            for stroke in segment.strokes {
                CanvasRenderer.drawStrokeWorld(toRenderStroke(stroke), in: context)
            }
        }
        if let stroke = currentStroke {
            CanvasRenderer.drawStrokeWorld(toRenderStroke(stroke), in: context)
        }
    }

    private func updateSegmentsIfNeeded() {
        sessionState.updateSegmentsIfNeeded(contentOffset: contentOffset, boundsWidth: bounds.width, segmentWidth: segmentWidth)
    }

    func showMenuAtCenter() {
        radialMenu.showMenu(at: menuTriggerButton.center)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        radialMenu.handleTap(at: location)
    }

    @objc private func handleSparklesTap() {
        undoLastStroke()
    }
    
    @objc private func handleRedoTap() {
        redoLastStroke()
    }

    /// Removes the most recently completed stroke (Undo). No-op if nothing to undo.
    private func undoLastStroke() {
        guard sessionState.undoLastStroke() else { return }
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
        setNeedsDisplay()
        showToast(text: NSLocalizedString("toast.undo", comment: "Undo"), type: .warning)
    }

    /// Re-applies the most recently undone stroke (Redo). No-op if nothing to redo.
    private func redoLastStroke() {
        guard sessionState.redoLastStroke() else { return }
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
        setNeedsDisplay()
        showToast(text: NSLocalizedString("toast.redo", comment: "Redo"), type: .success)
    }

    private func exportVisible() {
        let defaults = UserDefaults.standard
        let exportFull = defaults.object(forKey: "settings.export.full") != nil && defaults.bool(forKey: "settings.export.full")
        if exportFull, let bounds = sessionState.worldBoundingRectForExport(currentStroke: currentStroke) {
            // Export full world bounds drawing
            exportManager.exportFull(
                worldBounds: bounds,
                backgroundColor: backgroundColorTone.resolvedColor(with: traitCollection),
                drawStrokesWorld: { [weak self] context in
                    guard let self = self else { return }
                    // Draw all strokes in full world coordinates
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    for segment in self.sessionState.segments.values {
                        for stroke in segment.strokes {
                            CanvasRenderer.drawStrokeWorld(self.toRenderStroke(stroke), in: context)
                        }
                    }
                    if let stroke = self.currentStroke {
                        CanvasRenderer.drawStrokeWorld(self.toRenderStroke(stroke), in: context)
                    }
                },
                presentShare: { [weak self] url in
                    self?.presentShare(url: url)
                },
                showToast: { [weak self] text, type in
                    self?.showToast(text: text, type: type)
                }
            )
        } else {
            // Export visible area as before
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
            title: NSLocalizedString("alert.clear_title", comment: "Clear drawing?"),
            message: NSLocalizedString("alert.clear_message", comment: "This will remove all strokes in current session. This cannot be undone."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("action.cancel", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("action.clear", comment: "Clear"), style: .destructive) { [weak self] _ in
            self?.clearLastDrawingSession()
            self?.showToast(text: NSLocalizedString("toast.session_cleared", comment: "Session cleared"), type: .warning)
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
        sessionState.clear()
        currentStroke = nil
        currentStrokeSegmentId = nil
        sessionState.undoStack.removeAll()
        sessionState.redoPayloadStack.removeAll()
        telemetry = Telemetry()
        didShowSavedToastThisSession = false
        sessionManager.deleteSession()
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
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
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
        _ = toastManager // Initialize toast manager
        registerForAppLifecycle()
        if sessionManager.shouldAutoloadOnLaunch() {
            loadSession()
        }
        applySavedBrushSettings()
        sessionManager.startPeriodicSaveTimerIfNeeded { [weak self] in
            self?.saveSession()
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TapeCanvasUIView, previousTraitCollection: UITraitCollection) in
            self?.handleUserInterfaceStyleChange(previous: previousTraitCollection)
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
            let isDark = traitCollection.userInterfaceStyle == .dark
            let isFirstPrimary = (idx == 0)
            let isFirstAchievement = (idx == primaryColorPalette.count)
            if isDark && (isFirstPrimary || isFirstAchievement) {
                baseStrokeColor = .white
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
            let message = index == 0 ? NSLocalizedString("toast.original_colors_restored", comment: "Original colors restored") : NSLocalizedString("toast.new_colors_unlocked", comment: "New colors unlocked")
            showToast(text: message, type: .success)
        }
        lastPaletteIndex = index
    }

    /// Default center for the menu trigger button (top‑left area from safe area).
    private func defaultMenuTriggerCenter() -> CGPoint {
        CGPoint(
            x: safeAreaInsets.left + Layout.menuTriggerMargin + Layout.menuTriggerSize / 2,
            y: safeAreaInsets.top + Layout.menuTriggerMargin + Layout.menuTriggerSize / 2
        )
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
            menuTriggerButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title1)
            menuTriggerButton.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        menuTriggerButton.accessibilityLabel = NSLocalizedString("accessibility.menu_trigger_label", comment: "Open radial menu")
        menuTriggerButton.accessibilityHint = NSLocalizedString("accessibility.menu_trigger_hint", comment: "Double-tap to open the radial menu. Drag to move the button.")
        menuTriggerButton.accessibilityTraits.insert(.button)
        menuTriggerButton.addAction(UIAction { [weak self] _ in
            self?.showMenuAtCenter()
        }, for: .touchUpInside)
        menuTriggerButton.addGestureRecognizer(menuTriggerPan)
        menuTriggerButton.isUserInteractionEnabled = true
        updateMenuTriggerButtonAppearance()
        addSubview(menuTriggerButton)
        menuTriggerButton.layer.zPosition = 2000
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

