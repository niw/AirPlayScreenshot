//
//  BackgroundAudioService.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import AVFoundation
import Foundation

@MainActor
final class BackgroundAudioService {
    private let audioPlayer: AVPlayer

    init() {
        let playerItem = AVPlayerItem(url: URL(fileURLWithPath: ""))
        audioPlayer = AVPlayer(playerItem: playerItem)

        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, mode: .default, options: .mixWithOthers)
    }

    private func setActive(_ state: Bool) {
        try? AVAudioSession.sharedInstance().setActive(state)
    }

    func start() {
        setActive(true)
        audioPlayer.play()
    }

    func stop() {
        audioPlayer.pause()
        setActive(false)
    }
}
