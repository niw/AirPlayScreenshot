//
//  AnnexB.swift
//  AirPlayScreenshot
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import Foundation

/// Annex-B elementary stream parsing shared by the decoder backends.
enum AnnexB {
    /// Walks the stream and invokes `body` once per NALU. openh264 wants
    /// NALUs with their start codes; VideoToolbox wants the bare payload for
    /// AVCC repacking — `includingStartCode` selects which.
    static func enumerateNALUs(
        in data: Data,
        includingStartCode: Bool,
        _ body: (UnsafeBufferPointer<UInt8>) -> Void
    ) {
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let bytes = buffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            let length = buffer.count
            var naluStart = -1
            var index = 0
            while index + 3 < length {
                let isFourBytesStartCode = bytes[index] == 0 && bytes[index + 1] == 0 && bytes[index + 2] == 0 && bytes[index + 3] == 1
                let isThreeBytesStartCode = !isFourBytesStartCode && bytes[index] == 0 && bytes[index + 1] == 0 && bytes[index + 2] == 1
                if isThreeBytesStartCode || isFourBytesStartCode {
                    if naluStart >= 0, index > naluStart {
                        body(UnsafeBufferPointer(start: bytes + naluStart, count: index - naluStart))
                    }
                    let startCodeLength = isFourBytesStartCode ? 4 : 3
                    naluStart = includingStartCode ? index : index + startCodeLength
                    index += startCodeLength
                    continue
                }
                index += 1
            }
            if naluStart >= 0, naluStart < length {
                body(UnsafeBufferPointer(start: bytes + naluStart, count: length - naluStart))
            }
        }
    }
}
