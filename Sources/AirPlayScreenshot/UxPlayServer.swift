//
//  UxPlayServer.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import CoreGraphics
import dnssd
import Foundation
import os
import UxPlay

private let logger = Logger(subsystem: "at.niw.AirPlayScreenshot", category: "UxPlayServer")

// MARK: - UxPlay callbacks (C → Swift)

// The opaque context pointer carries an unretained `UxPlayServer`, set in `start()`.
private func server(from context: UnsafeMutableRawPointer?) -> UxPlayServer? {
    guard let context else {
        return nil
    }
    return Unmanaged<UxPlayServer>.fromOpaque(context).takeUnretainedValue()
}

// MARK: - UxPlayServer

// AirPlay mirroring receiver backed by UxPlay's raop server. Advertises
// itself on Bonjour and emits received events and video data.
final class UxPlayServer: Sendable {
    struct VideoData {
        var data: Data
        var isH265: Bool
    }

    let name: String

    private struct State {
        var raop: OpaquePointer?
        var dnssd: OpaquePointer?
        var port: UInt16?
        var eventHandler: (@Sendable (AirPlayReceiver.Event) -> Void)?
        var videoHandler: (@Sendable (VideoData) -> Void)?
    }

    private let state = OSAllocatedUnfairLock<State>(uncheckedState: State())

    var isRunning: Bool {
        state.withLockUnchecked { $0.raop != nil }
    }

    // Port the raop HTTP server is listening on, available after `start()`.
    var port: UInt16? {
        state.withLockUnchecked { $0.port }
    }

    // Called on UxPlay's threads for connection lifecycle and mirroring
    // state events.
    var eventHandler: (@Sendable (AirPlayReceiver.Event) -> Void)? {
        get {
            state.withLockUnchecked { $0.eventHandler }
        }
        set {
            state.withLockUnchecked { $0.eventHandler = newValue }
        }
    }

    // Called synchronously on UxPlay's video thread for every received NALU
    // chunk — dispatch to your own queue and return quickly.
    var videoHandler: (@Sendable (VideoData) -> Void)? {
        get {
            state.withLockUnchecked { $0.videoHandler }
        }
        set {
            state.withLockUnchecked { $0.videoHandler = newValue }
        }
    }

    init(name: String) {
        self.name = name
    }

    deinit {
        stop()
    }

    private func emit(_ event: AirPlayReceiver.Event) {
        eventHandler?(event)
    }

