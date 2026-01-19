//
//  ContentView.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var proStatus: ProStatus
    @State private var menuTrigger: Int = 0

    var body: some View {
        ZStack {
            TapeCanvasView(
                isProUser: proStatus.isPro,
                scenePhase: scenePhase,
                menuTrigger: menuTrigger,
                purchasePro: {
                    await proStatus.purchasePro()
                },
                restorePurchases: {
                    await proStatus.restorePurchases()
                }
            )
            .ignoresSafeArea()

            Image("InfinityPaper")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.leading, 12)
                .zIndex(10)
                .highPriorityGesture(
                    TapGesture().onEnded {
                        menuTrigger += 1
                    }
                )
        }
    }
}

private struct TapeCanvasView: View {
    let isProUser: Bool
    let scenePhase: ScenePhase
    let menuTrigger: Int
    let purchasePro: () async -> PurchaseOutcome
    let restorePurchases: () async -> Void

    var body: some View {
        TapeCanvasRepresentable(
            isProUser: isProUser,
            scenePhase: scenePhase,
            menuTrigger: menuTrigger,
            purchasePro: purchasePro,
            restorePurchases: restorePurchases
        )
            .ignoresSafeArea()
    }
}

private struct TapeCanvasRepresentable: UIViewRepresentable {
    let isProUser: Bool
    let scenePhase: ScenePhase
    let menuTrigger: Int
    let purchasePro: () async -> PurchaseOutcome
    let restorePurchases: () async -> Void

