import UIKit

final class RadialMenuController {
    private unowned let host: UIView
    private let graphiteColor: UIColor
    private var colorSubPalette: [UIColor]
    private let getIsEraser: () -> Bool
    private let setIsEraser: (Bool) -> Void
    private let setBaseStrokeColor: (UIColor) -> Void
    private let cycleLineWidth: () -> Void
    private let onExport: () -> Void
    private let onSettings: () -> Void
    private let onSparkles: () -> Void
    private let onPaletteIndexChanged: (Int) -> Void

    private let menuView = UIView()
    private let colorMenuView = UIView()
    private let colorButton = UIButton(type: .system)
    private let widthButton = UIButton(type: .system)
    private let eraserButton = UIButton(type: .system)
    private let exportButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let sparklesButton = UIButton(type: .system)
    private var colorButtons: [UIButton] = []
    private let menuCenterKeyX = "radialMenu.center.x"
    private let menuCenterKeyY = "radialMenu.center.y"
    private let bounceCountKey = "radialMenu.bounce.count"
    private let paletteIndexKey = "radialMenu.palette.index"
    private let bounceMilestone = 1000
    private var bounceCount: Int = 0
    private var paletteIndex: Int = 0
    private var displayLink: CADisplayLink?
    private var inertiaVelocity: CGPoint = .zero
    private let inertiaDecelRate: CGFloat = 0.94
    private let inertiaStopThreshold: CGFloat = 18
    private let bounceFactor: CGFloat = 1.2

