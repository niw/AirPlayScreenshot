//
//  OpenH264Decoder.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import CoreVideo
import Foundation
import OpenH264
import os
import Synchronization

private let logger = Logger(subsystem: "at.niw.AirPlayScreenshot", category: "OpenH264Decoder")

// Pure software AVC (H.264) decoder backed by Cisco openh264's `ISVCDecoder`.
// Works regardless of app foreground/background state, unlike VideoToolbox.
//
// `decode(annexB:)` must be called serially (the underlying `ISVCDecoder` is
// not thread-safe); `latestPixelBuffer` is safe to read from any thread.
final class OpenH264Decoder: @unchecked Sendable {
    // In C, `ISVCDecoder` is `const ISVCDecoderVtbl *`, so methods are
    // invoked through the vtbl: `decoder.pointee!.pointee.Method(decoder, ...)`.
    private let decoder: UnsafeMutablePointer<ISVCDecoder?>

    // Latest decoded frame, replaced per decoded picture. Snapshot consumers
    // read `latestPixelBuffer` and never block the decode queue.
    private let latestPixelBufferSlot = OSAllocatedUnfairLock<CVPixelBuffer?>(uncheckedState: nil)

    // One-shot logging flags, lock-free access from any thread.
    private let firstReferenceLostLogged = Atomic<Bool>(false)
    private let firstBitstreamErrorLogged = Atomic<Bool>(false)

    init?() {
        var decoder: UnsafeMutablePointer<ISVCDecoder?>?
        guard WelsCreateDecoder(&decoder) == 0, let decoder, decoder.pointee != nil else {
            logger.error("WelsCreateDecoder failed")
            return nil
        }

        var param = SDecodingParam()
        // Matches openh264's `h264dec` reference sample: UCHAR_MAX selects all
        // spatial layers (SVC). For AVC streams this is the canonical value.
        param.uiTargetDqLayer = .max
        param.eEcActiveIdc = ERROR_CON_DISABLE
        param.bParseOnly = false
        param.sVideoProperty.eVideoBsType = VIDEO_BITSTREAM_AVC

        guard decoder.pointee!.pointee.Initialize(decoder, &param) == Int(cmResultSuccess.rawValue) else {
            logger.error("ISVCDecoder Initialize failed")
            WelsDestroyDecoder(decoder)
            return nil
        }

        self.decoder = decoder
        logger.log("openh264 decoder initialized (version \(OPENH264_MAJOR).\(OPENH264_MINOR).\(OPENH264_REVISION))")
    }

    deinit {
        _ = decoder.pointee!.pointee.Uninitialize(decoder)
        WelsDestroyDecoder(decoder)
    }

    // MARK: - Decode

    func decode(annexB data: Data) {
        // Feed each NALU individually. openh264's DecodeFrameNoDelay is
        // slice-level — multi-NALU buffers cause it to process only the first
        // and silently drop the rest.
        AnnexB.enumerateNALUs(in: data, includingStartCode: true) { nalu in
            decodeNALU(nalu.baseAddress!, length: nalu.count)
        }
    }

    // The most recently decoded NV12 pixel buffer (BT.601 video range), or
    // nil if no frame is available yet.
    var latestPixelBuffer: CVPixelBuffer? {
        latestPixelBufferSlot.withLockUnchecked { $0 }
    }

    private func decodeNALU(_ bytes: UnsafePointer<UInt8>, length: Int) {
        var bufferInfo = SBufferInfo()
        var yuv: [UnsafeMutablePointer<UInt8>?] = [nil, nil, nil]

        let state = decoder.pointee!.pointee.DecodeFrameNoDelay(decoder, bytes, Int32(length), &yuv, &bufferInfo)
        if state != dsErrorFree {
            // Log each error class once so Console isn't flooded but qualitative
            // failures still surface during diagnostics.
            if state.rawValue & dsRefLost.rawValue != 0,
               firstReferenceLostLogged.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged
            {
                logger.log("first dsRefLost observed (state=0x\(String(state.rawValue, radix: 16), privacy: .public))")
            }
            if state.rawValue & dsBitstreamError.rawValue != 0,
               firstBitstreamErrorLogged.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged
            {
                logger.log("first dsBitstreamError observed (state=0x\(String(state.rawValue, radix: 16), privacy: .public))")
            }
        }
        guard bufferInfo.iBufferStatus == 1 else {
            return
        }

        let systemBuffer = bufferInfo.UsrData.sSystemBuffer
        let width = Int(systemBuffer.iWidth)
        let height = Int(systemBuffer.iHeight)
        guard width > 0, height > 0, let y = yuv[0], let u = yuv[1], let v = yuv[2] else {
            return
        }

        guard let pixelBuffer = makePixelBuffer(
            y: y,
            u: u,
            v: v,
            width: width,
            height: height,
            strideY: Int(systemBuffer.iStride.0),
            strideUV: Int(systemBuffer.iStride.1)
        ) else {
            return
        }

        latestPixelBufferSlot.withLockUnchecked { latestPixelBuffer in
            latestPixelBuffer = pixelBuffer
        }
    }

    // Build an NV12 (BT.601 video range, biplanar) CVPixelBuffer from openh264's
    // I420 output.
    private func makePixelBuffer(
        y: UnsafePointer<UInt8>,
        u: UnsafePointer<UInt8>,
        v: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        strideY: Int,
        strideUV: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            logger.error("CVPixelBufferCreate failed (\(status))")
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        // Plane 0: Y (full resolution).
        let destinationY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let destinationStrideY = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        for row in 0 ..< height {
            memcpy(destinationY + row * destinationStrideY, y + row * strideY, width)
        }

        // Plane 1: CbCr interleaved at half resolution.
        let widthUV = width / 2
        let heightUV = height / 2
        let destinationUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let destinationStrideUV = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        for row in 0 ..< heightUV {
            let sourceU = u + row * strideUV
            let sourceV = v + row * strideUV
            let destination = destinationUV + row * destinationStrideUV
            for column in 0 ..< widthUV {
                destination[column * 2] = sourceU[column]
                destination[column * 2 + 1] = sourceV[column]
            }
        }

        return pixelBuffer
    }
}
