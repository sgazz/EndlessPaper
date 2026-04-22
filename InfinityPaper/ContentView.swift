//
//  ContentView.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import OSLog
import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            TapeCanvasView()
            .ignoresSafeArea()
        }
    }
}

private struct ToolbarSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = CGSize(width: 340, height: 52)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct TapeCanvasView: View {
    @StateObject private var toolbarBroker = CanvasToolbarStateBroker()
    @State private var showAbout = false
    @State private var showSettings = false
    @AppStorage("firstUseOrientationDismissed") private var firstUseOrientationDismissed = false

    @State private var toolbarMeasuredSize: CGSize = ToolbarSizePreferenceKey.defaultValue
    @State private var showClearCanvasConfirmation = false
    @State private var showNewSpaceConfirmation = false
    @State private var chromeHiddenForFocus = false

    private var toolbarDock: CanvasToolbarDock { .top }

    /// Top/bottom dock: balanced offset from safe area (unchanged feel).
    private let toolbarTopBottomMargin: CGFloat = 11
    /// Leading/trailing dock: small inset after safe area (typically ~8–10 pt to visible edge on phones).
    private let toolbarSideDockMargin: CGFloat = 4
    private let toolbarHintReserve: CGFloat = 56

    var body: some View {
        ZStack {
            TapeCanvasRepresentable(
                toolbarBroker: toolbarBroker,
                onRequestSettings: { DispatchQueue.main.async { showAbout = true } },
                onOpenFullSettings: { DispatchQueue.main.async { showSettings = true } },
                onCanvasReady: { _ in }
            )
            .ignoresSafeArea()

            GeometryReader { _ in
                VStack {
                    Spacer(minLength: 0)
                    if !firstUseOrientationDismissed {
                        let pad = toolbarDock.hintContentPadding(toolbarReserve: toolbarHintReserve)
                        VStack(spacing: 10) {
                            Text(NSLocalizedString("first_use.lead", comment: "First session one-line hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(NSLocalizedString("first_use.body", comment: "First session second line"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, pad.top + 8)
                        .padding(.bottom, pad.bottom + 8)
                        .padding(.leading, pad.leading)
                        .padding(.trailing, pad.trailing)
                        .opacity(chromeHiddenForFocus ? 0 : 1)
                        .allowsHitTesting(!chromeHiddenForFocus)
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                firstUseOrientationDismissed = true
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(!chromeHiddenForFocus)

            GeometryReader { geo in
                let safe = geo.safeAreaInsets
                let dock: CanvasToolbarDock = .top
                let isiPhonePortrait = UIDevice.current.userInterfaceIdiom == .phone && geo.size.height > geo.size.width
                let docked = dock.dockedCenter(
                    toolbarSize: toolbarMeasuredSize,
                    containerSize: geo.size,
                    safeArea: safe,
                    topBottomMargin: toolbarTopBottomMargin,
                    sideDockMargin: toolbarSideDockMargin
                )
                let display = CGPoint(
                    x: docked.x,
                    y: docked.y + (isiPhonePortrait ? toolbarMeasuredSize.height : 0)
                )

                ZStack {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)

                    CanvasFloatingToolbar(
                        broker: toolbarBroker,
                        dock: dock,
                        onSelectColor: { idx in
                            toolbarBroker.canvas?.toolbarSelectColor(at: idx)
                        },
                        onSelectLineWidthPreset: { idx in
                            toolbarBroker.canvas?.toolbarSetLineWidthPreset(at: idx)
                        },
                        onUndo: {
                            toolbarBroker.canvas?.toolbarUndo()
                        },
                        onRedo: {
                            toolbarBroker.canvas?.toolbarRedo()
                        },
                        onExport: {
                            toolbarBroker.canvas?.toolbarExport()
                        },
                        onSettings: {
                            toolbarBroker.canvas?.toolbarOpenFullSettings()
                        },
                        onTogglePaperLock: {
                            DispatchQueue.main.async {
                                guard let canvas = toolbarBroker.canvas else { return }
                                canvas.toolbarSetPaperMovementLocked(!canvas.toolbarPaperMovementLocked)
                                toolbarBroker.syncFromCanvas()
                            }
                        },
                        onInfinityClearCanvas: {
                            DispatchQueue.main.async {
                                showClearCanvasConfirmation = true
                            }
                        },
                        onInfinityNewSpace: {
                            DispatchQueue.main.async {
                                showNewSpaceConfirmation = true
                            }
                        },
                        onInfinityCenterView: {
                            DispatchQueue.main.async {
                                toolbarBroker.canvas?.toolbarCenterViewOnContent()
                                toolbarBroker.syncFromCanvas()
                            }
                        },
                        onInfinityFocusMode: {
                            withAnimation(.easeOut(duration: 0.28)) {
                                chromeHiddenForFocus = true
                            }
                        },
                        onInfinityZoomIn: {
                            DispatchQueue.main.async {
                                toolbarBroker.canvas?.toolbarZoomIn()
                                toolbarBroker.syncFromCanvas()
                            }
                        },
                        onInfinityZoomOut: {
                            DispatchQueue.main.async {
                                toolbarBroker.canvas?.toolbarZoomOut()
                                toolbarBroker.syncFromCanvas()
                            }
                        },
                        onInfinityResetView: {
                            DispatchQueue.main.async {
                                toolbarBroker.canvas?.toolbarResetView()
                                toolbarBroker.syncFromCanvas()
                            }
                        },
                        onInfinityFitContent: {
                            DispatchQueue.main.async {
                                toolbarBroker.canvas?.toolbarFitContent()
                                toolbarBroker.syncFromCanvas()
                            }
                        }
                    )
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: ToolbarSizePreferenceKey.self,
                                value: g.size
                            )
                        }
                    )
                    .position(display)
                    .allowsHitTesting(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(chromeHiddenForFocus ? 0 : 1)
            .allowsHitTesting(!chromeHiddenForFocus)
        }
        .overlay(alignment: .bottom) {
            if chromeHiddenForFocus {
                Button {
                    withAnimation(.easeOut(duration: 0.28)) {
                        chromeHiddenForFocus = false
                    }
                } label: {
                    Text(String(localized: "toolbar.focus_show_tools"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(ToolbarSizePreferenceKey.self) { toolbarMeasuredSize = $0 }
        .confirmationDialog(
            String(localized: "toolbar.clear_confirm_title"),
            isPresented: $showClearCanvasConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "toolbar.clear_confirm_action"), role: .destructive) {
                toolbarBroker.canvas?.toolbarClearCanvasConfirmed()
                toolbarBroker.syncFromCanvas()
            }
            Button(String(localized: "action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "toolbar.clear_confirm_message"))
        }
        .confirmationDialog(
            String(localized: "toolbar.new_space_confirm_title"),
            isPresented: $showNewSpaceConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "toolbar.new_space_confirm_action"), role: .destructive) {
                toolbarBroker.canvas?.toolbarPerformNewSpace()
                toolbarBroker.syncFromCanvas()
            }
            Button(String(localized: "action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "toolbar.new_space_confirm_message"))
        }
        .sheet(isPresented: $showAbout) {
            AboutView(onDismiss: { showAbout = false })
        }
        .sheet(isPresented: $showSettings) {
            if let cv = toolbarBroker.canvas {
                SettingsView(
                    palette: cv.exposedPrimaryPalette,
                    currentBaseColor: cv.exposedBaseStrokeColor,
                    currentLineWidth: cv.exposedBaseLineWidth,
                    onSelectBaseColor: { color in
                        cv.setBaseStrokeColorFromSettings(color)
                        toolbarBroker.syncFromCanvas()
                    },
                    onLineWidthChanged: { width in
                        cv.setBaseLineWidthFromSettings(width)
                        toolbarBroker.syncFromCanvas()
                    },
                    onClearSession: {
                        cv.confirmAndClearSessionFromSettings()
                        toolbarBroker.syncFromCanvas()
                    },
                    onLoadPreviousSession: {
                        cv.loadSessionFromSettings()
                    },
                    onResetRadialMenuPosition: {
                        cv.resetRadialMenuPositionFromSettings()
                    },
                    onLegacyRadialTriggerChanged: {
                        cv.refreshLegacyRadialTriggerVisibility()
                    },
                    onDismiss: { showSettings = false }
                )
            } else {
                Color.clear
                    .onAppear { showSettings = false }
            }
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
            Text("Hero&Frend© 2026")
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
    @ObservedObject var toolbarBroker: CanvasToolbarStateBroker
    var onRequestSettings: () -> Void
    var onOpenFullSettings: () -> Void
    var onCanvasReady: (TapeCanvasUIView) -> Void

    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView()
        view.onRequestSettings = onRequestSettings
        view.onOpenFullSettings = onOpenFullSettings
        view.onToolbarStateChange = { [weak toolbarBroker] in
            toolbarBroker?.syncFromCanvas()
        }
        toolbarBroker.attach(view)
        onCanvasReady(view)
        return view
    }

    func updateUIView(_ uiView: TapeCanvasUIView, context: Context) {
        uiView.onRequestSettings = onRequestSettings
        uiView.onOpenFullSettings = onOpenFullSettings
        uiView.onToolbarStateChange = { [weak toolbarBroker] in
            toolbarBroker?.syncFromCanvas()
        }
    }
}

final class TapeCanvasUIView: UIView {
    private enum Layout {
        static let menuTriggerSize: CGFloat = 88
        static let menuTriggerMargin: CGFloat = 10
    }

    private enum Defaults {
        /// Matches `toolbarWidthPresets` “medium” for new installs.
        static let baseLineWidth: CGFloat = 2.5
    }

    /// Curated widths for toolbar + radial width control (persisted).
    static let toolbarWidthPresets: [CGFloat] = [1.5, 2.5, 4.0, 6.0]

    private let sessionState = TapeCanvasSessionState()
    private var currentStroke: TapeSessionStroke?
    private var currentStrokeSegmentId: Int?
    private var contentOffset: CGPoint = .zero
    private var zoomScale: CGFloat = 1
    private let minZoomScale: CGFloat = 0.5
    private let maxZoomScale: CGFloat = 2.5
    private var paperMovementLocked = false
    /// Avoid overlapping `saveSession` work (timer + resign active); coalesce to one follow-up save if needed.
    private var sessionSaveInFlight = false
    private var sessionSaveCoalesceRequested = false
    private var paperSurfaceObserverToken: NSObjectProtocol?
#if DEBUG
    private static let saveDiagnostics = Logger(subsystem: "com.infinitypaper", category: "TapeCanvas")
#endif
    private var displayLink: CADisplayLink?
    private var autoScrollLink: CADisplayLink?
    private var lastTouchLocation: CGPoint?
    private let autoScrollSpeed: CGFloat = 90
    private var decelVelocity: CGPoint = .zero
    private let decelRate: CGFloat = 0.92
    private let velocityStopThreshold: CGFloat = 12
    private var cachedPaperSurface: PaperSurface = .quiet
    /// Adaptive background color that responds to system dark mode.
    private var backgroundColorTone: UIColor {
        UIColor { traits in
            PaperSurface.current().backgroundColor(for: traits)
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
    /// Single curated palette: calm canvas, high-energy strokes (slot 0 → white in dark mode for “paper ink”).
    private let primaryColorPalette: [UIColor] = [
        // Strong neutrals (balance + fine lines on light paper)
        UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 0.96), // #1A1A1F deep ink
        UIColor(red: 0.24, green: 0.27, blue: 0.34, alpha: 0.95), // #3D4557 cool graphite
        // Purple / violet (brand spine)
        UIColor(red: 0.58, green: 0.20, blue: 1.00, alpha: 0.96), // #9433FF electric violet
        UIColor(red: 0.43, green: 0.16, blue: 0.85, alpha: 0.96), // #6E29D9 royal purple
        UIColor(red: 0.72, green: 0.28, blue: 0.98, alpha: 0.95), // #B847FA vivid orchid
        // Magenta / pink
        UIColor(red: 1.00, green: 0.14, blue: 0.62, alpha: 0.96), // #FF249E neon magenta
        UIColor(red: 1.00, green: 0.35, blue: 0.78, alpha: 0.95), // #FF59C7 vivid pink
        // Warm accents
        UIColor(red: 1.00, green: 0.32, blue: 0.38, alpha: 0.96), // #FF5261 hot coral
        UIColor(red: 1.00, green: 0.48, blue: 0.08, alpha: 0.96), // #FF7A14 bright orange
        UIColor(red: 1.00, green: 0.76, blue: 0.12, alpha: 0.95), // #FFC21F electric amber
        // Greens
        UIColor(red: 0.55, green: 1.00, blue: 0.22, alpha: 0.95), // #8CFF38 acid lime
        UIColor(red: 0.12, green: 0.94, blue: 0.48, alpha: 0.96), // #1EF07A neon spring
        // Cyans / teals / blues
        UIColor(red: 0.02, green: 0.86, blue: 0.78, alpha: 0.96), // #05DBC7 neon teal
        UIColor(red: 0.05, green: 0.92, blue: 1.00, alpha: 0.96), // #0DEBFF bright cyan
        UIColor(red: 0.14, green: 0.55, blue: 1.00, alpha: 0.96), // #248CFF laser blue
        UIColor(red: 0.32, green: 0.62, blue: 1.00, alpha: 0.95), // #519EFF sky laser
        // Extra depth without mud
        UIColor(red: 0.18, green: 0.95, blue: 1.00, alpha: 0.94) // #2EF2FF aqua pop
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
    private lazy var pinchRecognizer: UIPinchGestureRecognizer = {
        UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    }()
    private lazy var twoFingerDoubleTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerDoubleTap(_:)))
        recognizer.numberOfTouchesRequired = 2
        recognizer.numberOfTapsRequired = 2
        recognizer.cancelsTouchesInView = false
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

    /// Radial menu “About” / legacy info entry.
    var onRequestSettings: (() -> Void)?
    /// Bottom toolbar gear: full Settings sheet.
    var onOpenFullSettings: (() -> Void)?
    /// Called when undo/redo availability or line width changes so SwiftUI toolbar can refresh.
    var onToolbarStateChange: (() -> Void)?

    private static let legacyRadialDefaultsKey = "settings.ui.legacyRadialMenuTrigger"

    static func readLegacyRadialMenuTriggerEnabled() -> Bool {
        false
    }

    var toolbarUndoEnabled: Bool { !sessionState.undoStack.isEmpty }
    var toolbarRedoEnabled: Bool { !sessionState.redoPayloadStack.isEmpty }
    var toolbarBaseLineWidth: CGFloat { baseLineWidth }
    var toolbarPaperMovementLocked: Bool { paperMovementLocked }

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

    /// After SwiftUI confirmation from the toolbar “More” menu (no second alert).
    func toolbarClearCanvasConfirmed() {
        clearLastDrawingSession()
        showToast(text: NSLocalizedString("toast.session_cleared", comment: "Session cleared"), type: .warning)
    }

    /// Clears the session, resets horizontal scroll to origin, and nudges the user gently.
    func toolbarPerformNewSpace() {
        clearLastDrawingSession()
        contentOffset = .zero
        setNeedsDisplay()
        postToolbarStateChange()
        showToast(text: NSLocalizedString("toast.new_space", comment: "Fresh space"), type: .info)
    }

    /// Scrolls so the current drawing (if any) is roughly centered in the viewport.
    func toolbarCenterViewOnContent() {
        guard bounds.width > 1 else { return }
        let visibleWorldWidth = bounds.width / max(zoomScale, 0.001)
        let visibleWorldHeight = bounds.height / max(zoomScale, 0.001)
        if let rect = sessionState.rawWorldBoundingRect(currentStroke: currentStroke) {
            contentOffset.x = rect.midX - visibleWorldWidth * 0.5
            contentOffset.y = rect.midY - visibleWorldHeight * 0.5
        } else {
            contentOffset = .zero
        }
        clampContentOffset()
        setNeedsDisplay()
        postToolbarStateChange()
        showToast(text: NSLocalizedString("toast.view_centered", comment: "View centered"), type: .info)
    }

    func toolbarZoomIn() {
        zoomBy(step: 1.2)
    }

    func toolbarZoomOut() {
        zoomBy(step: 1 / 1.2)
    }

    func toolbarResetView() {
        resetZoomAndCenter(animated: true)
    }

    func toolbarFitContent() {
        fitContentInView(animated: true)
    }
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

    // MARK: - Bottom toolbar (SwiftUI)

    private func postToolbarStateChange() {
        onToolbarStateChange?()
    }

    private func applyLegacyRadialMenuVisibility() {
        menuTriggerButton.isHidden = true
        menuTriggerButton.isUserInteractionEnabled = false
        menuTriggerPan.isEnabled = false
    }

    /// Call after toggling the legacy radial trigger in Settings so the ∞ button appears or hides immediately.
    func refreshLegacyRadialTriggerVisibility() {
        applyLegacyRadialMenuVisibility()
    }

    func toolbarUndo() {
        undoLastStroke()
    }

    func toolbarRedo() {
        redoLastStroke()
    }

    func toolbarExport() {
        exportVisible()
    }

    func toolbarOpenFullSettings() {
        onOpenFullSettings?()
    }

    func toolbarSetPaperMovementLocked(_ locked: Bool) {
        paperMovementLocked = locked
        if locked {
            stopDeceleration()
            stopAutoScroll()
            lastTouchLocation = nil
        }
        postToolbarStateChange()
        showToast(
            text: locked
                ? NSLocalizedString("toast.paper_movement_locked", comment: "Paper movement locked")
                : NSLocalizedString("toast.paper_movement_unlocked", comment: "Paper movement unlocked"),
            type: .info
        )
    }

    /// Legacy entry: cycles through `toolbarWidthPresets` and persists (radial width button).
    func toolbarCycleLineWidthPersist() {
        cycleLineWidth()
    }

    /// Toolbar / popover: set one of the curated widths.
    func toolbarSetLineWidthPreset(at index: Int) {
        guard Self.toolbarWidthPresets.indices.contains(index) else { return }
        baseLineWidth = Self.toolbarWidthPresets[index]
        UserDefaults.standard.set(Double(baseLineWidth), forKey: SettingsKeys.baseLineWidth)
        setNeedsDisplay()
        postToolbarStateChange()
    }

    /// Index into `toolbarWidthPresets` nearest to the current width (for selection ring).
    func toolbarWidthPresetIndex() -> Int {
        let presets = Self.toolbarWidthPresets
        guard !presets.isEmpty else { return 0 }
        return presets.indices.min { a, b in
            abs(presets[a] - baseLineWidth) < abs(presets[b] - baseLineWidth)
        } ?? 0
    }

    /// Persisted palette index clamped to the current exposed palette (toolbar selection ring).
    var toolbarSelectedPaletteIndex: Int {
        let palette = exposedPrimaryPalette
        guard !palette.isEmpty else { return 0 }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKeys.baseColorIndex) != nil {
            let idx = defaults.integer(forKey: SettingsKeys.baseColorIndex)
            return min(max(0, idx), palette.count - 1)
        }
        return 0
    }

    func toolbarSelectColor(at index: Int) {
        let palette = exposedPrimaryPalette
        guard palette.indices.contains(index) else { return }
        let chosen = palette[index]
        let isDark = traitCollection.userInterfaceStyle == .dark
        let isFirstPrimary = index == 0
        let isFirstAchievement = index == primaryColorPalette.count
        baseStrokeColor = (isDark && (isFirstPrimary || isFirstAchievement)) ? .white : chosen
        UserDefaults.standard.set(index, forKey: SettingsKeys.baseColorIndex)
        radialMenu.updateColorsForDarkMode(
            graphiteColor: graphiteColor.resolvedColor(with: traitCollection),
            firstColorMenuTint: isDark ? .white : nil
        )
        setNeedsDisplay()
        postToolbarStateChange()
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
        if let token = paperSurfaceObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
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
            noiseProfile: PaperSurface.current().noiseProfile,
            traitCollection: traitCollection
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let viewportWorldWidth = bounds.width / max(zoomScale, 0.001)
        let visibleIds = sessionState.visibleSegmentIds(contentOffset: contentOffset, boundsWidth: viewportWorldWidth, segmentWidth: segmentWidth)
        context.saveGState()
        context.scaleBy(x: zoomScale, y: zoomScale)
        context.translateBy(x: -contentOffset.x, y: -contentOffset.y)
        for id in visibleIds {
            guard let segment = sessionState.segments[id] else { continue }
            for stroke in segment.strokes {
                CanvasRenderer.drawStrokeWorld(toRenderStroke(stroke), in: context)
            }
        }

        if let stroke = currentStroke {
            CanvasRenderer.drawStrokeWorld(toRenderStroke(stroke), in: context)
        }
        context.restoreGState()
        
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
        CGPoint(
            x: viewPoint.x / max(zoomScale, 0.001) + contentOffset.x,
            y: viewPoint.y / max(zoomScale, 0.001) + contentOffset.y
        )
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
        guard (panRecognizer.state == .possible || panRecognizer.state == .failed),
              (pinchRecognizer.state == .possible || pinchRecognizer.state == .failed) else { return }
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
        guard (panRecognizer.state == .possible || panRecognizer.state == .failed),
              (pinchRecognizer.state == .possible || pinchRecognizer.state == .failed) else { return }
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
        postToolbarStateChange()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentStroke = nil
        currentStrokeSegmentId = nil
        lastTouchLocation = nil
        stopAutoScroll()
        setNeedsDisplay()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard !paperMovementLocked else {
            recognizer.setTranslation(.zero, in: self)
            if recognizer.state == .began || recognizer.state == .changed {
                stopDeceleration()
            }
            return
        }
        switch recognizer.state {
        case .began:
            stopDeceleration()
        case .changed:
            let translation = recognizer.translation(in: self)
            contentOffset.x -= translation.x / max(zoomScale, 0.001)
            contentOffset.y -= translation.y / max(zoomScale, 0.001)
            telemetry.recordPan(deltaX: hypot(translation.x, translation.y))
            recognizer.setTranslation(.zero, in: self)
            updateSegmentsIfNeeded()
            setNeedsDisplay()
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self)
            decelVelocity = CGPoint(
                x: velocity.x / max(zoomScale, 0.001),
                y: velocity.y / max(zoomScale, 0.001)
            )
            startDeceleration()
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard !paperMovementLocked else { return }
        let oldScale = zoomScale
        let newScale = min(max(minZoomScale, oldScale * recognizer.scale), maxZoomScale)
        guard abs(newScale - oldScale) > 0.0001 else {
            recognizer.scale = 1
            return
        }
        let focal = recognizer.location(in: self)
        let worldFocalBefore = CGPoint(
            x: focal.x / max(oldScale, 0.001) + contentOffset.x,
            y: focal.y / max(oldScale, 0.001) + contentOffset.y
        )
        zoomScale = newScale
        contentOffset.x = worldFocalBefore.x - focal.x / newScale
        contentOffset.y = worldFocalBefore.y - focal.y / newScale
        clampContentOffset()
        updateSegmentsIfNeeded()
        setNeedsDisplay()
        recognizer.scale = 1
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
        decelVelocity = .zero
    }

    @objc private func handleDeceleration() {
        guard displayLink != nil else { return }
        let dt = CGFloat(displayLink?.duration ?? 1.0 / 60.0)
        if hypot(decelVelocity.x, decelVelocity.y) < velocityStopThreshold {
            stopDeceleration()
            return
        }
        contentOffset.x -= decelVelocity.x * dt
        contentOffset.y -= decelVelocity.y * dt
        telemetry.recordPan(deltaX: hypot(decelVelocity.x * dt, decelVelocity.y * dt))
        let decay = pow(decelRate, dt * 60)
        decelVelocity.x *= decay
        decelVelocity.y *= decay
        updateSegmentsIfNeeded()
        setNeedsDisplay()
    }

    private func startAutoScrollIfNeeded() {
        guard !paperMovementLocked else { return }
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
        guard !paperMovementLocked else {
            stopAutoScroll()
            return
        }
        guard let lastTouchLocation, currentStroke != nil else {
            stopAutoScroll()
            return
        }
        let dt = CGFloat(autoScrollLink?.duration ?? 1.0 / 60.0)
        contentOffset.x += (autoScrollSpeed * dt) / max(zoomScale, 0.001)
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
        guard sessionState.hasUnsavedChanges else {
#if DEBUG
            Self.saveDiagnostics.debug("saveSession skipped: nothing to persist")
#endif
            return
        }
        if sessionSaveInFlight {
            sessionSaveCoalesceRequested = true
            return
        }
        sessionSaveInFlight = true
        sessionSaveCoalesceRequested = false
        let tokenSnapshot = sessionState.persistenceToken
        let storedSession = sessionState.buildStoredSession(
            contentOffset: contentOffset,
            savedAt: Date().timeIntervalSince1970
        )

        sessionManager.saveSession(storedSession) { [weak self] result in
            guard let self else { return }
            self.sessionSaveInFlight = false
            switch result {
            case .success:
                self.sessionState.acknowledgePersistenceSave(succeededWithToken: tokenSnapshot)
                if !self.didShowSavedToastThisSession {
                    self.didShowSavedToastThisSession = true
                    self.showToast(text: NSLocalizedString("toast.saved", comment: "Saved"), type: .success)
                }
                let needsAnother = self.sessionState.hasUnsavedChanges || self.sessionSaveCoalesceRequested
                self.sessionSaveCoalesceRequested = false
                if needsAnother {
                    self.saveSession()
                }
            case .failure:
                self.sessionSaveCoalesceRequested = false
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
                self.postToolbarStateChange()
            case .failure:
                // Session load failed - this is expected if no session exists yet
                break
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyLegacyRadialMenuVisibility()
        // Update background color to adapt to dark mode / paper surface.
        backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)

        let surfaceNow = PaperSurface.current()
        if surfaceNow != cachedPaperSurface {
            cachedPaperSurface = surfaceNow
            noiseTile = nil
            setNeedsDisplay()
        }
        
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
        let viewportWorldWidth = bounds.width / max(zoomScale, 0.001)
        let visibleIds = sessionState.visibleSegmentIds(contentOffset: contentOffset, boundsWidth: viewportWorldWidth, segmentWidth: segmentWidth)
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
        let viewportWorldWidth = bounds.width / max(zoomScale, 0.001)
        sessionState.updateSegmentsIfNeeded(contentOffset: contentOffset, boundsWidth: viewportWorldWidth, segmentWidth: segmentWidth)
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
        postToolbarStateChange()
    }

    /// Re-applies the most recently undone stroke (Redo). No-op if nothing to redo.
    private func redoLastStroke() {
        guard sessionState.redoLastStroke() else { return }
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
        setNeedsDisplay()
        showToast(text: NSLocalizedString("toast.redo", comment: "Redo"), type: .success)
        postToolbarStateChange()
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
                        noiseProfile: PaperSurface.current().noiseProfile,
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
        telemetry = Telemetry()
        didShowSavedToastThisSession = false
        sessionManager.deleteSession()
        radialMenu.updateActionAvailability(undoEnabled: !sessionState.undoStack.isEmpty, redoEnabled: !sessionState.redoPayloadStack.isEmpty)
        setNeedsDisplay()
        postToolbarStateChange()
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
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(twoFingerDoubleTapRecognizer)
        tapRecognizer.require(toFail: twoFingerDoubleTapRecognizer)
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
        if paperSurfaceObserverToken == nil {
            paperSurfaceObserverToken = NotificationCenter.default.addObserver(
                forName: PaperSurface.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.cachedPaperSurface = PaperSurface.current()
                self.backgroundColor = self.backgroundColorTone.resolvedColor(with: self.traitCollection)
                self.noiseTile = nil
                self.setNeedsDisplay()
            }
        }
        applyLegacyRadialMenuVisibility()
    }

    @objc private func handleTwoFingerDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        resetZoomAndCenter(animated: true)
    }

    private func resetZoomAndCenter(animated: Bool) {
        let apply = {
            self.zoomScale = 1
            self.toolbarCenterViewOnContent()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func fitContentInView(animated: Bool) {
        guard let rect = sessionState.rawWorldBoundingRect(currentStroke: currentStroke),
              rect.width > 1, rect.height > 1, bounds.width > 1, bounds.height > 1 else {
            resetZoomAndCenter(animated: animated)
            return
        }
        let pad: CGFloat = 24
        let targetX = (bounds.width - 2 * pad) / rect.width
        let targetY = (bounds.height - 2 * pad) / rect.height
        let targetScale = min(max(minZoomScale, min(targetX, targetY)), maxZoomScale)
        let apply = {
            self.zoomScale = targetScale
            let visibleW = self.bounds.width / max(self.zoomScale, 0.001)
            let visibleH = self.bounds.height / max(self.zoomScale, 0.001)
            self.contentOffset.x = rect.midX - visibleW * 0.5
            self.contentOffset.y = rect.midY - visibleH * 0.5
            self.clampContentOffset()
            self.updateSegmentsIfNeeded()
            self.setNeedsDisplay()
            self.postToolbarStateChange()
            self.showToast(text: NSLocalizedString("toast.view_fit_content", comment: "Fit content"), type: .info)
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func zoomBy(step: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let oldScale = zoomScale
        let newScale = min(max(minZoomScale, oldScale * step), maxZoomScale)
        guard abs(newScale - oldScale) > 0.0001 else { return }
        let worldAtCenter = CGPoint(
            x: center.x / max(oldScale, 0.001) + contentOffset.x,
            y: center.y / max(oldScale, 0.001) + contentOffset.y
        )
        zoomScale = newScale
        contentOffset.x = worldAtCenter.x - center.x / newScale
        contentOffset.y = worldAtCenter.y - center.y / newScale
        clampContentOffset()
        updateSegmentsIfNeeded()
        setNeedsDisplay()
        postToolbarStateChange()
    }

    private func clampContentOffset() {
        contentOffset.x = max(-bounds.width, min(contentOffset.x, 1_000_000))
        contentOffset.y = max(-bounds.height, min(contentOffset.y, 1_000_000))
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
        let presets = Self.toolbarWidthPresets
        let nearest = presets.indices.min { a, b in
            abs(presets[a] - baseLineWidth) < abs(presets[b] - baseLineWidth)
        } ?? 0
        let next = (nearest + 1) % presets.count
        baseLineWidth = presets[next]
        UserDefaults.standard.set(Double(baseLineWidth), forKey: SettingsKeys.baseLineWidth)
        setNeedsDisplay()
        postToolbarStateChange()
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
            if Self.readLegacyRadialMenuTriggerEnabled() {
                NSLocalizedString("accessibility.canvas_hint_radial", comment: "VoiceOver: canvas with legacy radial")
            } else {
                NSLocalizedString("accessibility.canvas_hint_toolbar", comment: "VoiceOver: canvas with bottom toolbar")
            }
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

