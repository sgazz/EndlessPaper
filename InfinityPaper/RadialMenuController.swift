import UIKit

final class RadialMenuController {
    private unowned let host: UIView
    private let graphiteColor: UIColor
    private var colorSubPalette: [UIColor]
    private let setBaseStrokeColor: (UIColor) -> Void
    private let cycleLineWidth: () -> Void
    private let onClearLastSession: () -> Void
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

    // Layout
    private enum MenuLayout {
        static let menuSize: CGFloat = 192
        static let menuRadius: CGFloat = 52
        static let buttonSize: CGFloat = 72
        static let menuCornerRadius: CGFloat = 80
        static let margin: CGFloat = 64
    }

    private static let hapticsKey = "settings.haptics.enabled"
    private static let radialScaleKey = "settings.radial.scale"
    private static let radialAnimationSpeedKey = "settings.radial.animationSpeed"
    private static let largerMenuButtonsKey = "settings.ui.largerButtons"
    private static let verboseA11yKey = "settings.ui.verboseA11y"
    private static let highContrastUIKey = "settings.ui.highContrast"

    private var hapticsEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.hapticsKey) != nil else { return true }
        return defaults.bool(forKey: Self.hapticsKey)
    }

    private var effectiveRadialScale: CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.radialScaleKey) != nil else { return 1.0 }
        return CGFloat(defaults.double(forKey: Self.radialScaleKey))
    }

    private var effectiveButtonSize: CGFloat {
        let defaults = UserDefaults.standard
        let useLarger = defaults.object(forKey: Self.largerMenuButtonsKey) != nil && defaults.bool(forKey: Self.largerMenuButtonsKey)
        return useLarger ? 80 : MenuLayout.buttonSize
    }

    private var effectiveAnimationSpeed: CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.radialAnimationSpeedKey) != nil else { return 1.0 }
        let raw = CGFloat(defaults.double(forKey: Self.radialAnimationSpeedKey))
        return max(0.25, min(2.0, raw))
    }

    private var effectiveShowDuration: TimeInterval { 0.42 / TimeInterval(effectiveAnimationSpeed) }
    private var effectiveHideDuration: TimeInterval { 0.28 / TimeInterval(effectiveAnimationSpeed) }
    private var effectiveStaggerDelay: TimeInterval { 0.032 / TimeInterval(effectiveAnimationSpeed) }

    private var highContrastUI: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.highContrastUIKey) != nil else { return false }
        return defaults.bool(forKey: Self.highContrastUIKey)
    }

    private var verboseAccessibilityHints: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.verboseA11yKey) != nil else { return true }
        return defaults.bool(forKey: Self.verboseA11yKey)
    }

    // Animation (base values; effective durations use effectiveShowDuration / effectiveHideDuration)
    private let menuSpringDamping: CGFloat = 0.72
    private let menuSpringVelocity: CGFloat = 0.6
    private let menuShowDuration: TimeInterval = 0.42
    private let menuHideDuration: TimeInterval = 0.28
    private let buttonStaggerDelay: TimeInterval = 0.032
    private let buttonInitialScale: CGFloat = 0.4
    private let menuInitialScale: CGFloat = 0.88

    private(set) var menuCenter: CGPoint = .zero
    private lazy var menuPan: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handleMenuPan(_:)))
    }()
    private lazy var colorMenuPan: UIPanGestureRecognizer = {
        UIPanGestureRecognizer(target: self, action: #selector(handleMenuPan(_:)))
    }()

    init(
        host: UIView,
        graphiteColor: UIColor,
        colorSubPalette: [UIColor],
        setBaseStrokeColor: @escaping (UIColor) -> Void,
        cycleLineWidth: @escaping () -> Void,
        onClearLastSession: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onSparkles: @escaping () -> Void,
        onPaletteIndexChanged: @escaping (Int) -> Void
    ) {
        self.host = host
        self.graphiteColor = graphiteColor
        self.colorSubPalette = colorSubPalette
        self.setBaseStrokeColor = setBaseStrokeColor
        self.cycleLineWidth = cycleLineWidth
        self.onClearLastSession = onClearLastSession
        self.onExport = onExport
        self.onSettings = onSettings
        self.onSparkles = onSparkles
        self.onPaletteIndexChanged = onPaletteIndexChanged

        loadMenuCenter()
        configureMenu()
        configureColorMenu()
        loadBounceProgress()
    }

    deinit {
        stopInertia()
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
        guard bounds.width > 0, bounds.height > 0 else { return }
        if menuCenter != .zero {
            menuCenter = clamp(point: menuCenter, in: bounds)
        }
        let buttonSize = effectiveButtonSize
        layoutMenuSlots(
            view: menuView,
            size: MenuLayout.menuSize,
            radius: MenuLayout.menuRadius,
            slots: [colorButton, widthButton, eraserButton, settingsButton, exportButton, sparklesButton],
            buttonSize: buttonSize
        )
        layoutMenuSlots(
            view: colorMenuView,
            size: MenuLayout.menuSize,
            radius: MenuLayout.menuRadius,
            slots: colorButtons.map { Optional($0) },
            buttonSize: buttonSize
        )
        let scale = effectiveRadialScale
        menuView.transform = CGAffineTransform(scaleX: scale, y: scale)
        colorMenuView.transform = CGAffineTransform(scaleX: scale, y: scale)

        if highContrastUI {
            menuView.layer.borderWidth = 1.5
            menuView.layer.borderColor = UIColor(white: 0.2, alpha: 0.9).cgColor
            colorMenuView.layer.borderWidth = 1.5
            colorMenuView.layer.borderColor = UIColor(white: 0.2, alpha: 0.9).cgColor
        } else {
            menuView.layer.borderWidth = 0
            colorMenuView.layer.borderWidth = 0
        }
        applyAccessibilityHints()
    }

    private func applyAccessibilityHints() {
        let verbose = verboseAccessibilityHints
        colorButton.accessibilityHint = verbose ? "Double-tap to open the color palette and choose a brush color." : "Opens the color palette"
        widthButton.accessibilityHint = verbose ? "Double-tap to cycle through thin, medium, and thick brush widths." : "Cycles through brush widths"
        eraserButton.accessibilityHint = verbose ? "Double-tap to clear the current drawing and saved session. You will be asked to confirm." : "Clears the last drawing session"
        exportButton.accessibilityHint = verbose ? "Double-tap to share or save your drawing as a file (PDF or PNG, depending on settings)." : "Share or save your drawing"
        settingsButton.accessibilityHint = verbose ? "Double-tap to open app settings for brush, export, and session options." : "Opens app settings"
        sparklesButton.accessibilityHint = verbose ? "Double-tap to apply special effects (feature coming soon)." : "Applies special effects"
        for button in colorButtons {
            button.accessibilityHint = verbose ? "Double-tap to select this color for the brush." : "Selects this color"
        }
    }

    func handleTap(at location: CGPoint) {
        guard isMenuVisible else { return }
        if !menuView.frame.contains(location) && !colorMenuView.frame.contains(location) {
            hideMenuAfterSelection()
        }
    }

    func updateColorPalette(_ colors: [UIColor]) {
        // If count differs, rebuild the color menu buttons to avoid overlap/misalignment
        if colors.count != colorButtons.count {
            // Remove old buttons
            colorButtons.forEach { $0.removeFromSuperview() }
            // Build new buttons
            colorButtons = colors.enumerated().map { index, color in
                let button = UIButton(type: .system)
                configureTapButton(
                    button,
                    imageSystemName: "circle.fill",
                    tintColor: color,
                    action: { [weak self] in self?.handleColorSelect(index: index) }
                )
                colorMenuView.addSubview(button)
                button.backgroundColor = .clear
                button.layer.cornerRadius = 0
                button.frame.size = CGSize(width: MenuLayout.buttonSize, height: MenuLayout.buttonSize)
                return button
            }
            colorSubPalette = colors
            colorButton.setImage(makeColorDotsIcon(), for: .normal)
            // Relayout immediately if visible
            layout(in: host.bounds)
            return
        }
        // Same count: just update tint colors
        colorSubPalette = colors
        for (index, color) in colors.enumerated() {
            let button = colorButtons[index]
            button.tintColor = color
            if let imageView = button.imageView {
                imageView.tintColor = color
            }
        }
        colorButton.setImage(makeColorDotsIcon(), for: .normal)
    }

    private func configureMenu() {
        menuView.backgroundColor = .clear
        menuView.layer.cornerRadius = MenuLayout.menuCornerRadius
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
            imageSystemName: "trash",
            tintColor: graphiteColor,
            action: { [weak self] in self?.handleClearTap() }
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

        [colorButton, widthButton, eraserButton, settingsButton, exportButton, sparklesButton].forEach {
            $0.backgroundColor = .clear
            $0.layer.cornerRadius = 0
            $0.frame.size = CGSize(width: MenuLayout.buttonSize, height: MenuLayout.buttonSize)
            menuView.addSubview($0)
        }

        menuView.addGestureRecognizer(menuPan)
        host.addSubview(menuView)
    }

    private func configureColorMenu() {
        colorMenuView.backgroundColor = .clear
        colorMenuView.layer.cornerRadius = MenuLayout.menuCornerRadius
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
            button.accessibilityLabel = "Color \(index + 1)"
            button.accessibilityHint = "Selects this color"
            colorMenuView.addSubview(button)
            return button
        }
        colorButtons.forEach {
            $0.backgroundColor = .clear
            $0.layer.cornerRadius = 0
            $0.frame.size = CGSize(width: MenuLayout.buttonSize, height: MenuLayout.buttonSize)
        }

        colorMenuView.addGestureRecognizer(colorMenuPan)
        host.addSubview(colorMenuView)
    }

    private func handleColorSelect(index: Int) {
        guard colorSubPalette.indices.contains(index) else { return }
        setBaseStrokeColor(colorSubPalette[index])
        hideMenuAfterSelection()
    }

    private func handleWidthTap() {
        cycleLineWidth()
        hideMenuAfterSelection()
    }

    private func handleClearTap() {
        onClearLastSession()
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
        // Accessibility
        button.accessibilityTraits.insert(.button)
        if button === colorButton {
            button.accessibilityLabel = "Colors"
            button.accessibilityHint = "Opens the color palette"
        } else if button === widthButton {
            button.accessibilityLabel = "Line Width"
            button.accessibilityHint = "Cycles through brush widths"
        } else if button === eraserButton {
            button.accessibilityLabel = "Clear"
            button.accessibilityHint = "Clears the last drawing session"
        } else if button === exportButton {
            button.accessibilityLabel = "Export"
            button.accessibilityHint = "Share or save your drawing"
        } else if button === settingsButton {
            button.accessibilityLabel = "Settings"
            button.accessibilityHint = "Opens app settings"
        } else if button === sparklesButton {
            button.accessibilityLabel = "Effects"
            button.accessibilityHint = "Applies special effects"
        }

        button.addAction(UIAction { [weak self] _ in
            if self?.hapticsEnabled == true {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            action()
        }, for: .touchUpInside)
    }

    private func makeColorDotsIcon(size: CGFloat = 26) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let colorsToUse: [UIColor] = {
            let sample = Array(colorSubPalette.prefix(3))
            if sample.isEmpty { return [.red, .green, .blue] }
            if sample.count == 1 { return [sample[0], sample[0], sample[0]] }
            if sample.count == 2 { return [sample[0], sample[1], sample[0]] }
            return sample
        }()
        return renderer.image { context in
            let dotDiameter = size * 0.24
            let spacing = size * 0.08
            let totalWidth = dotDiameter * 3 + spacing * 2
            let startX = (size - totalWidth) / 2
            let y = (size - dotDiameter) / 2
            for (index, color) in colorsToUse.enumerated() {
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

    private func layoutMenuSlots(view: UIView, size: CGFloat, radius: CGFloat, slots: [UIButton?], buttonSize: CGFloat = MenuLayout.buttonSize) {
        let actualButtons = slots.compactMap { $0 }
        view.frame = CGRect(x: menuCenter.x - size / 2, y: menuCenter.y - size / 2, width: size, height: size)
        guard !actualButtons.isEmpty else { return }
        let center = CGPoint(x: size / 2, y: size / 2)
        let count = actualButtons.count
        let half = buttonSize / 2
        for (i, button) in actualButtons.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * (2 * CGFloat.pi / CGFloat(count))
            let x = center.x + radius * cos(angle) - half
            let y = center.y + radius * sin(angle) - half
            button.frame = CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
        }
    }

    private var mainMenuButtons: [UIButton] {
        [colorButton, widthButton, eraserButton, settingsButton, exportButton, sparklesButton]
    }

    private func showColorMenu() {
        menuView.isHidden = true
        colorMenuView.isHidden = false
        host.bringSubviewToFront(colorMenuView)
        layout(in: host.bounds)

        let scale = effectiveRadialScale
        colorMenuView.alpha = 0
        colorMenuView.transform = CGAffineTransform(scaleX: menuInitialScale * scale, y: menuInitialScale * scale)
        colorButtons.forEach {
            $0.transform = CGAffineTransform(scaleX: buttonInitialScale, y: buttonInitialScale)
            $0.alpha = 0
        }

        UIView.animate(
            withDuration: effectiveShowDuration,
            delay: 0,
            usingSpringWithDamping: menuSpringDamping,
            initialSpringVelocity: menuSpringVelocity,
            options: [.allowUserInteraction]
        ) {
            self.colorMenuView.alpha = 1
            self.colorMenuView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }

        colorButtons.enumerated().forEach { index, button in
            UIView.animate(
                withDuration: effectiveShowDuration * 0.85,
                delay: Double(index) * effectiveStaggerDelay,
                usingSpringWithDamping: menuSpringDamping,
                initialSpringVelocity: menuSpringVelocity,
                options: [.allowUserInteraction]
            ) {
                button.transform = .identity
                button.alpha = 1
            }
        }
    }

    private func hideMenuAfterSelection() {
        hideMenu(animated: true)
    }

    private func showMenu(animated: Bool) {
        menuView.isHidden = false
        host.bringSubviewToFront(menuView)
        layout(in: host.bounds)

        if animated {
            let scale = effectiveRadialScale
            menuView.alpha = 0
            menuView.transform = CGAffineTransform(scaleX: menuInitialScale * scale, y: menuInitialScale * scale)
            mainMenuButtons.forEach {
                $0.transform = CGAffineTransform(scaleX: buttonInitialScale, y: buttonInitialScale)
                $0.alpha = 0
            }

            UIView.animate(
                withDuration: effectiveShowDuration,
                delay: 0,
                usingSpringWithDamping: menuSpringDamping,
                initialSpringVelocity: menuSpringVelocity,
                options: [.allowUserInteraction]
            ) {
                self.menuView.alpha = 1
                self.menuView.transform = CGAffineTransform(scaleX: scale, y: scale)
            }

            mainMenuButtons.enumerated().forEach { index, button in
                UIView.animate(
                    withDuration: effectiveShowDuration * 0.85,
                    delay: Double(index) * effectiveStaggerDelay,
                    usingSpringWithDamping: menuSpringDamping,
                    initialSpringVelocity: menuSpringVelocity,
                    options: [.allowUserInteraction]
                ) {
                    button.transform = .identity
                    button.alpha = 1
                }
            }
        } else {
            let scale = effectiveRadialScale
            menuView.alpha = 1
            menuView.transform = CGAffineTransform(scaleX: scale, y: scale)
            mainMenuButtons.forEach {
                $0.transform = .identity
                $0.alpha = 1
            }
        }
    }

    private func hideMenu(animated: Bool) {
        if animated {
            let scale = effectiveRadialScale
            UIView.animate(
                withDuration: effectiveHideDuration,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.menuView.alpha = 0
                self.menuView.transform = CGAffineTransform(scaleX: self.menuInitialScale * scale, y: self.menuInitialScale * scale)
                self.colorMenuView.alpha = 0
                self.colorMenuView.transform = CGAffineTransform(scaleX: self.menuInitialScale * scale, y: self.menuInitialScale * scale)
                self.mainMenuButtons.forEach {
                    $0.transform = CGAffineTransform(scaleX: self.buttonInitialScale, y: self.buttonInitialScale)
                    $0.alpha = 0
                }
                self.colorButtons.forEach {
                    $0.transform = CGAffineTransform(scaleX: self.buttonInitialScale, y: self.buttonInitialScale)
                    $0.alpha = 0
                }
            } completion: { _ in
                let scale = self.effectiveRadialScale
                self.menuView.isHidden = true
                self.colorMenuView.isHidden = true
                self.menuView.alpha = 1
                self.menuView.transform = CGAffineTransform(scaleX: scale, y: scale)
                self.colorMenuView.alpha = 1
                self.colorMenuView.transform = CGAffineTransform(scaleX: scale, y: scale)
                self.mainMenuButtons.forEach {
                    $0.transform = .identity
                    $0.alpha = 1
                }
                self.colorButtons.forEach {
                    $0.transform = .identity
                    $0.alpha = 1
                }
            }
        } else {
            let scale = effectiveRadialScale
            menuView.isHidden = true
            colorMenuView.isHidden = true
            menuView.alpha = 1
            menuView.transform = CGAffineTransform(scaleX: scale, y: scale)
            colorMenuView.alpha = 1
            colorMenuView.transform = CGAffineTransform(scaleX: scale, y: scale)
            mainMenuButtons.forEach { $0.transform = .identity; $0.alpha = 1 }
            colorButtons.forEach { $0.transform = .identity; $0.alpha = 1 }
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

        let margin = MenuLayout.margin
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
        guard bounds.width > 0, bounds.height > 0 else { return point }
        let margin = MenuLayout.margin
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
        // Clamp to current bounds if we already have a valid host frame
        if host.bounds.width > 0 && host.bounds.height > 0 {
            menuCenter = clamp(point: menuCenter, in: host.bounds)
        }
    }

    private func saveMenuCenter() {
        let defaults = UserDefaults.standard
        defaults.set(menuCenter.x, forKey: menuCenterKeyX)
        defaults.set(menuCenter.y, forKey: menuCenterKeyY)
    }

    /// Sets the radial menu center to the given point (in host coordinates), saves it, and updates layout. Does not show the menu.
    func setMenuCenterAndSave(_ point: CGPoint) {
        menuCenter = clamp(point: point, in: host.bounds)
        saveMenuCenter()
        layout(in: host.bounds)
    }

    private func loadBounceProgress() {
        let defaults = UserDefaults.standard
        bounceCount = defaults.integer(forKey: bounceCountKey)
        paletteIndex = defaults.integer(forKey: paletteIndexKey)
    }

    func syncPaletteIndex() {
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

