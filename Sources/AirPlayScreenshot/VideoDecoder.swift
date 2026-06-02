//
//  VideoDecoder.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import CoreVideo
import Foundation
import UIKit

// Shared software-rendering context: capture must also work while the app is
// backgrounded, where GPU access is prohibited.
private let ciContext = CIContext(options: [.useSoftwareRenderer: true])

/// Identifier for the available H.264 decoding backends, chosen when
/// creating an `AirPlayReceiver`.
public enum VideoDecoderKind: Sendable {
    case videoToolbox
    case openH264
}

/// Common interface implemented by both the openh264 and VideoToolbox
/// backends. Methods must be safe to call from any thread.
protocol VideoDecoder: AnyObject, Sendable {
    /// Bring the decoder online. Called from the foreground / main thread
    /// before any NALUs are pushed so any worker threads are spawned with
    /// foreground priority.
    func start()
    /// Feed an H.264 Annex-B NALU chunk to the decoder.
    func process(naluData: Data)
    /// Render the latest decoded frame as a UIImage, or nil if nothing has
    /// been decoded yet.
    func capture() -> UIImage?
}

extension VideoDecoder {
    /// Render a decoded pixel buffer into a UIImage.
    func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}
