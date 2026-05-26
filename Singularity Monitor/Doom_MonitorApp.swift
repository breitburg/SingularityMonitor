//
//  Doom_MonitorApp.swift
//  Doom Monitor
//
//  Created by Ilia Breitburg on 14/05/2026.
//

import SwiftUI

@main
struct Doom_MonitorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Terminate on backgrounding so every reopen is a cold launch
            // and counts as a new "Last App Open" in iOS system metrics.
            if newPhase == .background {
                exit(0)
            }
        }
    }
}
