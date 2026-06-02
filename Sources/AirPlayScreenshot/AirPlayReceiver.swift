//
//  AirPlayReceiver.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import CoreGraphics
import Foundation
import UIKit

/// Errors thrown by `AirPlayReceiver.start()`.
public enum AirPlayReceiverError: LocalizedError {
    case raopInitFailed
    case raopConfigurationFailed
    case raopStartFailed
    case dnssdInitFailed(code: Int32)

    public var errorDescription: String? {
        switch self {
        case .raopInitFailed:
            "Failed to initialize the AirPlay server."
        case .raopConfigurationFailed:
            "Failed to configure the AirPlay server."
        case .raopStartFailed:
            "Failed to start the AirPlay server."
        case .dnssdInitFailed(let code):
            "Failed to register the Bonjour service (\(code))."
        }
    }
}

/// AirPlay mirroring receiver. Advertises itself on Bonjour, decodes the
/// incoming H.264 stream, and renders the latest frame on demand with
/// `capture()`.
public final class AirPlayReceiver: Sendable {
    public enum Event: Sendable {
        case connectionInitiated
        case clientConnected(name: String, model: String?, deviceID: String?)
        case disconnected
        case mirroringStarted
        case mirroringStopped
        case videoSizeChanged(CGSize)
    }

    public let name: String
    public let decoderKind: VideoDecoderKind

    // Connection lifecycle and mirroring state events. Single consumer.
    public let events: AsyncStream<Event>

    private let continuation: AsyncStream<Event>.Continuation
    private let server: UxPlayServer
    private let decoder: any VideoDecoder

    public var isRunning: Bool {
        server.isRunning
    }

    // Port the receiver is listening on, available after `start()`.
    public var port: UInt16? {
        server.port
    }

    public init(
        name: String = "AirPlayScreenshot",
        decoderKind: VideoDecoderKind = .openH264
    ) {
        let server = UxPlayServer(name: name)
        let decoder: any VideoDecoder = switch decoderKind {
        case .videoToolbox:
            VideoToolboxVideoDecoder()
        case .openH264:
            OpenH264VideoDecoder()
        }
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        server.videoHandler = { [decoder] video in
            // Neither backend decodes H.265 yet.
            guard !video.isH265 else {
                return
            }
            decoder.process(naluData: video.data)
        }
        server.eventHandler = { [continuation] event in
            continuation.yield(event)
        }
        self.name = name
        self.decoderKind = decoderKind
        self.server = server
        self.decoder = decoder
    }

    deinit {
        continuation.finish()
    }

    /// Start advertising and receiving. Call from the main thread in the
    /// foreground BEFORE mirroring starts — openh264 spawns worker pthreads
    /// and we want those created with foreground priority.
    public func start() throws {
        guard !server.isRunning else {
            return
        }
        decoder.start()
        try server.start()
    }

    public func stop() {
        server.stop()
    }

    /// Render the latest decoded frame, or nil if nothing has been decoded
    /// yet. Safe to call from any thread.
    public func capture() -> UIImage? {
        decoder.capture()
    }
}
