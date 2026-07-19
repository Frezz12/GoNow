//
//  GoNowApp.swift
//  GoNow
//
//  Created by Nikolay on 16.07.2026.
//

import SwiftUI

@main
struct GoNowApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationCoordinator.self) private var pushNotifications
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var localizationManager = LocalizationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(localizationManager)
                .environmentObject(pushNotifications)
                .environment(\.locale, localizationManager.locale)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .tint(AppColors.accentPrimary)
        }
    }
}
