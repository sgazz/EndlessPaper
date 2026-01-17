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

    var body: some View {
        TapeCanvasView(
            isProUser: proStatus.isPro,
            scenePhase: scenePhase,
            purchasePro: {
                await proStatus.purchasePro()
            }
        )
            .ignoresSafeArea()
    }
}

private struct TapeCanvasView: View {
    let isProUser: Bool
    let scenePhase: ScenePhase
    let purchasePro: () async -> Bool

    var body: some View {
        TapeCanvasRepresentable(
            isProUser: isProUser,
            scenePhase: scenePhase,
            purchasePro: purchasePro
        )
            .ignoresSafeArea()
    }
}

private struct TapeCanvasRepresentable: UIViewRepresentable {
    let isProUser: Bool
    let scenePhase: ScenePhase
    let purchasePro: () async -> Bool

    final class Coordinator {
        weak var view: TapeCanvasUIView?
    }

    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView()
        view.backgroundColor = UIColor(white: 0.98, alpha: 1.0)
        view.isProUser = isProUser
        view.onPurchasePro = purchasePro
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: TapeCanvasUIView, context: Context) {
        uiView.isProUser = isProUser
        uiView.onPurchasePro = purchasePro
        if scenePhase == .background {
            uiView.persistSessionIfNeeded()
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
    private var decelVelocity: CGFloat = 0
    private let decelRate: CGFloat = 0.92
    private let velocityStopThreshold: CGFloat = 4
    private let backgroundColorTone = UIColor(white: 0.98, alpha: 1.0)
    private var baseStrokeColor: UIColor = UIColor.black.withAlphaComponent(0.9)
    private var colorPalette: [UIColor] = [
        UIColor(red: 0.05, green: 0.9, blue: 1.0, alpha: 0.95),  // neon cyan
        UIColor(red: 0.96, green: 0.2, blue: 0.84, alpha: 0.95),  // neon magenta
        UIColor(red: 0.2, green: 1.0, blue: 0.45, alpha: 0.95),   // neon green
        UIColor(red: 0.99, green: 0.78, blue: 0.1, alpha: 0.95),  // neon yellow
        UIColor(red: 0.55, green: 0.35, blue: 1.0, alpha: 0.95)   // neon purple
    ]
    private var colorIndex: Int = 0
    private var colorButtons: [HoldButton] = []
    private var baseLineWidth: CGFloat = 2.2
    private var isEraser: Bool = false
    private var noiseTile: UIImage?
    private let menuView = UIView()
    private let colorMenuView = UIView()
    private let colorButton = HoldButton(type: .system)
    private let widthButton = HoldButton(type: .system)
    private let eraserButton = HoldButton(type: .system)
    private let proButton = HoldButton(type: .system)
    private let exportButton = HoldButton(type: .system)
    private var menuCenter: CGPoint = .zero
    private var didLoadSession: Bool = false
    private var telemetry = Telemetry()
    private let freeHistoryEnabled = true
    private let freeHistoryFileName = "session_free.json"
    private let proHistoryFileName = "session.json"
    private let freeHistoryMaxAgeHours: Double = 24
    private var segmentWidth: CGFloat = 1
    var isProUser: Bool = false {
        didSet {
            if !didLoadSession {
                loadSession()
            }
            updateProButtonAppearance()
        }
    }
    var onPurchasePro: (() async -> Bool)?
    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        return recognizer
    }()
    private lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.minimumPressDuration = 0.5
        recognizer.cancelsTouchesInView = false
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
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(tapRecognizer)
        configureMenu()
        registerForAppLifecycle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(tapRecognizer)
        configureMenu()
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
        context.setLineWidth(stroke.lineWidth)
        let path = CGMutablePath()
        let first = toViewPoint(stroke.points[0])
        path.move(to: first)
        for point in stroke.points.dropFirst() {
            path.addLine(to: toViewPoint(point))
        }
        context.addPath(path)
        context.strokePath()
    }

    private func drawStrokeWorld(_ stroke: Stroke, in context: CGContext) {
        guard stroke.points.count > 1 else { return }
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineWidth(stroke.lineWidth)
        let path = CGMutablePath()
        let first = stroke.points[0]
        path.move(to: first)
        for point in stroke.points.dropFirst() {
            path.addLine(to: point)
        }
        context.addPath(path)
        context.strokePath()
    }

    private func toWorldPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x + contentOffset.x, y: viewPoint.y + contentOffset.y)
    }

    private func toViewPoint(_ worldPoint: CGPoint) -> CGPoint {
        CGPoint(x: worldPoint.x - contentOffset.x, y: worldPoint.y - contentOffset.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        guard longPressRecognizer.state == .possible || longPressRecognizer.state == .failed else { return }
        if !menuView.isHidden { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        stopDeceleration()
        let location = touch.location(in: self)
        let color = isEraser ? backgroundColorTone : baseStrokeColor
        currentStroke = Stroke(
            points: [toWorldPoint(location)],
            times: [touch.timestamp],
            color: color,
            lineWidth: baseLineWidth
        )
        currentStrokeSegmentId = segmentId(forWorldX: toWorldPoint(location).x)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        guard let touch = touches.first, touches.count == 1 else { return }
        let location = touch.location(in: self)
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
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentStroke = nil
        currentStrokeSegmentId = nil
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
        layoutMenu(view: menuView, size: size, radius: 52, buttons: [colorButton, widthButton, eraserButton, proButton, exportButton])
        layoutMenu(view: colorMenuView, size: size, radius: 52, buttons: colorButtons)
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
        menuView.backgroundColor = UIColor(white: 1.0, alpha: 0.92)
        menuView.layer.cornerRadius = 80
        menuView.layer.shadowColor = UIColor.black.cgColor
        menuView.layer.shadowOpacity = 0.1
        menuView.layer.shadowRadius = 10
        menuView.layer.shadowOffset = CGSize(width: 0, height: 4)
        menuView.layer.zPosition = 1000
        menuView.isHidden = true
        menuView.isUserInteractionEnabled = true

        configureHoldButton(
            colorButton,
            imageSystemName: "circle.fill",
            tintColor: baseStrokeColor,
            action: { [weak self] in self?.showColorMenu() }
        )
        configureHoldButton(
            widthButton,
            imageSystemName: "line.3.horizontal",
            tintColor: UIColor.black.withAlphaComponent(0.7),
            action: { [weak self] in self?.handleWidthTap() }
        )
        configureHoldButton(
            eraserButton,
            imageSystemName: "eraser",
            tintColor: UIColor.black.withAlphaComponent(0.7),
            action: { [weak self] in self?.handleEraserTap() }
        )
        configureHoldButton(
            proButton,
            imageSystemName: "crown",
            tintColor: UIColor.black.withAlphaComponent(0.7),
            action: { [weak self] in self?.handleProTap() }
        )
        configureHoldButton(
            exportButton,
            imageSystemName: "square.and.arrow.up",
            tintColor: UIColor.black.withAlphaComponent(0.7),
            action: { [weak self] in self?.handleExportTap() }
        )

        [colorButton, widthButton, eraserButton, proButton, exportButton].forEach {
            $0.backgroundColor = UIColor(white: 1.0, alpha: 0.9)
            $0.layer.cornerRadius = 36
            $0.frame.size = CGSize(width: 72, height: 72)
            menuView.addSubview($0)
        }
        updateProButtonAppearance()

        addSubview(menuView)

        configureColorMenu()
    }

    private func configureColorMenu() {
        colorMenuView.backgroundColor = UIColor(white: 1.0, alpha: 0.92)
        colorMenuView.layer.cornerRadius = 80
        colorMenuView.layer.shadowColor = UIColor.black.cgColor
        colorMenuView.layer.shadowOpacity = 0.1
        colorMenuView.layer.shadowRadius = 10
        colorMenuView.layer.shadowOffset = CGSize(width: 0, height: 4)
        colorMenuView.layer.zPosition = 1001
        colorMenuView.isHidden = true
        colorMenuView.isUserInteractionEnabled = true

        colorButtons = colorPalette.enumerated().map { index, color in
            let button = HoldButton(type: .system)
            configureHoldButton(
                button,
                imageSystemName: "circle.fill",
                tintColor: color,
                action: { [weak self] in self?.handleColorSelect(index: index) }
            )
            colorMenuView.addSubview(button)
            return button
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

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            menuCenter = recognizer.location(in: self)
            menuView.isHidden = false
            bringSubviewToFront(menuView)
            setNeedsLayout()
        case .ended, .cancelled, .failed:
            break
        default:
            break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard !menuView.isHidden || !colorMenuView.isHidden else { return }
        let location = recognizer.location(in: self)
        if !menuView.frame.contains(location) && !colorMenuView.frame.contains(location) {
            hideMenuAfterSelection()
        }
    }

    private func handleColorSelect(index: Int) {
        guard colorPalette.indices.contains(index) else { return }
        colorIndex = index
        baseStrokeColor = colorPalette[index]
        if isEraser {
            isEraser = false
            eraserButton.tintColor = UIColor.black.withAlphaComponent(0.7)
        }
        colorButton.tintColor = baseStrokeColor
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
            _ = await onPurchasePro?()
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
        proButton.tintColor = isProUser ? UIColor.systemGreen : UIColor.black.withAlphaComponent(0.7)
    }

    private func configureHoldButton(
        _ button: HoldButton,
        imageSystemName: String,
        tintColor: UIColor,
        action: @escaping () -> Void
    ) {
        button.setImage(UIImage(systemName: imageSystemName), for: .normal)
        button.tintColor = tintColor
        button.onHold = action
        button.onHighlight = { [weak button] isHighlighted in
            button?.alpha = isHighlighted ? 0.85 : 1.0
        }
    }

    private func showColorMenu() {
        colorMenuView.isHidden = false
        bringSubviewToFront(colorMenuView)
        setNeedsLayout()
    }

    private func layoutMenu(view: UIView, size: CGFloat, radius: CGFloat, buttons: [UIButton]) {
        guard !buttons.isEmpty else { return }
        view.frame = CGRect(x: menuCenter.x - size / 2, y: menuCenter.y - size / 2, width: size, height: size)
        let center = CGPoint(x: size / 2, y: size / 2)
        let angles: [CGFloat] = [-CGFloat.pi / 2, -CGFloat.pi * 0.1, CGFloat.pi * 0.3, CGFloat.pi * 0.7, CGFloat.pi * 1.1]
        for (index, button) in buttons.enumerated() {
            let angle = angles[index % angles.count]
            let x = center.x + radius * cos(angle) - 36
            let y = center.y + radius * sin(angle) - 36
            button.frame = CGRect(x: x, y: y, width: 72, height: 72)
        }
    }

    private func hideMenuAfterSelection() {
        menuView.isHidden = true
        colorMenuView.isHidden = true
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

private final class HoldButton: UIButton {
    var onHold: (() -> Void)?
    var onHighlight: ((Bool) -> Void)?
    private let feedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        recognizer.minimumPressDuration = 0.15
        recognizer.allowableMovement = 30
        addGestureRecognizer(recognizer)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let extended = bounds.insetBy(dx: -12, dy: -12)
        return extended.contains(point)
    }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onHighlight?(true)
            feedback.selectionChanged()
        case .ended:
            onHighlight?(false)
            let location = recognizer.location(in: self)
            if bounds.contains(location) {
                onHold?()
            }
        case .cancelled, .failed:
            onHighlight?(false)
        default:
            break
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
