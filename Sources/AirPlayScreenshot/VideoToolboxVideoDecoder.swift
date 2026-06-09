//
//  VideoToolboxVideoDecoder.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import CoreMedia
import CoreVideo
import Foundation
import os
import UIKit
import VideoToolbox

private let logger = Logger(subsystem: "at.niw.AirPlayScreenshot", category: "VideoToolboxVideoDecoder")

/// Hardware-accelerated H.264 decoder backed by VideoToolbox. Fast and power-
/// efficient in the foreground, but VTDecompressionSession is gated to
/// foreground apps — output silently stops when the app is backgrounded
/// (and the H.264 reference chain is lost shortly after, so even returning
/// to foreground won't recover until the next IDR).
final class VideoToolboxVideoDecoder: VideoDecoder, @unchecked Sendable {
    private let queue = DispatchQueue(label: "at.niw.AirPlayScreenshot.videotoolbox", qos: .userInitiated)

    // Decoder state — only touched on `queue`.
    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?

    // Latest decoded frame.
    private let latestPixelBufferSlot = OSAllocatedUnfairLock<CVPixelBuffer?>(uncheckedState: nil)

    deinit {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    func start() {
        // VideoToolbox session is created lazily once we have SPS/PPS — nothing to do
        // here.
    }

    func process(naluData: Data) {
        queue.async { [weak self] in
            self?.processOnQueue(annexB: naluData)
        }
    }

    func capture() -> UIImage? {
        guard let pixelBuffer = latestPixelBufferSlot.withLockUnchecked({ $0 }) else {
            return nil
        }
        return image(from: pixelBuffer)
    }

    // MARK: - Decode pipeline

    private func processOnQueue(annexB: Data) {
        var unitsToDecode: [Data] = []
        AnnexB.enumerateNALUs(in: annexB, includingStartCode: false) { nalu in
            let unit = Data(buffer: nalu)
            switch nalu[0] & 0x1F {
            // SPS
            case 7:
                if sps != unit {
                    sps = unit
                    invalidateSession()
                }
            // PPS
            case 8:
                if pps != unit {
                    pps = unit
                    invalidateSession()
                }
            default:
                unitsToDecode.append(unit)
            }
        }

        if session == nil {
            createSessionIfPossible()
        }
        guard let session, let formatDescription else {
            return
        }

        for nalu in unitsToDecode {
            decodeNALU(nalu, session: session, formatDescription: formatDescription)
        }
    }

    private func invalidateSession() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    private func createSessionIfPossible() {
        guard let sps, let pps else {
            return
        }
        var newFormatDescription: CMVideoFormatDescription?
        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress!
                let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress!
                let pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                let sizes: [Int] = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &newFormatDescription
                        )
                    }
                }
            }
        }
        guard status == noErr, let newFormatDescription else {
            logger.error("CMVideoFormatDescriptionCreate failed (\(status))")
            return
        }
        formatDescription = newFormatDescription

        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        var session: VTDecompressionSession?
        let sessionStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: newFormatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )
        guard sessionStatus == noErr, let session else {
            logger.error("VTDecompressionSessionCreate failed (\(sessionStatus))")
            return
        }
        self.session = session
    }

    private func decodeNALU(_ nalu: Data, session: VTDecompressionSession, formatDescription: CMVideoFormatDescription) {
        // Build AVCC (4-byte big-endian length prefix + NALU bytes) directly
        // in a block that the CMBlockBuffer takes ownership of.
        let avccLength = 4 + nalu.count
        let avccBytes = UnsafeMutableRawPointer.allocate(byteCount: avccLength, alignment: 1)
        withUnsafeBytes(of: UInt32(nalu.count).bigEndian) { length in
            avccBytes.copyMemory(from: length.baseAddress!, byteCount: 4)
        }
        nalu.withUnsafeBytes { bytes in
            avccBytes.advanced(by: 4).copyMemory(from: bytes.baseAddress!, byteCount: nalu.count)
        }

        var blockBuffer: CMBlockBuffer?
        let blockBufferStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: avccBytes,
            blockLength: avccLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockBufferStatus == noErr, let blockBuffer else {
            avccBytes.deallocate()
            return
        }

        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avccLength
        let sampleBufferStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleBufferStatus == noErr, let sampleBuffer else {
            return
        }

        var flagsOut: VTDecodeInfoFlags = []
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [],
            infoFlagsOut: &flagsOut,
            outputHandler: { [weak self] status, _, imageBuffer, _, _ in
                guard let self, status == noErr, let imageBuffer else {
                    return
                }
                latestPixelBufferSlot.withLockUnchecked { latestPixelBuffer in
                    latestPixelBuffer = imageBuffer
                }
            }
        )
    }
}
