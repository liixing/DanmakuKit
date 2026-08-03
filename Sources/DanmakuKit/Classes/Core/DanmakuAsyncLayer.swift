//
//  DanmakuAsyncLayer.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/16.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

class Sentinel {
    
    private var value: Int32 = 0
    
    public func getValue() -> Int32 {
        return value
    }
    
    public func increase() {
        #if os(macOS)
        _ = OSAtomicIncrement32(&value)
        #else
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        p.pointee = value
        OSAtomicIncrement32(p)
        p.deallocate()
        #endif
    }
    
}

public class DanmakuAsyncLayer: CALayer {
    
    /// When true, it is drawn asynchronously and is ture by default.
    public var displayAsync = true
    
    public var willDisplay: ((_ layer: DanmakuAsyncLayer) -> Void)?
    
    public var displaying: ((_ context: CGContext, _ size: CGSize, _ isCancelled:(() -> Bool)) -> Void)?
    
    public var didDisplay: ((_ layer: DanmakuAsyncLayer, _ finished: Bool) -> Void)?
    
    /// The number of queues to draw the danmaku.
    public static var drawDanmakuQueueCount = 16 {
        didSet {
            guard drawDanmakuQueueCount != oldValue else { return }
            pool = nil
            createPoolIfNeed()
        }
    }
    
    private let sentinel = Sentinel()
    
    private static var pool: DanmakuQueuePool?
    
    override init() {
        super.init()
        #if os(macOS)
        contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
        #else
        contentsScale = UIScreen.main.scale
        #endif
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        sentinel.increase()
    }
    
    public override func setNeedsDisplay() {
        //1. Cancel the last drawing
        sentinel.increase()
        //2. call super
        super.setNeedsDisplay()
    }
    
    public override func display() {
        display(isAsync: displayAsync)
    }
    
    private func display(isAsync: Bool) {
        guard displaying != nil, bounds.size.width > 0, bounds.size.height > 0 else {
            willDisplay?(self)
            contents = nil
            didDisplay?(self, true)
            return
        }
        
        if isAsync {
            willDisplay?(self)
            let value = sentinel.getValue()
            let isCancelled = {() -> Bool in
                return value != self.sentinel.getValue()
            }
            let size = bounds.size
            let scale = contentsScale
            let opaque = isOpaque
            let backgroundColor = (opaque && self.backgroundColor != nil) ? self.backgroundColor : nil
            queue.async {
                guard !isCancelled() else { return }
                #if os(macOS)
                guard let cgImage = Self.renderMacDanmakuImage(
                    size: size,
                    scale: scale,
                    opaque: opaque,
                    backgroundColor: backgroundColor,
                    isCancelled: isCancelled,
                    displaying: self.displaying
                ) else {
                    return
                }
                if isCancelled() {
                    DispatchQueue.main.async { self.didDisplay?(self, false) }
                    return
                }
                DispatchQueue.main.async {
                    if isCancelled() { self.didDisplay?(self, false) }
                    else { self.contents = cgImage; self.didDisplay?(self, true) }
                }
                #else
                UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
                guard let context = UIGraphicsGetCurrentContext() else {
                    UIGraphicsEndImageContext()
                    return
                }
                if opaque {
                    context.saveGState()
                    if backgroundColor == nil || (backgroundColor?.alpha ?? 0) < 1 {
                        context.setFillColor(UIColor.white.cgColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    if let backgroundColor = backgroundColor {
                        context.setFillColor(backgroundColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    context.restoreGState()
                }
                self.displaying?(context, size, isCancelled)
                if isCancelled() {
                    UIGraphicsEndImageContext()
                    DispatchQueue.main.async {
                        self.didDisplay?(self, false)
                    }
                    return
                }
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                if isCancelled() {
                    DispatchQueue.main.async {
                        self.didDisplay?(self, false)
                    }
                    return
                }
                DispatchQueue.main.async {
                    if isCancelled() {
                        self.didDisplay?(self, false)
                    } else {
                        self.contents = image?.cgImage
                        self.didDisplay?(self, true)
                    }
                }
                #endif
            }
            
        } else {
            sentinel.increase()
            willDisplay?(self)
            #if os(macOS)
            let size = bounds.size
            let scale = contentsScale
            let opaque = isOpaque
            if let image = Self.renderMacDanmakuImage(
                size: size,
                scale: scale,
                opaque: opaque,
                backgroundColor: (opaque && self.backgroundColor != nil) ? self.backgroundColor : nil,
                isCancelled: { false },
                displaying: displaying
            ) {
                contents = image
                didDisplay?(self, true)
            } else {
                contents = nil
                didDisplay?(self, false)
            }
            #else
            UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, contentsScale)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            displaying?(context, bounds.size, {() -> Bool in return false})
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            contents = image?.cgImage
            didDisplay?(self, true)
            #endif
        }
    }

    #if os(macOS)
    /// Single-pass CG bitmap for `CALayer.contents`.
    ///
    /// Uses **default CG coordinates** (origin bottom-left, y up) and expects
    /// the cell to draw with Core Text at a baseline `y` — no NSGraphicsContext
    /// flip stack (that was the inverted-glyph bug).
    private static func renderMacDanmakuImage(
        size: CGSize,
        scale: CGFloat,
        opaque: Bool,
        backgroundColor: CGColor?,
        isCancelled: () -> Bool,
        displaying: ((_ context: CGContext, _ size: CGSize, _ isCancelled: () -> Bool) -> Void)?
    ) -> CGImage? {
        let pixelW = max(1, Int(ceil(size.width * scale)))
        let pixelH = max(1, Int(ceil(size.height * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let context = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: alphaInfo.rawValue
        ) else {
            return nil
        }
        // Point space, origin bottom-left (standard CG / CALayer.contents).
        context.scaleBy(x: scale, y: scale)
        if opaque {
            context.saveGState()
            if backgroundColor == nil || (backgroundColor?.alpha ?? 0) < 1 {
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
            if let bg = backgroundColor {
                context.setFillColor(bg)
                context.fill(CGRect(origin: .zero, size: size))
            }
            context.restoreGState()
        }
        displaying?(context, size, isCancelled)
        guard !isCancelled() else { return nil }
        return context.makeImage()
    }
    #endif
    
    private static func createPoolIfNeed() {
        guard DanmakuAsyncLayer.pool == nil else { return }
        DanmakuAsyncLayer.pool = DanmakuQueuePool(name: "com.DanmakuKit.DanmakuAsynclayer", queueCount: DanmakuAsyncLayer.drawDanmakuQueueCount, qos: .userInteractive)
    }
    
    private lazy var queue: DispatchQueue = {
        return DanmakuAsyncLayer.pool?.queue ?? DispatchQueue(label: "com.DanmakuKit.DanmakuAsynclayer")
    }()
    
}
