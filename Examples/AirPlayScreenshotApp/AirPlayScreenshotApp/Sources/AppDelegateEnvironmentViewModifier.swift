//
//  AppDelegateEnvironmentViewModifier.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import Foundation
import SwiftUI

struct AppDelegateEnvironmentViewModifier: ViewModifier {
    var appDelegate: AppDelegate

    func body(content: Content) -> some View {
        content
            .environment(appDelegate.airPlayReceiverService.eraseToAnyAirPlayReceiverService())
    }
}

extension View {
    func appDelegateEnvironment(appDelegate: AppDelegate) -> some View {
        modifier(AppDelegateEnvironmentViewModifier(appDelegate: appDelegate))
    }
}
