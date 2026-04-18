//
//  InfinityPaperApp.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import SwiftUI

@main
struct InfinityPaperApp: App {
    @State private var mainOpacity = 0.0
    @State private var splashOpacity = 1.0
    @State private var didStartTransition = false
    @State private var isMainHitTestingEnabled = false
    /// After the splash fade completes, remove the splash layer from the hierarchy.
    @State private var splashLayerRemoved = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(mainOpacity)
                    .allowsHitTesting(isMainHitTestingEnabled)
                if !splashLayerRemoved {
                    SplashView()
                        .opacity(splashOpacity)
                        .allowsHitTesting(!isMainHitTestingEnabled)
                }
            }
            .onAppear {
                guard !didStartTransition else { return }
                didStartTransition = true
                mainOpacity = 0
                splashOpacity = 1
                isMainHitTestingEnabled = false
                let overlapStart = 2.2
                DispatchQueue.main.asyncAfter(deadline: .now() + overlapStart) {
                    isMainHitTestingEnabled = true
                    withAnimation(.easeInOut(duration: 0.8)) {
                        mainOpacity = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let fadeDuration: TimeInterval = 0.6
                    withAnimation(.easeInOut(duration: fadeDuration)) {
                        splashOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
                        splashLayerRemoved = true
                    }
                }
            }
        }
    }
}

private struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var logoOpacity = 0.0

    /// Slightly richer than canvas (#F8F5EE / #232220) for a soft, premium handoff.
    private var splashBackground: Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                UIColor(red: 29.0 / 255.0, green: 28.0 / 255.0, blue: 26.0 / 255.0, alpha: 1.0) // #1D1C1A
            } else {
                UIColor(red: 243.0 / 255.0, green: 238.0 / 255.0, blue: 228.0 / 255.0, alpha: 1.0) // #F3EEE4
            }
        })
    }

    /// Whisper line: explicit contrast on warm light vs deep dark splash (avoids muddy `.secondary` on #1D1C1A).
    private var whisperForeground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.58)
            : Color.black.opacity(0.4)
    }

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image("InfinityPapir")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 24)
                Text(NSLocalizedString("splash.whisper", comment: "Brief calm line on launch splash"))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(whisperForeground)
                    .padding(.horizontal, 40)
            }
            .opacity(logoOpacity)
        }
        .onAppear {
            logoOpacity = 0
            withAnimation(.easeOut(duration: 1.1)) {
                logoOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    logoOpacity = 0.88
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) {
                withAnimation(.easeInOut(duration: 1.25)) {
                    logoOpacity = 0
                }
            }
        }
    }
}
