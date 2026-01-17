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

    private struct StoredSession: Codable {
        var strokes: [StoredStroke]
        var contentOffset: StoredPoint
        var savedAt: TimeInterval
    }

    private struct StoredStroke: Codable {
        var points: [StoredPoint]
        var color: StoredColor
        var lineWidth: CGFloat
    }

    private struct StoredPoint: Codable {
        var x: CGFloat
        var y: CGFloat
    }

    private struct StoredColor: Codable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var alpha: CGFloat
    }

    private var strokes: [Stroke] = []
    private var currentStroke: Stroke?
    private var contentOffset: CGPoint = .zero
    private var displayLink: CADisplayLink?
    private var decelVelocity: CGFloat = 0
    private let decelRate: CGFloat = 0.92
    private let velocityStopThreshold: CGFloat = 4
    private let backgroundColorTone = UIColor(white: 0.98, alpha: 1.0)
    private var baseStrokeColor: UIColor = UIColor.black.withAlphaComponent(0.9)
    private var baseLineWidth: CGFloat = 2.2
    private var isEraser: Bool = false
    private var noiseTile: UIImage?
    private let menuView = UIView()
    private let colorButton = UIButton(type: .system)
    private let widthButton = UIButton(type: .system)
    private let eraserButton = UIButton(type: .system)
    private let proButton = UIButton(type: .system)
    private var menuCenter: CGPoint = .zero
    private var didLoadSession: Bool = false
    private var telemetry = Telemetry()
    private let freeHistoryEnabled = true
    private let freeHistoryFileName = "session_free.json"
    private let proHistoryFileName = "session.json"
    private let freeHistoryMaxAgeHours: Double = 12
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
        return recognizer
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(longPressRecognizer)
        configureMenu()
        registerForAppLifecycle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(longPressRecognizer)
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

        for stroke in strokes {
            drawStroke(stroke, in: context)
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

    private func toWorldPoint(_ viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: viewPoint.x + contentOffset.x, y: viewPoint.y + contentOffset.y)
    }

    private func toViewPoint(_ worldPoint: CGPoint) -> CGPoint {
        CGPoint(x: worldPoint.x - contentOffset.x, y: worldPoint.y - contentOffset.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard panRecognizer.state == .possible || panRecognizer.state == .failed else { return }
        guard longPressRecognizer.state == .possible || longPressRecognizer.state == .failed else { return }
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
        guard let stroke = currentStroke else { return }
        strokes.append(stroke)
        telemetry.recordStroke(points: stroke.points.count)
        currentStroke = nil
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentStroke = nil
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
        let storedStrokes = strokes.map { stroke in
            StoredStroke(
                points: stroke.points.map { StoredPoint(x: $0.x, y: $0.y) },
                color: stroke.color.toStoredColor(),
                lineWidth: stroke.lineWidth
            )
        }
        let storedSession = StoredSession(
            strokes: storedStrokes,
            contentOffset: StoredPoint(x: contentOffset.x, y: contentOffset.y),
            savedAt: Date().timeIntervalSince1970
        )
        do {
            let data = try JSONEncoder().encode(storedSession)
            try data.write(to: sessionURL(forPro: isProUser), options: [.atomic])
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
            strokes = storedSession.strokes.map { stored in
                Stroke(
                    points: stored.points.map { CGPoint(x: $0.x, y: $0.y) },
                    times: [],
                    color: stored.color.toUIColor(),
                    lineWidth: stored.lineWidth
                )
            }
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

    private func drawNoise(in context: CGContext, rect: CGRect) {
        if noiseTile == nil {
            noiseTile = makeNoiseTile(size: 96)
        }
        guard let noiseTile else { return }
        UIColor(patternImage: noiseTile).setFill()
        context.fill(rect)
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
        menuView.layer.cornerRadius = 40
        menuView.layer.shadowColor = UIColor.black.cgColor
        menuView.layer.shadowOpacity = 0.1
        menuView.layer.shadowRadius = 10
        menuView.layer.shadowOffset = CGSize(width: 0, height: 4)
        menuView.isHidden = true

        colorButton.setImage(UIImage(systemName: "circle.fill"), for: .normal)
        colorButton.tintColor = baseStrokeColor
        colorButton.addTarget(self, action: #selector(handleColorTap), for: .touchUpInside)

        widthButton.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        widthButton.tintColor = UIColor.black.withAlphaComponent(0.7)
        widthButton.addTarget(self, action: #selector(handleWidthTap), for: .touchUpInside)

        eraserButton.setImage(UIImage(systemName: "eraser"), for: .normal)
        eraserButton.tintColor = UIColor.black.withAlphaComponent(0.7)
        eraserButton.addTarget(self, action: #selector(handleEraserTap), for: .touchUpInside)

        proButton.setImage(UIImage(systemName: "crown"), for: .normal)
        proButton.addTarget(self, action: #selector(handleProTap), for: .touchUpInside)

        [colorButton, widthButton, eraserButton, proButton].forEach {
            $0.backgroundColor = UIColor(white: 1.0, alpha: 0.9)
            $0.layer.cornerRadius = 18
            $0.frame.size = CGSize(width: 36, height: 36)
            menuView.addSubview($0)
        }
        updateProButtonAppearance()

        addSubview(menuView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGFloat = 80
        menuView.frame = CGRect(x: menuCenter.x - size / 2, y: menuCenter.y - size / 2, width: size, height: size)
        let radius: CGFloat = 26
        let center = CGPoint(x: size / 2, y: size / 2)
        let angles: [CGFloat] = [-CGFloat.pi / 2, 0, CGFloat.pi / 2, CGFloat.pi]
        let buttons = [colorButton, widthButton, eraserButton, proButton]
        for (index, button) in buttons.enumerated() {
            let angle = angles[index]
            let x = center.x + radius * cos(angle) - 18
            let y = center.y + radius * sin(angle) - 18
            button.frame = CGRect(x: x, y: y, width: 36, height: 36)
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            menuCenter = recognizer.location(in: self)
            menuView.isHidden = false
            setNeedsLayout()
        case .ended, .cancelled, .failed:
            menuView.isHidden = true
        default:
            break
        }
    }

    @objc private func handleColorTap() {
        if baseStrokeColor == UIColor.black.withAlphaComponent(0.9) {
            baseStrokeColor = UIColor(red: 0.12, green: 0.2, blue: 0.35, alpha: 0.9)
        } else {
            baseStrokeColor = UIColor.black.withAlphaComponent(0.9)
        }
        colorButton.tintColor = baseStrokeColor
    }

    @objc private func handleWidthTap() {
        baseLineWidth = baseLineWidth < 3.5 ? 4.2 : 2.2
    }

    @objc private func handleEraserTap() {
        isEraser.toggle()
        eraserButton.tintColor = isEraser ? UIColor.systemBlue : UIColor.black.withAlphaComponent(0.7)
    }

    @objc private func handleProTap() {
        guard !isProUser else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = await onPurchasePro?()
            updateProButtonAppearance()
        }
    }

    private func updateProButtonAppearance() {
        proButton.tintColor = isProUser ? UIColor.systemGreen : UIColor.black.withAlphaComponent(0.7)
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
