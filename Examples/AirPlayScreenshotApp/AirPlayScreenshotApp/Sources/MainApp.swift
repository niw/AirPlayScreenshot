//
//  MainApp.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import SwiftUI

@main
struct MainApp: App {
    @UIApplicationDelegateAdaptor
    private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .appDelegateEnvironment(appDelegate: appDelegate)
        }
    }
}
