//
//  AirPlayReceiverService.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import AirPlayScreenshot
import Foundation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AirPlayReceiverService: AirPlayReceiverServiceProtocol {
    private static let waitingStatusText: LocalizedStringKey = "Waiting for sender to start mirroring…"

    private(set) var statusText: LocalizedStringKey = AirPlayReceiverService.waitingStatusText
    private(set) var isMirroring: Bool = false
    private(set) var capturedImage: UIImage?
    private(set) var currentClientName: String?
    private(set) var capturedFrames: [CapturedFrame] = []
    private(set) var isAutoCapturing: Bool = false

    private let receiver: AirPlayReceiver
    private var autoCaptureTask: Task<Void, Never>?

    init(name: String, decoderKind: VideoDecoderKind = .openH264) {
        let receiver = AirPlayReceiver(name: name, decoderKind: decoderKind)
        self.receiver = receiver
        // The loop ends when the receiver deallocates and finishes the
        // stream, so the task doesn't need to be retained for cancellation.
        Task { [weak self, events = receiver.events] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    func start() {
        do {
            try receiver.start()
            statusText = "Advertised as \"\(receiver.name)\" on port \(receiver.port ?? 0)"
        } catch {
            statusText = "Failed to start: \(error.localizedDescription)"
        }
    }

    func captureCurrentFrame() {
        if let frame = makeFrame() {
            appendFrame(frame)
            statusText = "Captured at \(CapturedFrame.timeFormatter.string(from: frame.timestamp))"
        } else {
            statusText = "No frame available yet"
        }
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

    func stopAutoCapture() {
        autoCaptureTask?.cancel()
        autoCaptureTask = nil
        isAutoCapturing = false
    }

    func clearCapturedFrames() {
        capturedFrames.removeAll()
        capturedImage = nil
    }

    private func tickAutoCapture() {
        if let frame = makeFrame() {
            appendFrame(frame)
        }
    }

    private func makeFrame() -> CapturedFrame? {
        guard let image = receiver.capture() else {
            return nil
        }
        return CapturedFrame(timestamp: Date(), image: image)
    }

    private func appendFrame(_ frame: CapturedFrame) {
        capturedImage = frame.image
        capturedFrames.append(frame)
        if capturedFrames.count > CapturedFrame.maxCount {
            capturedFrames.removeFirst(capturedFrames.count - CapturedFrame.maxCount)
        }
    }

    // MARK: - Receiver events

    private func handle(_ event: AirPlayReceiver.Event) {
        switch event {
        case .connectionInitiated:
            statusText = "Client connecting…"
        case .clientConnected(let name, _, _):
            currentClientName = name
            statusText = "\(name) is connecting…"
        case .disconnected:
            currentClientName = nil
            isMirroring = false
            statusText = Self.waitingStatusText
        case .mirroringStarted:
            isMirroring = true
            if let name = currentClientName {
                statusText = "Mirroring from \(name) — tap Capture"
            } else {
                statusText = "Mirroring active — tap Capture"
            }
        case .mirroringStopped:
            isMirroring = false
            statusText = "Mirroring stopped"
        case .videoSizeChanged:
            break
        }
    }
}
