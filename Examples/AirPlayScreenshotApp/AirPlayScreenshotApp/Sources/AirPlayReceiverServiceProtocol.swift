//
//  AirPlayReceiverServiceProtocol.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import Foundation
import Observation
import SwiftUI
import UIKit

struct CapturedFrame: Identifiable {
    static let maxCount: Int = 60

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var id: UUID = .init()
    var timestamp: Date
    var image: UIImage
}

@MainActor
protocol AirPlayReceiverServiceProtocol: AnyObject, Observable {
    var statusText: LocalizedStringKey { get }
    var isMirroring: Bool { get }
    var capturedImage: UIImage? { get }
    var capturedFrames: [CapturedFrame] { get }
    var isAutoCapturing: Bool { get }

    func start()
    func captureCurrentFrame()
    func startAutoCapture()
    func stopAutoCapture()
    func clearCapturedFrames()
}

@MainActor
@Observable
final class AnyAirPlayReceiverService: AirPlayReceiverServiceProtocol {
    private let service: any AirPlayReceiverServiceProtocol

    init(_ service: some AirPlayReceiverServiceProtocol) {
        self.service = service
    }

    var statusText: LocalizedStringKey {
        service.statusText
    }

    var isMirroring: Bool {
        service.isMirroring
    }

    var capturedImage: UIImage? {
        service.capturedImage
    }

    var capturedFrames: [CapturedFrame] {
        service.capturedFrames
    }

    var isAutoCapturing: Bool {
        service.isAutoCapturing
    }

    func start() {
        service.start()
    }

    func captureCurrentFrame() {
        service.captureCurrentFrame()
    }

    func startAutoCapture() {
        service.startAutoCapture()
    }

    func stopAutoCapture() {
        service.stopAutoCapture()
    }

    func clearCapturedFrames() {
        service.clearCapturedFrames()
    }
}

extension AirPlayReceiverServiceProtocol {
    func eraseToAnyAirPlayReceiverService() -> AnyAirPlayReceiverService {
        AnyAirPlayReceiverService(self)
    }
}
