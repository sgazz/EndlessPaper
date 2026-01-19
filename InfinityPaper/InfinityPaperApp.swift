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

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                } else {
                    ContentView()
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showSplash = false
                }
            }
        }
    }
}

private struct SplashView: View {
    private let splashBackground = Color(.sRGB, red: 250.0 / 255.0, green: 247.0 / 255.0, blue: 243.0 / 255.0, opacity: 1.0)
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
