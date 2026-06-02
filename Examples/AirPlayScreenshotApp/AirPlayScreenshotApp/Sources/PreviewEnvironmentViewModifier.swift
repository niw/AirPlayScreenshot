//
//  PreviewEnvironmentViewModifier.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import Foundation
import SwiftUI

struct PreviewEnvironmentViewModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(PreviewAirPlayReceiverService().eraseToAnyAirPlayReceiverService())
    }
}

extension View {
    func previewEnvironment() -> some View {
        modifier(PreviewEnvironmentViewModifier())
    }
}
