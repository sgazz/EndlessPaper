import SwiftUI

struct SettingsView: View {
    // MARK: - Bindings / Callbacks to integrate with canvas and menu
    @State private var selectedColorIndex: Int
    @State private var baseLineWidth: CGFloat
    @State private var exportFormat: ExportFormat
    @State private var exportResolution: CGFloat
    @State private var exportMargin: CGFloat
    @State private var includeBackgroundNoise: Bool
    @State private var transparentBackground: Bool
    @State private var autoNameExports: Bool
    @State private var exportPrefix: String
    @State private var hapticsEnabled: Bool
    @State private var radialMenuScale: CGFloat
    @State private var radialAnimationSpeed: CGFloat
    @State private var autosaveMode: AutosaveMode
    @State private var autoloadOnLaunch: Bool
    @State private var highContrastUI: Bool
    @State private var largerMenuButtons: Bool
    @State private var verboseAccessibilityHints: Bool

    let palette: [UIColor]
    let onSelectBaseColor: (UIColor) -> Void
    let onLineWidthChanged: (CGFloat) -> Void
    let onClearSession: () -> Void
    let onLoadPreviousSession: () -> Void
    let onResetRadialMenuPosition: () -> Void
    let onDismiss: () -> Void

    // UserDefaults keys
    private enum Keys {
        static let baseColorIndex = "settings.baseColorIndex"
        static let baseLineWidth = "settings.baseLineWidth"
        static let exportFormat = "settings.export.format"
        static let exportResolution = "settings.export.resolution"
        static let exportMargin = "settings.export.margin"
        static let includeBackgroundNoise = "settings.export.includeNoise"
        static let transparentBackground = "settings.export.transparent"
        static let autoNameExports = "settings.export.autoName"
        static let exportPrefix = "settings.export.prefix"
        static let hapticsEnabled = "settings.haptics.enabled"
        static let radialMenuScale = "settings.radial.scale"
        static let radialAnimationSpeed = "settings.radial.animationSpeed"
        static let autosaveMode = "settings.session.autosaveMode"
        static let autoloadOnLaunch = "settings.session.autoload"
        static let highContrastUI = "settings.ui.highContrast"
        static let largerMenuButtons = "settings.ui.largerButtons"
        static let verboseAccessibilityHints = "settings.ui.verboseA11y"
    }

