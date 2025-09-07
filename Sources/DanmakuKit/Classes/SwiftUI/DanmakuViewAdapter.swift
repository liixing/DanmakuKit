//
//  DanmakuViewAdapter.swift
//  DanmakuKit
//
//  Created by QiYiZhong on 2024/1/31.
//

#if canImport(SwiftUI)
import SwiftUI
#endif
#if os(macOS)
import Combine
import AppKit
#endif

//#if canImport(SwiftUI)
//// 平台适配：将 Representable 统一为 PlatformViewRepresentable
//#if canImport(UIKit)
//@available(iOS 13.0, tvOS 13.0, *)
//public typealias PlatformViewRepresentable = UIViewRepresentable
//#elseif os(macOS)
//@available(macOS 10.15, *)
//public typealias PlatformViewRepresentable = NSViewRepresentable
//#endif
//#endif

@available(iOS 14.0, tvOS 14.0, macOS 10.15, *)
public struct DanmakuViewAdapter: PlatformViewRepresentable {

    #if canImport(UIKit)
    public typealias UIViewType = DanmakuView
    #elseif os(macOS)
    public typealias NSViewType = DanmakuView
    #endif

    @ObservedObject var coordinator: Coordinator
    
    public init(coordinator: Coordinator) {
        self.coordinator = coordinator
    }
    
    #if canImport(UIKit)
    public func makeUIView(context: Context) -> UIViewType {
        return coordinator.makeView()
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {}
    #elseif os(macOS)
    public func makeNSView(context: Context) -> NSViewType {
        return coordinator.makeView()
    }
    
    public func updateNSView(_ nsView: NSViewType, context: Context) {}
    #endif

    public func makeCoordinator() -> Coordinator {
        return coordinator
    }
    
    public class Coordinator: ObservableObject {
        
        public init() {}
        
        public private(set) var danmakuView: DanmakuView?
        
        private var frameObserver: Any?
        
        public weak var danmakuViewDelegate: DanmakuViewDelegate? {
            willSet {
                danmakuView?.delegate = newValue
            }
        }

        public func play() { danmakuView?.play() }
        public func pause() { danmakuView?.pause() }
        public func stop() { danmakuView?.stop() }
        public func clean() { danmakuView?.clean() }
        public func shoot(danmaku: DanmakuCellModel) { danmakuView?.shoot(danmaku: danmaku) }

        public func canShoot(danmaku: DanmakuCellModel) -> Bool {
            guard let view = danmakuView else { return false }
            return view.canShoot(danmaku: danmaku)
        }

        public func recalculateTracks() { danmakuView?.recalculateTracks() }

        public func sync(danmaku: DanmakuCellModel, at progress: Float) {
            danmakuView?.sync(danmaku: danmaku, at: progress)
        }
        
        func makeView() -> DanmakuView {
            danmakuView = DanmakuView(frame: .zero)
            #if canImport(UIKit)
            frameObserver = danmakuView?.publisher(for: \.frame).sink { [weak self] _ in
                guard let self = self else { return }
                self.danmakuView?.recalculateTracks()
            }
            #elseif os(macOS)
            danmakuView?.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default
                .publisher(for: NSView.frameDidChangeNotification, object: danmakuView)
                .sink { [weak self] _ in
                    self?.danmakuView?.recalculateTracks()
                }
            #endif
            return danmakuView!
        }
        
    }
    
}
