//
//  OpenH264VideoDecoder.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import CoreVideo
import Foundation
import os
import UIKit

/// Pure-software H.264 decoder backed by Cisco openh264. Works regardless of
/// app lifecycle state (foreground/background) because it doesn't go through
/// VideoToolbox, at the cost of more CPU.
final class OpenH264VideoDecoder: VideoDecoder {
    private let queue = DispatchQueue(label: "at.niw.AirPlayScreenshot.openh264", qos: .userInitiated)

    // Created in `start()` and read from the decode queue and capture
    // callers afterwards.
    private let decoderSlot = OSAllocatedUnfairLock<OpenH264Decoder?>(uncheckedState: nil)

    private var decoder: OpenH264Decoder? {
        decoderSlot.withLockUnchecked { $0 }
    }

    func start() {
        decoderSlot.withLockUnchecked { decoder in
            if decoder == nil {
                decoder = OpenH264Decoder()
            }
        }
    }

    func process(naluData: Data) {
        queue.async { [weak self] in
            self?.decoder?.decode(annexB: naluData)
        }
    }

    func capture() -> UIImage? {
        // No queue.sync — the decoder keeps the latest CVPixelBuffer in a
        // lock-protected slot, fetching it never blocks the decode queue.
        guard let pixelBuffer = decoder?.latestPixelBuffer else {
            return nil
        }
        return image(from: pixelBuffer)
    }
}
