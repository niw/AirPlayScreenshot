//
//  AppDelegate.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import AirPlayScreenshot
import Foundation
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let airPlayReceiverService: AirPlayReceiverService
    let backgroundAudioService: BackgroundAudioService

    override init() {
        // Pick the decoder backend here. `.openH264` works in foreground and
        // background; `.videoToolbox` is hardware-accelerated but stops decoding
        // when the app is backgrounded.
        airPlayReceiverService = AirPlayReceiverService(
            name: "AirPlayScreenshotApp",
            decoderKind: .openH264
        )
        backgroundAudioService = BackgroundAudioService()

        super.init()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        backgroundAudioService.stop()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundAudioService.start()
    }
}
