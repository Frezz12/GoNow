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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
