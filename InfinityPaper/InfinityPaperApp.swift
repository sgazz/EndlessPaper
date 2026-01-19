//
//  InfinityPaperApp.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import SwiftUI

@main
struct InfinityPaperApp: App {
    @State private var showSplash = true
    @State private var mainOpacity = 0.0
    @State private var splashOpacity = 1.0
    @State private var didStartTransition = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(mainOpacity)
                    .allowsHitTesting(!showSplash)
                SplashView()
                    .opacity(splashOpacity)
                    .allowsHitTesting(showSplash)
            }
            .onAppear {
                guard !didStartTransition else { return }
                didStartTransition = true
                mainOpacity = 0
                splashOpacity = 1
                let overlapStart = 2.2
                DispatchQueue.main.asyncAfter(deadline: .now() + overlapStart) {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        mainOpacity = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        splashOpacity = 0
                    }
                    showSplash = false
                }
            }
        }
    }
}

private struct SplashView: View {
    private let splashBackground = Color(.sRGB, red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0, opacity: 1.0)
    @State private var logoOpacity = 0.0

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()
            Image("InfinityPapir")
                .resizable()
                .scaledToFit()
                .padding(24)
                .ignoresSafeArea()
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
