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
    var body: some View {
        TapeCanvasRepresentable()
    }
}

private struct TapeCanvasRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView()
        view.backgroundColor = UIColor(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0)
        return view
    }

    func updateUIView(_ uiView: TapeCanvasUIView, context: Context) {
        // no-op
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
    private let backgroundColorTone = UIColor(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0, alpha: 1.0)
    private var baseStrokeColor: UIColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
    private let graphiteColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
    private var baseLineWidth: CGFloat = 2.2
    private var isEraser: Bool = false
    private var noiseTile: UIImage?
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
    private let sessionFileName = "session.json"
    private var segmentWidth: CGFloat = 1
    private let toastLabel = UILabel()
    private var toastTimer: Timer?
    private let menuTriggerButton = UIButton(type: .custom)
    private let menuTriggerKeyX = "menuTrigger.center.x"
    private let menuTriggerKeyY = "menuTrigger.center.y"
    private lazy var radialMenu = RadialMenuController(
        host: self,
        graphiteColor: graphiteColor,
        colorSubPalette: primaryColorPalette,
        getIsEraser: { [weak self] in self?.isEraser ?? false },
        setIsEraser: { [weak self] value in self?.isEraser = value },
        setBaseStrokeColor: { [weak self] color in self?.baseStrokeColor = color },
        cycleLineWidth: { [weak self] in self?.cycleLineWidth() },
        onExport: { [weak self] in self?.exportVisiblePDF() },
        onSettings: { [weak self] in self?.showToast(text: "Settings") },
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureCommon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCommon()
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

        let tailCount = min(20, max(0, smoothed.count - 1))
        let tailStart = max(0, smoothed.count - 1 - tailCount)
        let minScale: CGFloat = 0.15

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
        saveSession()
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
            try data.write(to: sessionURL(), options: Data.WritingOptions.atomic)
        } catch {
            // Best-effort persistence; ignore errors in MVP.
        }
    }

    private func loadSession() {
        do {
            let data = try Data(contentsOf: sessionURL())
            let storedSession = try JSONDecoder().decode(StoredSession.self, from: data)
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

    private func sessionURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(sessionFileName)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        segmentWidth = max(1, bounds.width * 1.5)
        updateSegmentsIfNeeded()
        radialMenu.layout(in: bounds)
        let triggerSize: CGFloat = 132
        let defaultCenter = CGPoint(
            x: safeAreaInsets.left + 12 + triggerSize / 2,
            y: safeAreaInsets.top + 12 + triggerSize / 2
        )
        menuTriggerButton.frame.size = CGSize(width: triggerSize, height: triggerSize)
        menuTriggerButton.center = clampMenuTrigger(point: loadMenuTriggerPosition() ?? defaultCenter)
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
            let base = backgroundColorTone.withAlphaComponent(0.02)
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
        // Placeholder for future feature.
    }

    private func exportVisiblePDF() {
        let pageBounds = bounds
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(backgroundColorTone.cgColor)
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
        let menuCenter = radialMenu.menuCenter
        activity.popoverPresentationController?.sourceRect = CGRect(x: menuCenter.x, y: menuCenter.y, width: 1, height: 1)
        controller.present(activity, animated: true)
    }

    private func configureToast() {
        toastLabel.textAlignment = .center
        toastLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        toastLabel.textColor = UIColor(white: 0.1, alpha: 0.9)
        toastLabel.backgroundColor = backgroundColorTone.withAlphaComponent(0.92)
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

    private func configureCommon() {
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(tapRecognizer)
        configureMenuTriggerButton()
        _ = radialMenu
        configureToast()
        registerForAppLifecycle()
        loadSession()
    }

    private func cycleLineWidth() {
        switch baseLineWidth {
        case ..<3:
            baseLineWidth = 4.2
        case ..<5:
            baseLineWidth = 6.2
        default:
            baseLineWidth = 2.2
        }
    }

    private func applyPalette(index: Int) {
        let palette = index == 0 ? primaryColorPalette : achievementColorPalette
        radialMenu.updateColorPalette(palette)
        if let lastPaletteIndex, lastPaletteIndex != index {
            let message = index == 0 ? "Original colors restored" : "New colors unlocked"
            showToast(text: message)
        }
        lastPaletteIndex = index
    }

    private func clampMenuTrigger(point: CGPoint) -> CGPoint {
        let size: CGFloat = 132
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

    private func configureMenuTriggerButton() {
        menuTriggerButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
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
            menuTriggerButton.setTitleColor(UIColor.black.withAlphaComponent(0.8), for: .normal)
            menuTriggerButton.titleLabel?.font = UIFont.systemFont(ofSize: 36, weight: .medium)
        }
        menuTriggerButton.accessibilityLabel = "Open radial menu"
        menuTriggerButton.addAction(UIAction { [weak self] _ in
            self?.showMenuAtCenter()
        }, for: .touchUpInside)
        menuTriggerButton.addGestureRecognizer(menuTriggerPan)
        menuTriggerButton.isUserInteractionEnabled = true
        addSubview(menuTriggerButton)
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