    final class Coordinator {
        var lastMenuTrigger: Int = 0
    }

    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView()
        view.backgroundColor = UIColor(white: 0.98, alpha: 1.0)
        view.isProUser = isProUser
        view.onPurchasePro = purchasePro
        view.onRestorePurchases = restorePurchases
        return view
    }

    func updateUIView(_ uiView: TapeCanvasUIView, context: Context) {
        uiView.isProUser = isProUser
        uiView.onPurchasePro = purchasePro
        uiView.onRestorePurchases = restorePurchases
        if scenePhase == .background {
            uiView.persistSessionIfNeeded()
        }
        if context.coordinator.lastMenuTrigger != menuTrigger {
            context.coordinator.lastMenuTrigger = menuTrigger
            uiView.showMenuAtCenter()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}

private final class TapeCanvasUIView: UIView {
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

    fileprivate struct StoredSession: Codable {
        var segments: [StoredSegment]
        var contentOffset: StoredPoint
        var savedAt: TimeInterval
    }

    fileprivate struct StoredSegment: Codable {
        var id: Int
        var strokes: [StoredStroke]
    }

    fileprivate struct StoredStroke: Codable {
        var points: [StoredPoint]
        var color: StoredColor
        var lineWidth: CGFloat
    }

    fileprivate struct StoredPoint: Codable {
        var x: CGFloat
        var y: CGFloat
    }

    fileprivate struct StoredColor: Codable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat
    }

    private var segments: [Int: Segment] = [:]
    private var currentStroke: Stroke?
    private var currentStrokeSegmentId: Int?
    private var contentOffset: CGPoint = .zero
    private var displayLink: CADisplayLink?
    private var autoScrollLink: CADisplayLink?
    private var lastTouchLocation: CGPoint?
    private let autoScrollSpeed: CGFloat = 90
    private var decelVelocity: CGFloat = 0
    private let decelRate: CGFloat = 0.92
    private let velocityStopThreshold: CGFloat = 4
    private let backgroundColorTone = UIColor(white: 0.98, alpha: 1.0)
    private var baseStrokeColor: UIColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
    private let graphiteColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
    private var colorPalette: [UIColor] = [
        UIColor(red: 0.05, green: 0.9, blue: 1.0, alpha: 0.95),  // neon cyan
        UIColor(red: 0.96, green: 0.2, blue: 0.84, alpha: 0.95),  // neon magenta
        UIColor(red: 0.2, green: 1.0, blue: 0.45, alpha: 0.95),   // neon green
        UIColor(red: 0.99, green: 0.78, blue: 0.1, alpha: 0.95),  // neon yellow
        UIColor(red: 0.55, green: 0.35, blue: 1.0, alpha: 0.95)   // neon purple
    ]
    private var colorIndex: Int = 0
    private var baseLineWidth: CGFloat = 2.2
    private var isEraser: Bool = false
    private var noiseTile: UIImage?
    private let menuView = UIView()
    private let menuBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let menuTintOverlay = UIView()
    private let colorMenuView = UIView()
    private let colorMenuBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let colorMenuTintOverlay = UIView()
    private let colorButton = UIButton(type: .system)
    private let widthButton = UIButton(type: .system)
    private let eraserButton = UIButton(type: .system)
    private let proButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let sparklesButton = UIButton(type: .system)
    private var menuCenter: CGPoint = .zero
    private let colorSubPalette: [UIColor] = [
        UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9),   // graphite
        UIColor(red: 0.12, green: 0.9, blue: 0.98, alpha: 0.95),   // neon cyan 2
        UIColor(red: 1.0, green: 0.35, blue: 0.78, alpha: 0.95),   // neon pink
        UIColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 0.95),   // neon violet
        UIColor(red: 0.98, green: 0.42, blue: 0.12, alpha: 0.95),  // neon orange
        UIColor(red: 0.22, green: 1.0, blue: 0.85, alpha: 0.95)    // neon mint
    ]
    private var colorButtons: [UIButton] = []
    private var didLoadSession: Bool = false
    private var telemetry = Telemetry()
    private let freeHistoryEnabled = true
    private let freeHistoryFileName = "session_free.json"
    private let proHistoryFileName = "session.json"
    private let freeHistoryMaxAgeHours: Double = 24
    private var segmentWidth: CGFloat = 1
    private let toastLabel = UILabel()
    private var toastTimer: Timer?
    var isProUser: Bool = false {
        didSet {
            if !didLoadSession {
                loadSession()
            }
            updateProButtonAppearance()
        }
    }
    var onPurchasePro: (() async -> PurchaseOutcome)?
    var onRestorePurchases: (() async -> Void)?
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(tapRecognizer)
        configureMenu()
        configureToast()
        registerForAppLifecycle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(tapRecognizer)
        configureMenu()
        configureToast()
        registerForAppLifecycle()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
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

        let tailCount = min(16, max(0, smoothed.count - 1))
        let tailStart = max(0, smoothed.count - 1 - tailCount)
        let minScale: CGFloat = 0.2

        var filteredScale: CGFloat = 1.0
        let smoothingAlpha: CGFloat = 0.18
        for i in 1..<smoothed.count {
            let start = smoothed[i - 1]
            let end = smoothed[i]
            let targetScale = targetWidthScale(for: stroke, index: i)
            filteredScale = filteredScale + (targetScale - filteredScale) * smoothingAlpha
            let width = stroke.lineWidth * filteredScale
            let tailScale: CGFloat
            if i >= tailStart && tailCount > 0 {
                let t = CGFloat(smoothed.count - 1 - i) / CGFloat(tailCount)
                tailScale = max(minScale, t)
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
        if !menuView.isHidden { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        stopDeceleration()
        let location = touch.location(in: self)
        lastTouchLocation = location
        let color = isEraser ? backgroundColorTone : baseStrokeColor
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
    }

    @objc private func appWillResignActive() {
        persistSessionIfNeeded()
    }

    func persistSessionIfNeeded() {
        if isProUser {
            saveSession()
        } else if freeHistoryEnabled {
            saveSession()
        } else {
            clearSavedSession(forPro: false)
        }
    }

    private func saveSession() {
        let storedSegments = segments.values.map { segment in
            StoredSegment(
                id: segment.id,
                strokes: segment.strokes.map { stroke in
                    StoredStroke(
                        points: stroke.points.map { StoredPoint(x: $0.x, y: $0.y) },
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
            let data = try JSONEncoder().encode(storedSession)
            try data.write(to: sessionURL(forPro: isProUser), options: Data.WritingOptions.atomic)
        } catch {
            // Best-effort persistence; ignore errors in MVP.
        }
    }

    private func loadSession() {
        didLoadSession = true
        do {
            let data = try Data(contentsOf: sessionURL(forPro: isProUser))
            let storedSession = try JSONDecoder().decode(StoredSession.self, from: data)
            if !isProUser && freeHistoryEnabled {
                let ageHours = (Date().timeIntervalSince1970 - storedSession.savedAt) / 3600
                if ageHours > freeHistoryMaxAgeHours {
                    clearSavedSession(forPro: false)
                    return
                }
            }
            segments = Dictionary(uniqueKeysWithValues: storedSession.segments.map { stored in
                let strokes = stored.strokes.map { stroke in
                    Stroke(
                        points: stroke.points.map { CGPoint(x: $0.x, y: $0.y) },
                        times: [],
                        color: stroke.color.toUIColor(),
                        lineWidth: stroke.lineWidth
                    )
                }
                return (stored.id, Segment(id: stored.id, strokes: strokes))
            })
            contentOffset = CGPoint(x: storedSession.contentOffset.x, y: storedSession.contentOffset.y)
            setNeedsDisplay()
        } catch {
            // No saved session or decode failure.
        }
    }

    private func clearSavedSession(forPro: Bool) {
        try? FileManager.default.removeItem(at: sessionURL(forPro: forPro))
    }

    private func sessionURL(forPro: Bool) -> URL {
        let directory: URL
        if forPro {
            directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        } else {
            directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        }
        let fileName = forPro ? proHistoryFileName : freeHistoryFileName
        return directory.appendingPathComponent(fileName)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        segmentWidth = max(1, bounds.width * 1.5)
        updateSegmentsIfNeeded()
        let size: CGFloat = 192
        layoutMenuSlots(
            view: menuView,
            size: size,
            radius: 52,
            slots: [colorButton, widthButton, settingsButton, proButton, exportButton, sparklesButton]
        )
        layoutMenuSlots(
            view: colorMenuView,
            size: size,
            radius: 52,
            slots: colorButtons.map { Optional($0) }
        )
        menuBlurView.frame = menuView.bounds
        menuTintOverlay.frame = menuView.bounds
        menuBlurView.layer.cornerRadius = menuView.layer.cornerRadius
        menuBlurView.layer.masksToBounds = true
        menuTintOverlay.layer.cornerRadius = menuView.layer.cornerRadius
        menuTintOverlay.layer.masksToBounds = true
        colorMenuBlurView.frame = colorMenuView.bounds
        colorMenuTintOverlay.frame = colorMenuView.bounds
        colorMenuBlurView.layer.cornerRadius = colorMenuView.layer.cornerRadius
        colorMenuBlurView.layer.masksToBounds = true
        colorMenuTintOverlay.layer.cornerRadius = colorMenuView.layer.cornerRadius
        colorMenuTintOverlay.layer.masksToBounds = true

        let toastWidth = min(bounds.width - 32, 220)
        toastLabel.frame = CGRect(
            x: (bounds.width - toastWidth) / 2,
            y: bounds.height - 96,
            width: toastWidth,
            height: 36
        )
    }

    private func drawNoise(in context: CGContext, rect: CGRect) {
        if noiseTile == nil {
            noiseTile = makeNoiseTile(size: 96)
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
        return renderer.image { ctx in
            let base = UIColor(white: 1.0, alpha: 0.02)
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            for _ in 0..<250 {
                let x = CGFloat.random(in: 0..<size)
                let y = CGFloat.random(in: 0..<size)
                let alpha = CGFloat.random(in: 0.015...0.05)
                let dotColor = UIColor(white: 0.0, alpha: alpha)
                ctx.cgContext.setFillColor(dotColor.cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
            }
        }
    }

    private func configureMenu() {
        menuView.backgroundColor = .clear
        menuView.layer.cornerRadius = 80
        menuView.layer.shadowColor = UIColor.black.cgColor
        menuView.layer.shadowOpacity = 0.1
        menuView.layer.shadowRadius = 10
        menuView.layer.shadowOffset = CGSize(width: 0, height: 4)
        menuView.layer.zPosition = 1000
        menuView.layer.borderWidth = 0
        menuView.isHidden = true
        menuView.isUserInteractionEnabled = true

        menuBlurView.isHidden = true
        menuTintOverlay.isHidden = true

        configureTapButton(
            colorButton,
            imageSystemName: "circle.fill",
            tintColor: graphiteColor,
            action: { [weak self] in self?.showColorMenu() }
        )
        colorButton.setImage(makeColorDotsIcon(), for: .normal)
        configureTapButton(
            widthButton,
            imageSystemName: "line.3.horizontal",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleWidthTap() }
        )
        widthButton.setImage(makeLineWidthIcon(), for: .normal)
        configureTapButton(
            eraserButton,
            imageSystemName: "eraser",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleEraserTap() }
        )
        configureTapButton(
            proButton,
            imageSystemName: "crown",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleProTap() }
        )
        configureTapButton(
            exportButton,
            imageSystemName: "square.and.arrow.up",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleExportTap() }
        )
        configureTapButton(
            settingsButton,
            imageSystemName: "gearshape",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleSettingsTap() }
        )
        configureTapButton(
            sparklesButton,
            imageSystemName: "sparkles",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleSparklesTap() }
        )

        [colorButton, widthButton, settingsButton, proButton, exportButton, sparklesButton].forEach {
            $0.backgroundColor = .clear
            $0.layer.cornerRadius = 0
            $0.frame.size = CGSize(width: 72, height: 72)
            menuView.addSubview($0)
        }
        updateProButtonAppearance()

        addSubview(menuView)
        configureColorMenu()
    }

    private func configureColorMenu() {
        colorMenuView.backgroundColor = .clear
        colorMenuView.layer.cornerRadius = 80
        colorMenuView.layer.shadowColor = UIColor.black.cgColor
        colorMenuView.layer.shadowOpacity = 0.1
        colorMenuView.layer.shadowRadius = 10
        colorMenuView.layer.shadowOffset = CGSize(width: 0, height: 4)
        colorMenuView.layer.zPosition = 1001
        colorMenuView.layer.borderWidth = 0
        colorMenuView.isHidden = true
        colorMenuView.isUserInteractionEnabled = true

        colorMenuBlurView.isHidden = true
        colorMenuTintOverlay.isHidden = true

        colorButtons = colorSubPalette.enumerated().map { index, color in
            let button = UIButton(type: .system)
            configureTapButton(
                button,
                imageSystemName: "circle.fill",
                tintColor: color,
                action: { [weak self] in self?.handleColorSelect(index: index) }
            )
            colorMenuView.addSubview(button)
            return button
        }
        colorButtons.forEach {
            $0.backgroundColor = .clear
            $0.layer.cornerRadius = 0
            $0.frame.size = CGSize(width: 72, height: 72)
        }

        addSubview(colorMenuView)
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
        menuCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        colorMenuView.isHidden = true
        showMenu(animated: true)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard !menuView.isHidden || !colorMenuView.isHidden else { return }
        let location = recognizer.location(in: self)
        if !menuView.frame.contains(location) && !colorMenuView.frame.contains(location) {
            hideMenuAfterSelection()
        }
    }

    private func handleColorSelect(index: Int) {
        guard colorSubPalette.indices.contains(index) else { return }
        baseStrokeColor = colorSubPalette[index]
        if isEraser {
            isEraser = false
            eraserButton.tintColor = UIColor.black.withAlphaComponent(0.7)
        }
        hideMenuAfterSelection()
    }

    @objc private func handleWidthTap() {
        switch baseLineWidth {
        case ..<3:
            baseLineWidth = 4.2
        case ..<5:
            baseLineWidth = 6.2
        default:
            baseLineWidth = 2.2
        }
        hideMenuAfterSelection()
    }

    @objc private func handleEraserTap() {
        isEraser.toggle()
        eraserButton.tintColor = isEraser ? UIColor.systemBlue : UIColor.black.withAlphaComponent(0.7)
        hideMenuAfterSelection()
    }

    @objc private func handleProTap() {
        guard !isProUser else { return }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await onPurchasePro?()
            switch outcome {
            case .success:
                showToast(text: "Pro activated")
            case .cancelled:
                showToast(text: "Purchase cancelled")
            case .pending:
                showToast(text: "Purchase pending")
            case .productNotFound:
                showToast(text: "Product not available")
            case .failed:
                showToast(text: "Purchase failed")
            case .none:
                break
            }
            updateProButtonAppearance()
            hideMenuAfterSelection()
        }
    }

    @objc private func handleExportTap() {
        guard isProUser else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            hideMenuAfterSelection()
            return
        }
        exportVisiblePDF()
        hideMenuAfterSelection()
    }

    @objc private func handleSettingsTap() {
        Task { [weak self] in
            guard let self else { return }
            showToast(text: "Restoring…")
            await onRestorePurchases?()
            showToast(text: isProUser ? "Restored" : "Nothing to restore")
            hideMenuAfterSelection()
        }
    }

    @objc private func handleSparklesTap() {
        // Placeholder for future feature.
        hideMenuAfterSelection()
    }

    private func exportVisiblePDF() {
        let pageBounds = bounds
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(pageBounds)
            cgContext.translateBy(x: -contentOffset.x, y: -contentOffset.y)
            drawStrokesForExport(in: cgContext)
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("InfinityPaper.pdf")
        do {
            try data.write(to: tempURL, options: Data.WritingOptions.atomic)
            presentShare(url: tempURL)
        } catch {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func presentShare(url: URL) {
        guard let controller = findViewController() else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = self
        activity.popoverPresentationController?.sourceRect = CGRect(x: menuCenter.x, y: menuCenter.y, width: 1, height: 1)
        controller.present(activity, animated: true)
    }

    private func updateProButtonAppearance() {
        proButton.tintColor = isProUser
            ? UIColor(red: 0.93, green: 0.74, blue: 0.2, alpha: 1.0)
            : graphiteColor
    }

    private func configureTapButton(
        _ button: UIButton,
        imageSystemName: String,
        tintColor: UIColor,
        action: @escaping () -> Void
    ) {
        button.setImage(UIImage(systemName: imageSystemName), for: .normal)
        button.tintColor = tintColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowRadius = 2
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.masksToBounds = false
        button.addAction(UIAction { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }, for: .touchUpInside)
    }

    private func makeColorDotsIcon(size: CGFloat = 26) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let dotDiameter = size * 0.24
            let spacing = size * 0.08
            let totalWidth = dotDiameter * 3 + spacing * 2
            let startX = (size - totalWidth) / 2
            let y = (size - dotDiameter) / 2
            let colors: [UIColor] = [.red, .green, .blue]
            for (index, color) in colors.enumerated() {
                let x = startX + CGFloat(index) * (dotDiameter + spacing)
                let rect = CGRect(x: x, y: y, width: dotDiameter, height: dotDiameter)
                context.cgContext.setFillColor(color.cgColor)
                context.cgContext.fillEllipse(in: rect)
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private func makeLineWidthIcon(size: CGFloat = 26) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let startX = size * 0.18
            let endX = size * 0.82
            let centerY = size / 2
            let offsets: [CGFloat] = [-size * 0.18, 0, size * 0.18]
            let widths: [CGFloat] = [1.2, 2.4, 3.8]
            context.cgContext.setStrokeColor(graphiteColor.cgColor)
            context.cgContext.setLineCap(.round)
            for (offset, width) in zip(offsets, widths) {
                context.cgContext.setLineWidth(width)
                context.cgContext.beginPath()
                context.cgContext.move(to: CGPoint(x: startX, y: centerY + offset))
                context.cgContext.addLine(to: CGPoint(x: endX, y: centerY + offset))
                context.cgContext.strokePath()
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private func layoutMenuSlots(view: UIView, size: CGFloat, radius: CGFloat, slots: [UIButton?]) {
        guard !slots.isEmpty else { return }
        view.frame = CGRect(x: menuCenter.x - size / 2, y: menuCenter.y - size / 2, width: size, height: size)
        let center = CGPoint(x: size / 2, y: size / 2)
        let angles: [CGFloat] = [
            -CGFloat.pi / 2,
            -CGFloat.pi / 6,
            CGFloat.pi / 6,
            CGFloat.pi / 2,
            CGFloat.pi * 5 / 6,
            -CGFloat.pi * 5 / 6
        ]
        for (index, button) in slots.enumerated() {
            guard let button else { continue }
            let angle = angles[index % angles.count]
            let x = center.x + radius * cos(angle) - 36
            let y = center.y + radius * sin(angle) - 36
            button.frame = CGRect(x: x, y: y, width: 72, height: 72)
        }
    }

    private func showColorMenu() {
        menuView.isHidden = true
        colorMenuView.isHidden = false
        bringSubviewToFront(colorMenuView)
        setNeedsLayout()
        colorMenuView.alpha = 0
        colorMenuView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.colorMenuView.alpha = 1
            self.colorMenuView.transform = .identity
        }
    }

    private func hideMenuAfterSelection() {
        hideMenu(animated: true)
    }

    private func configureToast() {
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = UIColor(white: 0.1, alpha: 0.9)
        toastLabel.backgroundColor = UIColor(white: 1.0, alpha: 0.9)
        toastLabel.layer.cornerRadius = 10
        toastLabel.layer.masksToBounds = true
        toastLabel.alpha = 0
        addSubview(toastLabel)
    }

    private func showToast(text: String) {
        toastTimer?.invalidate()
        toastLabel.text = text
        bringSubviewToFront(toastLabel)
        UIView.animate(withDuration: 0.15) {
            self.toastLabel.alpha = 1
        }
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.2) {
                self?.toastLabel.alpha = 0
            }
        }
    }

    private func showMenu(animated: Bool) {
        menuView.isHidden = false
        bringSubviewToFront(menuView)
        setNeedsLayout()
        if animated {
            menuView.alpha = 0
            menuView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.menuView.alpha = 1
                self.menuView.transform = .identity
            }
        } else {
            menuView.alpha = 1
            menuView.transform = .identity
        }
    }

    private func hideMenu(animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
                self.menuView.alpha = 0
                self.menuView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                self.colorMenuView.alpha = 0
                self.colorMenuView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            } completion: { _ in
                self.menuView.isHidden = true
                self.colorMenuView.isHidden = true
                self.menuView.alpha = 1
                self.menuView.transform = .identity
                self.colorMenuView.alpha = 1
                self.colorMenuView.transform = .identity
            }
        } else {
            menuView.isHidden = true
            colorMenuView.isHidden = true
            menuView.alpha = 1
            menuView.transform = .identity
            colorMenuView.alpha = 1
            colorMenuView.transform = .identity
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
    func toStoredColor() -> TapeCanvasUIView.StoredColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return TapeCanvasUIView.StoredColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension TapeCanvasUIView.StoredColor {
    func toUIColor() -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
