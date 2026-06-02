//
//  MainView.swift
//  AirPlayScreenshotApp
//
//  Created by Claude Opus 4.8 on 6/5/26.
//

import SwiftUI

struct MainView: View {
    @Environment(AnyAirPlayReceiverService.self)
    private var service

    var body: some View {
        VStack(spacing: 12) {
            Text(service.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top)

            ZStack {
                Color.black
                if let image = service.capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tv")
                            .font(.system(size: 64))
                            .foregroundStyle(.white.opacity(0.4))
                        Text("No capture yet")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button {
                    service.captureCurrentFrame()
                } label: {
                    Label("Capture", systemImage: "camera.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!service.isMirroring)

                Button {
                    if service.isAutoCapturing {
                        service.stopAutoCapture()
                    } else {
                        service.startAutoCapture()
                    }
                } label: {
                    Label(service.isAutoCapturing ? "Stop 1s" : "Auto 1s",
                          systemImage: service.isAutoCapturing ? "stop.circle" : "timer")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(service.isAutoCapturing ? .red : .accentColor)
            }
            .padding(.horizontal)

            capturedList
                .padding(.bottom)
        }
        .onAppear { service.start() }
    }

    private var capturedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History (\(service.capturedFrames.count)/\(CapturedFrame.maxCount))")
                    .font(.headline)
                Spacer()
                if !service.capturedFrames.isEmpty {
                    Button("Clear") {
                        service.clearCapturedFrames()
                    }
                    .font(.callout)
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(service.capturedFrames.reversed()) { frame in
                        VStack(spacing: 4) {
                            Image(uiImage: frame.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(CapturedFrame.timeFormatter.string(from: frame.timestamp))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 110)
        }
    }
}

#Preview {
    MainView()
        .previewEnvironment()
}