    func start() throws {
        try state.withLockUnchecked { state in
            guard state.raop == nil else {
                return
            }

            var callbacks = raop_callbacks_t()
            callbacks.cls = Unmanaged.passUnretained(self).toOpaque()

            callbacks.conn_init = { context in
                server(from: context)?.emit(.connectionInitiated)
            }
            callbacks.conn_destroy = { context in
                server(from: context)?.emit(.disconnected)
            }
            callbacks.conn_reset = { context, _ in
                server(from: context)?.emit(.disconnected)
            }
            callbacks.conn_teardown = { _, _, _ in
            }
            callbacks.conn_feedback = { _ in
            }
            callbacks.report_client_request = { context, deviceID, model, name, admit in
                admit?.pointee = true
                server(from: context)?.emit(.clientConnected(
                    name: name.map { String(cString: $0) } ?? "",
                    model: model.map { String(cString: $0) },
                    deviceID: deviceID.map { String(cString: $0) }
                ))
            }

            callbacks.video_set_codec = { _, _ in
                0
            }
            callbacks.video_process = { context, _, data in
                guard let uxPlayServer = server(from: context),
                      let data = data?.pointee,
                      let bytes = data.data,
                      data.data_len > 0
                else {
                    return
                }
                uxPlayServer.videoHandler?(VideoData(
                    data: Data(bytes: bytes, count: Int(data.data_len)),
                    isH265: data.is_h265
                ))
            }
            callbacks.video_pause = { _ in
            }
            callbacks.video_resume = { _ in
            }
            callbacks.video_flush = { _ in
            }
            callbacks.video_reset = { _, _ in
            }
            callbacks.video_report_size = { context, sourceWidth, sourceHeight, _, _ in
                server(from: context)?.emit(.videoSizeChanged(CGSize(
                    width: CGFloat(sourceWidth?.pointee ?? 0),
                    height: CGFloat(sourceHeight?.pointee ?? 0)
                )))
            }
            callbacks.mirror_video_running = { context, isRunning in
                server(from: context)?.emit(isRunning ? .mirroringStarted : .mirroringStopped)
            }

            // Audio: required by handshake but otherwise no-op.

            callbacks.audio_process = { _, _, _ in
            }
            callbacks.audio_flush = { _ in
            }
            callbacks.audio_set_client_volume = { _ in
                0.0
            }
            callbacks.audio_set_volume = { _, _ in
            }
            callbacks.audio_set_metadata = { _, _, _ in
            }
            callbacks.audio_set_coverart = { _, _, _ in
            }
            callbacks.audio_stop_coverart_rendering = { _ in
            }
            callbacks.audio_remote_control_id = { _, _, _ in
            }
            callbacks.audio_set_progress = { _, _, _, _ in
            }
            callbacks.audio_get_format = { _, ct, spf, usingScreen, isMedia, audioFormat in
                ct?.pointee = 2
                spf?.pointee = 480
                usingScreen?.pointee = true
                isMedia?.pointee = false
                audioFormat?.pointee = 0
            }

            // HLS / pin / pairing: no-op.

            callbacks.display_pin = { _, _ in
            }
            callbacks.register_client = { _, _, _, _ in
            }
            callbacks.check_register = { _, _ in
                true
            }
            callbacks.passwd = { _, length in
                length?.pointee = 0
                return nil
            }
            callbacks.export_dacp = { _, _, _ in
            }
            callbacks.on_video_play = { _, _, _ in
            }
            callbacks.on_video_scrub = { _, _ in
            }
            callbacks.on_video_rate = { _, _ in
            }
            callbacks.on_video_stop = { _ in
            }
            callbacks.on_video_acquire_playback_info = { _, _ in
            }
            callbacks.on_video_playlist_remove = { _ in
                0.0
            }

            guard let raop = raop_init(&callbacks) else {
                throw AirPlayReceiverError.raopInitFailed
            }

            raop_set_log_callback(raop, { _, level, message in
                let text = message.map { String(cString: $0) } ?? ""
                if level <= LOGGER_ERR {
                    logger.error("\(text, privacy: .public)")
                } else if level <= LOGGER_WARNING {
                    logger.log("\(text, privacy: .public)")
                } else {
                    logger.debug("\(text, privacy: .public)")
                }
            }, nil)
            raop_set_log_level(raop, LOGGER_INFO)

            let macAddress = Self.persistentMACAddress
            // raop_init2 expects a colon-separated hex string like "aa:bb:cc:dd:ee:ff".
            let macAddressString = macAddress.map { String(format: "%02x", $0) }.joined(separator: ":")
            guard raop_init2(raop, 1, macAddressString, Self.keyFilePath) == 0 else {
                raop_destroy(raop)
                throw AirPlayReceiverError.raopConfigurationFailed
            }

            var port: UInt16 = 0
            // httpd_start returns 1 on success, 0 when already running, and
            // negative values on socket errors.
            guard raop_start_httpd(raop, &port) > 0 else {
                raop_destroy(raop)
                throw AirPlayReceiverError.raopStartFailed
            }
            raop_set_port(raop, port)

            var dnssdError: Int32 = 0
            // dnssd_init wants raw 6-byte hardware address.
            let dnssd = macAddress.withUnsafeBufferPointer { buffer in
                buffer.withMemoryRebound(to: CChar.self) { buffer in
                    dnssd_init(name, Int32(name.utf8.count), buffer.baseAddress, Int32(buffer.count), &dnssdError, 0)
                }
            }
            guard let dnssd, dnssdError == 0 else {
                if let dnssd {
                    dnssd_destroy(dnssd)
                }
                raop_destroy(raop)
                throw AirPlayReceiverError.dnssdInitFailed(code: dnssdError)
            }

            // raop_set_dnssd populates the dnssd public-key string used by the TXT records,
            // so it MUST be called before dnssd_register_* (otherwise strlen(NULL) crash).
            raop_set_dnssd(raop, dnssd)

            // Register on kDNSServiceInterfaceIndexLocalOnly so that other processes on
            // the SAME device can discover us via Bonjour. (Useful when testing locally
            // — the system Screen Mirroring picker still filters same-device services,
            // but Bonjour browsers will see this.)
            let raopError = dnssd_register_raop_iface(dnssd, port, kDNSServiceInterfaceIndexLocalOnly)
            let airplayError = dnssd_register_airplay_iface(dnssd, port, kDNSServiceInterfaceIndexLocalOnly)
            if raopError != 0 || airplayError != 0 {
                logger.error("dnssd_register failed raop=\(raopError) airplay=\(airplayError)")
            }

            state.raop = raop
            state.dnssd = dnssd
            state.port = port

            logger.log("UxPlayServer started on port \(port) as \"\(self.name, privacy: .public)\"")
        }
    }

    func stop() {
        let resources = state.withLockUnchecked { state -> (raop: OpaquePointer?, dnssd: OpaquePointer?) in
            defer {
                state.raop = nil
                state.dnssd = nil
                state.port = nil
            }
            return (state.raop, state.dnssd)
        }
        if let dnssd = resources.dnssd {
            dnssd_unregister_raop(dnssd)
            dnssd_unregister_airplay(dnssd)
            dnssd_destroy(dnssd)
        }
        if let raop = resources.raop {
            raop_destroy(raop)
        }
    }

    // MARK: - Persistent identifiers

    private static var keyFilePath: String {
        URL.documentsDirectory.appendingPathComponent("uxplay.pem").path(percentEncoded: false)
    }

    private static var persistentMACAddress: [UInt8] {
        let defaults = UserDefaults.standard
        if let cached = defaults.data(forKey: "airplay.macAddress"), cached.count == 6 {
            return [UInt8](cached)
        }
        var address = [UInt8](repeating: 0, count: 6)
        address.withUnsafeMutableBytes { buffer in
            arc4random_buf(buffer.baseAddress, buffer.count)
        }
        address[0] &= 0xFE // ensure unicast
        address[0] |= 0x02 // ensure locally-administered
        defaults.set(Data(address), forKey: "airplay.macAddress")
        return address
    }
}
