//
//  PreviewAirPlayReceiverService.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class PreviewAirPlayReceiverService: AirPlayReceiverServiceProtocol {
    private(set) var statusText: LocalizedStringKey = "Mirroring from Preview — tap Capture"
    private(set) var isMirroring: Bool = true
    private(set) var capturedImage: UIImage?
    private(set) var capturedFrames: [CapturedFrame] = []
    private(set) var isAutoCapturing: Bool = false

    private var autoCaptureTask: Task<Void, Never>?

    func start() {
        statusText = "Advertised as \"Preview\""
    }

    func captureCurrentFrame() {
        let frame = makePlaceholderFrame()
        appendFrame(frame)
        statusText = "Captured at \(CapturedFrame.timeFormatter.string(from: frame.timestamp))"
    }

    func startAutoCapture() {
        guard !isAutoCapturing else {
            return
        }
        isAutoCapturing = true
        autoCaptureTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tickAutoCapture()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func tickAutoCapture() {
        appendFrame(makePlaceholderFrame())
    }

    func stopAutoCapture() {
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
        isAutoCapturing = false
    }

    func clearCapturedFrames() {
        capturedFrames.removeAll()
        capturedImage = nil
    }

    private func appendFrame(_ frame: CapturedFrame) {
        capturedImage = frame.image
        capturedFrames.append(frame)
        if capturedFrames.count > CapturedFrame.maxCount {
            capturedFrames.removeFirst(capturedFrames.count - CapturedFrame.maxCount)
        }
    }

    private func makePlaceholderFrame() -> CapturedFrame {
        let size = CGSize(width: 320, height: 200)
        let hue = CGFloat(capturedFrames.count % 8) / 8.0
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: hue, saturation: 0.5, brightness: 0.8, alpha: 1.0)
                .setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return CapturedFrame(timestamp: Date(), image: image)
    }
}
