//
//  InfinityPaperApp.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import SwiftUI

@main
struct InfinityPaperApp: App {
    @StateObject private var proStatus = ProStatus()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                } else {
                    ContentView()
                        .environmentObject(proStatus)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showSplash = false
                }
            }
        }
    }
}

private struct SplashView: View {
    private let splashBackground = Color(.sRGB, red: 250.0 / 255.0, green: 247.0 / 255.0, blue: 243.0 / 255.0, opacity: 1.0)

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()
            Image("InfinityPapir")
                .resizable()
                .scaledToFit()
                .padding(24)
                .ignoresSafeArea()
        }
    }
}
