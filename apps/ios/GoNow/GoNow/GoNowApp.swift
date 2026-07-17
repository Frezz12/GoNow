//
//  GoNowApp.swift
//  GoNow
//
//  Created by Nikolay on 16.07.2026.
//

import SwiftUI

@main
struct GoNowApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .tint(AppColors.accentPrimary)
                .animation(AppAnimation.standard, value: themeManager.mode)
        }
    }
}
