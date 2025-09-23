//
//  FPSMonitor.swift
//  DanmuKitMacExample
//
//  Created by Augment Agent on 2025/8/24.
//

import Foundation
import AppKit

final class FPSMonitor: ObservableObject {
    @Published var fps: Double = 0

    private var displayLink: CVDisplayLink?
    private var lastTimestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var frameCount: Int = 0

    func start() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link

        let callback: CVDisplayLinkOutputCallback = { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let monitor = Unmanaged<FPSMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.tick()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    func stop() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
        fps = 0
        frameCount = 0
        lastTimestamp = CFAbsoluteTimeGetCurrent()
    }

    private func tick() {
        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let delta = now - lastTimestamp
        if delta >= 1.0 {
            let currentFPS = Double(frameCount) / delta
            frameCount = 0
            lastTimestamp = now
            DispatchQueue.main.async { [weak self] in
                self?.fps = currentFPS
            }
        }
    }
}