    init(
        palette: [UIColor],
        currentBaseColor: UIColor,
        currentLineWidth: CGFloat,
        onSelectBaseColor: @escaping (UIColor) -> Void,
        onLineWidthChanged: @escaping (CGFloat) -> Void,
        onClearSession: @escaping () -> Void,
        onLoadPreviousSession: @escaping () -> Void,
        onResetRadialMenuPosition: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.palette = palette
        self.onSelectBaseColor = onSelectBaseColor
        self.onLineWidthChanged = onLineWidthChanged
        self.onClearSession = onClearSession
        self.onLoadPreviousSession = onLoadPreviousSession
        self.onResetRadialMenuPosition = onResetRadialMenuPosition
        self.onDismiss = onDismiss

        // Load defaults
        let defaults = UserDefaults.standard
        let defaultColorIndex = defaults.integer(forKey: Keys.baseColorIndex)
        _selectedColorIndex = State(initialValue: min(max(0, defaultColorIndex), max(0, palette.count - 1)))
        _baseLineWidth = State(initialValue: defaults.object(forKey: Keys.baseLineWidth) == nil ? currentLineWidth : CGFloat(defaults.double(forKey: Keys.baseLineWidth)))
        _exportFormat = State(initialValue: ExportFormat(rawValue: defaults.string(forKey: Keys.exportFormat) ?? ExportFormat.pdf.rawValue) ?? .pdf)
        _exportResolution = State(initialValue: defaults.object(forKey: Keys.exportResolution) != nil ? CGFloat(defaults.double(forKey: Keys.exportResolution)) : 2.0)
        _exportMargin = State(initialValue: defaults.object(forKey: Keys.exportMargin) != nil ? CGFloat(defaults.double(forKey: Keys.exportMargin)) : 0.0)
        _includeBackgroundNoise = State(initialValue: defaults.object(forKey: Keys.includeBackgroundNoise) != nil ? defaults.bool(forKey: Keys.includeBackgroundNoise) : true)
        _transparentBackground = State(initialValue: defaults.object(forKey: Keys.transparentBackground) != nil ? defaults.bool(forKey: Keys.transparentBackground) : false)
        _autoNameExports = State(initialValue: defaults.object(forKey: Keys.autoNameExports) != nil ? defaults.bool(forKey: Keys.autoNameExports) : true)
        _exportPrefix = State(initialValue: defaults.string(forKey: Keys.exportPrefix) ?? "InfinityPaper_")
        _hapticsEnabled = State(initialValue: defaults.object(forKey: Keys.hapticsEnabled) != nil ? defaults.bool(forKey: Keys.hapticsEnabled) : true)
        _radialMenuScale = State(initialValue: defaults.object(forKey: Keys.radialMenuScale) != nil ? CGFloat(defaults.double(forKey: Keys.radialMenuScale)) : 1.0)
        _radialAnimationSpeed = State(initialValue: defaults.object(forKey: Keys.radialAnimationSpeed) != nil ? CGFloat(defaults.double(forKey: Keys.radialAnimationSpeed)) : 1.0)
        _autosaveMode = State(initialValue: AutosaveMode(rawValue: defaults.string(forKey: Keys.autosaveMode) ?? AutosaveMode.onBackground.rawValue) ?? .onBackground)
        _autoloadOnLaunch = State(initialValue: defaults.object(forKey: Keys.autoloadOnLaunch) != nil ? defaults.bool(forKey: Keys.autoloadOnLaunch) : true)
        _highContrastUI = State(initialValue: defaults.object(forKey: Keys.highContrastUI) != nil ? defaults.bool(forKey: Keys.highContrastUI) : false)
        _largerMenuButtons = State(initialValue: defaults.object(forKey: Keys.largerMenuButtons) != nil ? defaults.bool(forKey: Keys.largerMenuButtons) : false)
        _verboseAccessibilityHints = State(initialValue: defaults.object(forKey: Keys.verboseAccessibilityHints) != nil ? defaults.bool(forKey: Keys.verboseAccessibilityHints) : true)

        // Apply initial color selection if matches current
        if let idx = palette.firstIndex(where: { $0.isEqual(currentBaseColor) }) {
            _selectedColorIndex = State(initialValue: idx)
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Brush & Canvas")) {
                    colorPaletteSection
                    lineWidthSection
                }

                Section(header: Text("Export & Share")) {
                    exportSection
                }

                Section(header: Text("Interactions & Gestures")) {
                    hapticsSection
                    radialMenuSection
                }

                Section(header: Text("Session & Storage"), footer: Text("Session is one drawing; it is saved automatically. Clear removes it and the saved file (you’ll be asked to confirm).")) {
                    autosaveSection
                    Button(role: .destructive) {
                        onClearSession()
                    } label: {
                        Text("Clear current session")
                    }
                    Button {
                        onLoadPreviousSession()
                    } label: {
                        Text("Load previous session")
                    }
                }

                Section(header: Text("Accessibility & UI")) {
                    Toggle("High contrast UI", isOn: $highContrastUI)
                        .onChange(of: highContrastUI) { newValue in
                            UserDefaults.standard.set(newValue, forKey: Keys.highContrastUI)
                        }
                    Toggle("Larger menu buttons", isOn: $largerMenuButtons)
                        .onChange(of: largerMenuButtons) { newValue in
                            UserDefaults.standard.set(newValue, forKey: Keys.largerMenuButtons)
                        }
                    Toggle("Verbose VoiceOver hints", isOn: $verboseAccessibilityHints)
                        .onChange(of: verboseAccessibilityHints) { newValue in
                            UserDefaults.standard.set(newValue, forKey: Keys.verboseAccessibilityHints)
                        }
                }

                Section(header: Text("About")) {
                    Text("InfinityPaper")
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                    if let websiteURL = URL(string: "https://example.com") {
                        Link("Website", destination: websiteURL)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Done") { onDismiss() } } }
        }
    }
    
    private var autosaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Autosave mode", selection: $autosaveMode) {
                Text("On background").tag(AutosaveMode.onBackground)
                Text("Periodic").tag(AutosaveMode.periodic)
            }
            .pickerStyle(.segmented)
            .onChange(of: autosaveMode) { newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: Keys.autosaveMode)
            }
            Text("On background: save when you leave the app. Periodic: also save every 60 seconds.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Autoload previous session on launch", isOn: $autoloadOnLaunch)
                .onChange(of: autoloadOnLaunch) { newValue in
                    UserDefaults.standard.set(newValue, forKey: Keys.autoloadOnLaunch)
                }
            Text("When on, the last saved drawing is loaded at startup.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var colorPaletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default brush color")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(palette.enumerated()), id: \.0) { idx, uiColor in
                        let color = Color(uiColor)
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(Color.black.opacity(selectedColorIndex == idx ? 0.6 : 0.15), lineWidth: selectedColorIndex == idx ? 3 : 1)
                            )
                            .onTapGesture {
                                selectedColorIndex = idx
                                let chosen = palette[idx]
                                onSelectBaseColor(chosen)
                                UserDefaults.standard.set(idx, forKey: Keys.baseColorIndex)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var lineWidthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default line width: \(String(format: "%.1f", baseLineWidth))")
            Slider(value: $baseLineWidth, in: 1.0...8.0, step: 0.2) {
                Text("Line Width")
            } minimumValueLabel: {
                Text("1.0")
            } maximumValueLabel: {
                Text("8.0")
            }
            .onChange(of: baseLineWidth) { newValue in
                onLineWidthChanged(newValue)
                UserDefaults.standard.set(Double(newValue), forKey: Keys.baseLineWidth)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Export format", selection: $exportFormat) {
                Text("PDF").tag(ExportFormat.pdf)
                Text("PNG").tag(ExportFormat.png)
            }
            .pickerStyle(.segmented)
            .onChange(of: exportFormat) { newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: Keys.exportFormat)
            }

            HStack {
                Text("Resolution")
                Slider(value: $exportResolution, in: 1.0...4.0, step: 0.5)
                Text(String(format: "x%.1f", exportResolution))
            }
            .onChange(of: exportResolution) { newValue in
                UserDefaults.standard.set(Double(newValue), forKey: Keys.exportResolution)
            }

            HStack {
                Text("Margins")
                Slider(value: $exportMargin, in: 0...64, step: 2)
                Text("\(Int(exportMargin)) pt")
            }
            .onChange(of: exportMargin) { newValue in
                UserDefaults.standard.set(Double(newValue), forKey: Keys.exportMargin)
            }

            Toggle("Include background noise (PNG)", isOn: $includeBackgroundNoise)
                .onChange(of: includeBackgroundNoise) { newValue in
                    UserDefaults.standard.set(newValue, forKey: Keys.includeBackgroundNoise)
                }
            Toggle("Transparent background (PNG)", isOn: $transparentBackground)
                .onChange(of: transparentBackground) { newValue in
                    UserDefaults.standard.set(newValue, forKey: Keys.transparentBackground)
                }

            Toggle("Auto-name exports", isOn: $autoNameExports)
                .onChange(of: autoNameExports) { newValue in
                    UserDefaults.standard.set(newValue, forKey: Keys.autoNameExports)
                }
            TextField("Export prefix", text: $exportPrefix)
                .textInputAutocapitalization(.never)
                .onChange(of: exportPrefix) { newValue in
                    UserDefaults.standard.set(newValue, forKey: Keys.exportPrefix)
                }
        }
    }

    private var hapticsSection: some View {
        Toggle("Haptics in menu", isOn: $hapticsEnabled)
            .onChange(of: hapticsEnabled) { newValue in
                UserDefaults.standard.set(newValue, forKey: Keys.hapticsEnabled)
            }
    }

    private var radialMenuSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Menu scale")
                Slider(value: $radialMenuScale, in: 0.8...1.4, step: 0.05)
                Text(String(format: "%.2f×", radialMenuScale))
            }
            .onChange(of: radialMenuScale) { newValue in
                UserDefaults.standard.set(Double(newValue), forKey: Keys.radialMenuScale)
            }

            HStack {
                Text("Animation speed")
                Slider(value: $radialAnimationSpeed, in: 0.5...1.5, step: 0.05)
                Text(String(format: "%.2fx", radialAnimationSpeed))
            }
            .onChange(of: radialAnimationSpeed) { newValue in
                UserDefaults.standard.set(Double(newValue), forKey: Keys.radialAnimationSpeed)
            }

            Button("Reset to defaults") {
                radialMenuScale = 1.0
                radialAnimationSpeed = 1.0
                UserDefaults.standard.set(1.0, forKey: Keys.radialMenuScale)
                UserDefaults.standard.set(1.0, forKey: Keys.radialAnimationSpeed)
            }

            Button("Reset menu position") {
                onResetRadialMenuPosition()
            }
        }
    }
}

// MARK: - Supporting Types

enum ExportFormat: String, CaseIterable, Identifiable { case pdf, png; var id: String { rawValue } }

enum AutosaveMode: String, CaseIterable, Identifiable { case onBackground, periodic; var id: String { rawValue } }
