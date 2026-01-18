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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(proStatus)
        }
    }
}
