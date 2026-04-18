//
//  CanvasFloatingToolbar.swift
//  InfinityPaper
//
//  SwiftUI capsule toolbar: primary drawing controls with calm paper/graphite styling.
//

import SwiftUI
import UIKit

// MARK: - State broker (toolbar ↔ UIKit canvas)

@MainActor
final class CanvasToolbarStateBroker: ObservableObject {
    weak var canvas: TapeCanvasUIView?

    @Published var undoEnabled: Bool = false
    @Published var redoEnabled: Bool = false
    @Published var lineWidthLabel: String = ""

    func attach(_ canvas: TapeCanvasUIView) {
        self.canvas = canvas
        syncFromCanvas()
    }

    func syncFromCanvas() {
        guard let canvas else {
            undoEnabled = false
            redoEnabled = false
            lineWidthLabel = ""
            return
        }
        undoEnabled = canvas.toolbarUndoEnabled
        redoEnabled = canvas.toolbarRedoEnabled
        lineWidthLabel = String(format: "%.1f", canvas.toolbarBaseLineWidth)
    }

    var paletteUIColors: [UIColor] {
        canvas?.exposedPrimaryPalette ?? []
    }
}

// MARK: - Floating toolbar

struct CanvasFloatingToolbar: View {
    @ObservedObject var broker: CanvasToolbarStateBroker
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    var onSelectColor: (Int) -> Void
    var onLineWidth: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onExport: () -> Void
    var onSettings: () -> Void
    var onMoreAbout: () -> Void

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var capsuleHPadding: CGFloat { isPad ? 22 : 14 }
    private var interItemSpacing: CGFloat { isPad ? 14 : 10 }
    private var iconFrame: CGFloat { isPad ? 40 : 34 }

    private var capsuleFill: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(white: 0.14, alpha: 0.92)
            } else {
                UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 0.94)
            }
        })
    }

    private var strokeLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var iconTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.55)
    }

    var body: some View {
        HStack(spacing: interItemSpacing) {
            Menu {
                ForEach(Array(broker.paletteUIColors.enumerated()), id: \.offset) { idx, ui in
                    Button {
                        onSelectColor(idx)
                    } label: {
                        Circle()
                            .fill(Color(uiColor: ui))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                    }
                    .accessibilityLabel(Text(String(format: NSLocalizedString("toolbar.color_slot", comment: ""), idx + 1)))
                }
            } label: {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: isPad ? 19 : 17, weight: .medium))
                    .frame(width: iconFrame, height: iconFrame)
            }
            .menuStyle(.button)
            .accessibilityLabel(Text(String(localized: "toolbar.color")))

            Button(action: onLineWidth) {
                VStack(spacing: 1) {
                    Image(systemName: "lineweight")
                        .font(.system(size: isPad ? 17 : 15, weight: .medium))
                    Text(broker.lineWidthLabel)
                        .font(.system(size: isPad ? 9 : 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(width: iconFrame, height: iconFrame)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "toolbar.line_width")))

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: isPad ? 19 : 17, weight: .medium))
                    .frame(width: iconFrame, height: iconFrame)
            }
            .buttonStyle(.plain)
            .disabled(!broker.undoEnabled)
            .opacity(broker.undoEnabled ? 1 : 0.35)
            .accessibilityLabel(Text(String(localized: "toolbar.undo")))

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: isPad ? 19 : 17, weight: .medium))
                    .frame(width: iconFrame, height: iconFrame)
            }
            .buttonStyle(.plain)
            .disabled(!broker.redoEnabled)
            .opacity(broker.redoEnabled ? 1 : 0.35)
            .accessibilityLabel(Text(String(localized: "toolbar.redo")))

            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: isPad ? 19 : 17, weight: .medium))
                    .frame(width: iconFrame, height: iconFrame)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "toolbar.export")))

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: isPad ? 18 : 16, weight: .medium))
                    .frame(width: iconFrame, height: iconFrame)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "toolbar.settings")))

            Menu {
                Button(String(localized: "toolbar.more_about"), action: onMoreAbout)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: isPad ? 19 : 17, weight: .medium))
                    .frame(width: iconFrame - 2, height: iconFrame)
            }
            .menuStyle(.button)
            .tint(iconTint)
            .accessibilityLabel(Text(String(localized: "toolbar.more")))
        }
        .foregroundStyle(iconTint)
        .padding(.horizontal, capsuleHPadding)
        .padding(.vertical, isPad ? 11 : 9)
        .background(
            Capsule(style: .continuous)
                .fill(capsuleFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(strokeLine, lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: isPad ? 14 : 10, y: isPad ? 5 : 4)
    }
}