    private(set) var menuCenter: CGPoint = .zero
    private lazy var menuPan: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handleMenuPan(_:)))
    }()

    init(
        host: UIView,
        graphiteColor: UIColor,
        colorSubPalette: [UIColor],
        getIsEraser: @escaping () -> Bool,
        setIsEraser: @escaping (Bool) -> Void,
        setBaseStrokeColor: @escaping (UIColor) -> Void,
        cycleLineWidth: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onSparkles: @escaping () -> Void,
        onPaletteIndexChanged: @escaping (Int) -> Void
    ) {
        self.host = host
        self.graphiteColor = graphiteColor
        self.colorSubPalette = colorSubPalette
        self.getIsEraser = getIsEraser
        self.setIsEraser = setIsEraser
        self.setBaseStrokeColor = setBaseStrokeColor
        self.cycleLineWidth = cycleLineWidth
        self.onExport = onExport
        self.onSettings = onSettings
        self.onSparkles = onSparkles
        self.onPaletteIndexChanged = onPaletteIndexChanged

        loadMenuCenter()
        configureMenu()
        configureColorMenu()
        loadBounceProgress()
    }

    var isMenuVisible: Bool {
        !menuView.isHidden || !colorMenuView.isHidden
    }

    func showMenuAtCenter() {
        menuCenter = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        menuCenter = clamp(point: menuCenter, in: host.bounds)
        saveMenuCenter()
        colorMenuView.isHidden = true
        showMenu(animated: true)
    }

    func showMenu(at point: CGPoint) {
        menuCenter = clamp(point: point, in: host.bounds)
        saveMenuCenter()
        colorMenuView.isHidden = true
        showMenu(animated: true)
    }

    func layout(in bounds: CGRect) {
        if menuCenter != .zero {
            menuCenter = clamp(point: menuCenter, in: bounds)
        }
        let size: CGFloat = 192
        layoutMenuSlots(
            view: menuView,
            size: size,
            radius: 52,
            slots: [colorButton, widthButton, settingsButton, exportButton, sparklesButton]
        )
        layoutMenuSlots(
            view: colorMenuView,
            size: size,
            radius: 52,
            slots: colorButtons.map { Optional($0) }
        )
    }

    func handleTap(at location: CGPoint) {
        guard isMenuVisible else { return }
        if !menuView.frame.contains(location) && !colorMenuView.frame.contains(location) {
            hideMenuAfterSelection()
        }
    }

    func updateColorPalette(_ colors: [UIColor]) {
        guard colors.count == colorButtons.count else { return }
        colorSubPalette = colors
        for (index, color) in colors.enumerated() {
            let button = colorButtons[index]
            button.tintColor = color
            if let imageView = button.imageView {
                imageView.tintColor = color
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

        [colorButton, widthButton, settingsButton, exportButton, sparklesButton].forEach {
            $0.backgroundColor = .clear
            $0.layer.cornerRadius = 0
            $0.frame.size = CGSize(width: 72, height: 72)
            menuView.addSubview($0)
        }

        menuView.addGestureRecognizer(menuPan)
        updateEraserAppearance()
        host.addSubview(menuView)
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

        colorMenuView.addGestureRecognizer(menuPan)
        host.addSubview(colorMenuView)
    }

    private func handleColorSelect(index: Int) {
        guard colorSubPalette.indices.contains(index) else { return }
        setBaseStrokeColor(colorSubPalette[index])
        if getIsEraser() {
            setIsEraser(false)
            updateEraserAppearance()
        }
        hideMenuAfterSelection()
    }

    private func handleWidthTap() {
        cycleLineWidth()
        hideMenuAfterSelection()
    }

    private func handleEraserTap() {
        setIsEraser(!getIsEraser())
        updateEraserAppearance()
        hideMenuAfterSelection()
    }

    private func handleExportTap() {
        onExport()
        hideMenuAfterSelection()
    }

    private func handleSettingsTap() {
        onSettings()
        hideMenuAfterSelection()
    }

    private func handleSparklesTap() {
        onSparkles()
        hideMenuAfterSelection()
    }

    private func updateEraserAppearance() {
        eraserButton.tintColor = getIsEraser()
            ? UIColor.systemBlue
            : UIColor.black.withAlphaComponent(0.7)
    }

    @objc private func handleMenuPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopInertia()
        case .changed:
            let translation = recognizer.translation(in: host)
            let raw = CGPoint(x: menuCenter.x + translation.x, y: menuCenter.y + translation.y)
            menuCenter = clamp(point: raw, in: host.bounds)
            recognizer.setTranslation(.zero, in: host)
            layout(in: host.bounds)
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: host)
            inertiaVelocity = CGPoint(x: velocity.x, y: velocity.y)
            startInertia()
            saveMenuCenter()
        default:
            break
        }
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
        host.bringSubviewToFront(colorMenuView)
        host.setNeedsLayout()
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

    private func showMenu(animated: Bool) {
        menuView.isHidden = false
        host.bringSubviewToFront(menuView)
        host.setNeedsLayout()
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

    private func startInertia() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleInertia))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopInertia() {
        displayLink?.invalidate()
        displayLink = nil
        inertiaVelocity = .zero
    }

    @objc private func handleInertia() {
        guard displayLink != nil else { return }
        let dt = CGFloat(displayLink?.duration ?? 1.0 / 60.0)
        var next = CGPoint(
            x: menuCenter.x + inertiaVelocity.x * dt,
            y: menuCenter.y + inertiaVelocity.y * dt
        )

        let margin: CGFloat = 64
        let minX = host.bounds.minX + margin
        let maxX = host.bounds.maxX - margin
        let minY = host.bounds.minY + margin
        let maxY = host.bounds.maxY - margin

        if next.x < minX {
            next.x = minX
            inertiaVelocity.x = abs(inertiaVelocity.x) * bounceFactor
            registerBounceIfNeeded()
        } else if next.x > maxX {
            next.x = maxX
            inertiaVelocity.x = -abs(inertiaVelocity.x) * bounceFactor
            registerBounceIfNeeded()
        }
        if next.y < minY {
            next.y = minY
            inertiaVelocity.y = abs(inertiaVelocity.y) * bounceFactor
            registerBounceIfNeeded()
        } else if next.y > maxY {
            next.y = maxY
            inertiaVelocity.y = -abs(inertiaVelocity.y) * bounceFactor
            registerBounceIfNeeded()
        }

        inertiaVelocity.x *= pow(inertiaDecelRate, dt * 60)
        inertiaVelocity.y *= pow(inertiaDecelRate, dt * 60)
        menuCenter = next
        layout(in: host.bounds)

        if hypot(inertiaVelocity.x, inertiaVelocity.y) < inertiaStopThreshold {
            stopInertia()
            saveMenuCenter()
        }
    }

    private func clamp(point: CGPoint, in bounds: CGRect) -> CGPoint {
        let margin: CGFloat = 64
        let x = min(max(point.x, bounds.minX + margin), bounds.maxX - margin)
        let y = min(max(point.y, bounds.minY + margin), bounds.maxY - margin)
        return CGPoint(x: x, y: y)
    }

    private func loadMenuCenter() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: menuCenterKeyX) != nil,
              defaults.object(forKey: menuCenterKeyY) != nil else { return }
        let x = defaults.double(forKey: menuCenterKeyX)
        let y = defaults.double(forKey: menuCenterKeyY)
        menuCenter = CGPoint(x: x, y: y)
    }

    private func saveMenuCenter() {
        let defaults = UserDefaults.standard
        defaults.set(menuCenter.x, forKey: menuCenterKeyX)
        defaults.set(menuCenter.y, forKey: menuCenterKeyY)
    }

    private func loadBounceProgress() {
        let defaults = UserDefaults.standard
        bounceCount = defaults.integer(forKey: bounceCountKey)
        paletteIndex = defaults.integer(forKey: paletteIndexKey)
        onPaletteIndexChanged(paletteIndex)
    }

    private func saveBounceProgress() {
        let defaults = UserDefaults.standard
        defaults.set(bounceCount, forKey: bounceCountKey)
        defaults.set(paletteIndex, forKey: paletteIndexKey)
    }

    private func registerBounceIfNeeded() {
        guard !colorMenuView.isHidden else { return }
        bounceCount += 1
        if bounceCount % bounceMilestone == 0 {
            paletteIndex = (paletteIndex + 1) % 2
            onPaletteIndexChanged(paletteIndex)
            saveBounceProgress()
        } else if bounceCount % 50 == 0 {
            saveBounceProgress()
        }
    }
}
