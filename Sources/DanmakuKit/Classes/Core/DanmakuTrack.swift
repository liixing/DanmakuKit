//
//  DanmakuTrack.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/17.
//

// Use shared platform typealiases (PlatformView, etc.) from PlatformTypes.swift
#if os(macOS)
import AppKit
#else
import UIKit
#endif

//MARK: DanmakuTrack

protocol DanmakuTrack {
    
    var positionY: CGFloat { get set }
    
    var index: UInt { get set }
    
    var stopClosure: ((_ cell: DanmakuCell) -> Void)? { get set }
    
    var danmakuCount: Int { get }
    
    var isOverlap: Bool { get set }
    
    var playingSpeed: Float { get set }

    func updatePlayingSpeed(_ playingSpeed: Float, isPlaying: Bool)
    
    init(view: PlatformView)
    
    func shoot(danmaku: DanmakuCell)
    
    func canShoot(danmaku: DanmakuCellModel) -> Bool
    
    func play()
    
    func pause()
    
    func stop()
    
    func pause(_ danmaku: DanmakuCellModel) -> Bool
    
    func play(_ danmaku: DanmakuCellModel) -> Bool
    
    func sync(_ danmaku: DanmakuCell, at progress: Float)
    
    func syncAndPlay(_ danmaku: DanmakuCell, at progress: Float)
    
    func canSync(_ danmaku: DanmakuCellModel, at progress: Float) -> Bool
    
    func clean()
    
}

let FLOATING_ANIMATION_KEY = "FLOATING_ANIMATION_KEY"
let TOP_ANIMATION_KEY = "TOP_ANIMATION_KEY"
let DANMAKU_CELL_KEY = "DANMAKU_CELL_KEY"
let DANMAKU_ANIMATION_GENERATION_KEY = "DANMAKU_ANIMATION_GENERATION_KEY"
let DANMAKU_ANIMATION_STARTED_AT_KEY = "DANMAKU_ANIMATION_STARTED_AT_KEY"
let DANMAKU_ANIMATION_SPEED_KEY = "DANMAKU_ANIMATION_SPEED_KEY"

private func animation(for cell: DanmakuCell, key: String) -> CAAnimation? {
    #if os(macOS)
    return cell.layer?.animation(forKey: key)
    #else
    return cell.layer.animation(forKey: key)
    #endif
}

private func removeAnimation(from cell: DanmakuCell, key: String) {
    #if os(macOS)
    cell.layer?.removeAnimation(forKey: key)
    #else
    cell.layer.removeAnimation(forKey: key)
    #endif
}

@discardableResult
private func configureAnimation(
    _ animation: CAAnimation,
    for cell: DanmakuCell,
    playingSpeed: Float
) -> CFTimeInterval {
    cell.animationGeneration &+= 1
    let startedAt = CACurrentMediaTime()
    animation.setValue(cell, forKey: DANMAKU_CELL_KEY)
    animation.setValue(NSNumber(value: cell.animationGeneration), forKey: DANMAKU_ANIMATION_GENERATION_KEY)
    animation.setValue(NSNumber(value: startedAt), forKey: DANMAKU_ANIMATION_STARTED_AT_KEY)
    animation.setValue(NSNumber(value: playingSpeed), forKey: DANMAKU_ANIMATION_SPEED_KEY)
    return startedAt
}

private func generation(of animation: CAAnimation) -> UInt64? {
    return (animation.value(forKey: DANMAKU_ANIMATION_GENERATION_KEY) as? NSNumber)?.uint64Value
}

private func recordElapsedTime(of animation: CAAnimation, for cell: DanmakuCell) {
    guard generation(of: animation) == cell.animationGeneration,
          let startedAt = animation.value(forKey: DANMAKU_ANIMATION_STARTED_AT_KEY) as? NSNumber,
          let speed = animation.value(forKey: DANMAKU_ANIMATION_SPEED_KEY) as? NSNumber else {
        return
    }
    let elapsed = max(0, CACurrentMediaTime() - startedAt.doubleValue) * speed.doubleValue
    let newAnimationTime = cell.animationTime + elapsed
    if let displayTime = cell.model?.displayTime {
        cell.animationTime = min(displayTime, newAnimationTime)
    } else {
        cell.animationTime = newAnimationTime
    }
}

private func invalidateAnimation(for cell: DanmakuCell, key: String) {
    if let currentAnimation = animation(for: cell, key: key) {
        recordElapsedTime(of: currentAnimation, for: cell)
    }
    cell.animationGeneration &+= 1
    removeAnimation(from: cell, key: key)
}

//MARK: DanmakuFloatingTrack

class DanmakuFloatingTrack: NSObject, DanmakuTrack, CAAnimationDelegate {
    
    var positionY: CGFloat = 0 {
        didSet {
            // Match DanmuKitMac behavior: do not mutate CALayer position on macOS while animating.
            // iOS can adjust layer.position.y to keep centered vertically on layout changes.
            #if !os(macOS)
            cells.forEach {
                $0.layer.position.y = positionY
            }
            #endif
        }
    }
    
    var index: UInt = 0
    
    var stopClosure: ((_ cell: DanmakuCell) -> Void)?
    
    var isOverlap: Bool = false
    
    var danmakuCount: Int {
        return cells.count
    }
    
    var playingSpeed: Float = 1.0
    
    private var cells: [DanmakuCell] = []
    
    private weak var view: PlatformView?
    
    required init(view: PlatformView) {
        self.view = view
    }

    func updatePlayingSpeed(_ playingSpeed: Float, isPlaying: Bool) {
        guard self.playingSpeed != playingSpeed else { return }
        if isPlaying {
            cells.forEach {
                freezeAnimation(on: $0)
            }
        }
        self.playingSpeed = playingSpeed
        if isPlaying {
            cells.forEach {
                addAnimation(to: $0)
            }
        }
    }
    
    func shoot(danmaku: DanmakuCell) {
        cells.append(danmaku)
        #if os(macOS)
        danmaku.frame = CGRect(x: view!.bounds.width, y: positionY - danmaku.bounds.height / 2.0, width: danmaku.bounds.width, height: danmaku.bounds.height)
        #else
        danmaku.layer.position = CGPoint(x: view!.bounds.width + danmaku.bounds.width / 2.0, y: positionY)
        #endif
        danmaku.model?.track = index
        prepare(danmaku: danmaku)
        addAnimation(to: danmaku)
        danmaku.enterTrack()
    }
    
    func canShoot(danmaku: DanmakuCellModel) -> Bool {
        guard !isOverlap else { return true }
        //初中数学的追击问题
        evictStaleCells()
        // The newest cell is the most likely to reject a launch immediately.
        // Checking backwards keeps the common occupied-track path effectively O(1).
        for cell in cells.reversed() {
            guard canShoot(danmaku, withoutCollidingWith: cell) else {
                return false
            }
        }
        return true
    }

    private func canShoot(
        _ danmaku: DanmakuCellModel,
        withoutCollidingWith cell: DanmakuCell
    ) -> Bool {
        guard let cellModel = cell.model else { return true }

        let preWidth = view!.bounds.width + cell.frame.width
        let nextWidth = view!.bounds.width + danmaku.size.width
        let preRight = currentFrameMaxX(of: cell)
        let preCellTime = (preRight / preWidth) * CGFloat(cellModel.displayTime)
        let distance = view!.bounds.width - preRight - 10
        guard distance >= 0 else { return false }

        let preV = preWidth / CGFloat(cellModel.displayTime)
        let nextV = nextWidth / CGFloat(danmaku.displayTime)
        guard nextV > preV else { return true }

        let catchUpTime = distance / (nextV - preV)
        return catchUpTime >= preCellTime
    }

    private func currentFrameMaxX(of cell: DanmakuCell) -> CGFloat {
        if let positionX = currentAnimatedPositionX(of: cell) {
            return max(positionX + cell.bounds.width / 2.0, 0)
        }
        let presentedMaxX = cell.realFrame.maxX
        return presentedMaxX.isFinite ? max(presentedMaxX, 0) : 0
    }

    /// A reused layer can briefly expose the previous animation's presentation
    /// position. Derive the current generation's position from its animation.
    private func currentAnimatedPositionX(of cell: DanmakuCell) -> CGFloat? {
        guard let animation = animation(for: cell, key: FLOATING_ANIMATION_KEY) as? CABasicAnimation,
              let fromX = (animation.fromValue as? NSNumber)?.doubleValue,
              let toX = (animation.toValue as? NSNumber)?.doubleValue,
              fromX.isFinite,
              toX.isFinite else {
            return nil
        }

        #if os(macOS)
        let currentTime = cell.layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
        #else
        let currentTime = cell.layer.convertTime(CACurrentMediaTime(), from: nil)
        #endif
        let progress: Double
        if animation.duration > 0, animation.duration.isFinite {
            progress = min(max((currentTime - animation.beginTime) / animation.duration, 0), 1)
        } else {
            progress = 1
        }
        let positionX = fromX + (toX - fromX) * progress
        return positionX.isFinite ? CGFloat(positionX) : nil
    }
    
    func play() {
        cells.forEach {
            addAnimation(to: $0)
        }
    }
    
    func play(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        if let layer = findCell.layer {
            layer.speed = 1.0
            layer.timeOffset = 0
        }
        #else
        addAnimation(to: findCell)
        #endif
        return true
    }
    
    func pause() {
        cells.forEach {
            freezeAnimation(on: $0)
        }
    }
    
    func pause(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        let realFrame = findCell.realFrame
        findCell.frame.origin = CGPoint(
            x: realFrame.midX - findCell.bounds.width / 2.0,
            y: realFrame.midY - findCell.bounds.height / 2.0
        )
        if let layer = findCell.layer {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0.0
            layer.timeOffset = pausedTime
        }
        #else
        freezeAnimation(on: findCell)
        #endif
        return true
    }
    
    func stop() {
        cells.forEach {
            invalidateAnimation(for: $0, key: FLOATING_ANIMATION_KEY)
            $0.removeFromSuperview()
            #if os(macOS)
            $0.layer?.removeAllAnimations()
            #else
            $0.layer.removeAllAnimations()
            #endif
        }
        cells.removeAll()
    }
    
    func sync(_ danmaku: DanmakuCell, at progress: Float) {
        guard let model = danmaku.model else { return }
        let totalWidth = view!.frame.width + danmaku.bounds.width
        let syncFrame = CGRect(x: view!.frame.width - totalWidth * CGFloat(progress), y: positionY - danmaku.bounds.height / 2.0, width: danmaku.bounds.width, height: danmaku.bounds.height)
        cells.append(danmaku)
        #if os(macOS)
        danmaku.layer?.opacity = 1
        #else
        danmaku.layer.opacity = 1
        #endif
        danmaku.frame = syncFrame
        danmaku.model?.track = index
        danmaku.animationTime = model.displayTime * Double(progress)
    }
    
    func syncAndPlay(_ danmaku: DanmakuCell, at progress: Float) {
        sync(danmaku, at: progress)
        addAnimation(to: danmaku)
    }
    
    func canSync(_ danmaku: DanmakuCellModel, at progress: Float) -> Bool {
        let totalWidth = view!.frame.width + danmaku.size.width
        let syncFrame = CGRect(x: view!.frame.width - totalWidth * CGFloat(progress), y: positionY - danmaku.size.height / 2.0, width: danmaku.size.width, height: danmaku.size.height)
        return cells.first(where: { (cell) -> Bool in
            // realFrame是presentationLayer的frame，只有坐标是可靠的，size并不可靠，因此这里要使用cell设置size
            let cellRealyFrame = CGRect(x: cell.realFrame.midX - cell.bounds.width / 2.0, y: cell.realFrame.midY - cell.bounds.height / 2.0, width: cell.bounds.width, height: cell.bounds.height)
            return cellRealyFrame.intersects(syncFrame)
        }) == nil
    }
    
    func clean() {
        stop()
    }

    /// Remove cells whose floating animation was stripped externally
    /// (e.g. app backgrounded, system memory pressure) so they don't
    /// permanently block the track.
    private func evictStaleCells() {
        #if os(macOS)
        let hasAnim: (DanmakuCell) -> Bool = { $0.layer?.animation(forKey: FLOATING_ANIMATION_KEY) != nil }
        #else
        let hasAnim: (DanmakuCell) -> Bool = { $0.layer.animation(forKey: FLOATING_ANIMATION_KEY) != nil }
        #endif
        cells.removeAll { cell in
            guard !hasAnim(cell) else { return false }
            #if os(macOS)
            cell.layer?.removeAllAnimations()
            cell.layer?.opacity = 0
            #else
            cell.layer.removeAllAnimations()
            cell.layer.position.x = -cell.bounds.width / 2.0
            #endif
            cell.leaveTrack()
            stopClosure?(cell)
            return true
        }
    }
    
    func animationDidStop(_ anim: CAAnimation, finished _: Bool) {
        guard let danmaku = anim.value(forKey: DANMAKU_CELL_KEY) as? DanmakuCell,
              generation(of: anim) == danmaku.animationGeneration else {
            return
        }
        recordElapsedTime(of: anim, for: danmaku)
        danmaku.animationGeneration &+= 1

        var findCell: DanmakuCell?
        cells.removeAll { (cell) -> Bool in
            let isTargetCell = cell == danmaku
            if isTargetCell {
                findCell = cell
            }
            return isTargetCell
        }
        if let cell = findCell {
            #if os(macOS)
            cell.layer?.removeAllAnimations()
            cell.layer?.opacity = 0
            // Avoid invalid geometry warnings on AppKit; do not push to infinity.
            cell.leaveTrack()
            stopClosure?(cell)
            #else
            cell.layer.removeAllAnimations()
            cell.layer.position.x = -cell.bounds.width / 2.0
            cell.leaveTrack()
            stopClosure?(cell)
            #endif
        }
    }
    
    private func addAnimation(to danmaku: DanmakuCell) {
        guard let cellModel = danmaku.model else { return }
        let rate = max(danmaku.frame.maxX / (view!.bounds.width + danmaku.frame.width), 0)
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.beginTime = configureAnimation(animation, for: danmaku, playingSpeed: playingSpeed)
        animation.duration = (cellModel.displayTime * Double(rate)) / Double(playingSpeed)
        // Collision prediction and retiming both assume constant velocity.
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.delegate = self
        #if os(macOS)
        animation.fromValue = NSNumber(value: Float(danmaku.layer?.position.x ?? danmaku.frame.midX))
        animation.toValue = NSNumber(value: Float(-danmaku.bounds.width))
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        danmaku.layer?.add(animation, forKey: FLOATING_ANIMATION_KEY)
        #else
        animation.fromValue = NSNumber(value: Float(danmaku.layer.position.x))
        animation.toValue = NSNumber(value: Float(-danmaku.bounds.width / 2.0))
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        danmaku.layer.add(animation, forKey: FLOATING_ANIMATION_KEY)
        #endif
    }

    private func freezeAnimation(on danmaku: DanmakuCell) {
        let animatedPositionX = currentAnimatedPositionX(of: danmaku)
        let realFrame = danmaku.realFrame
        #if os(macOS)
        let modelMidX = danmaku.frame.midX
        let fallbackMidX = (view?.bounds.width ?? 0) + danmaku.bounds.width / 2.0
        let midX = animatedPositionX
            ?? (realFrame.midX.isFinite
                ? realFrame.midX
                : (modelMidX.isFinite ? modelMidX : fallbackMidX))
        danmaku.frame.origin = CGPoint(
            x: midX - danmaku.bounds.width / 2.0,
            y: positionY - danmaku.bounds.height / 2.0
        )
        #else
        let modelX = danmaku.layer.position.x
        let fallbackX = (view?.bounds.width ?? 0) + danmaku.bounds.width / 2.0
        let positionX = animatedPositionX
            ?? (realFrame.midX.isFinite
                ? realFrame.midX
                : (modelX.isFinite ? modelX : fallbackX))
        danmaku.layer.position = CGPoint(x: positionX, y: positionY)
        #endif
        invalidateAnimation(for: danmaku, key: FLOATING_ANIMATION_KEY)
    }
    
}

//MARK: DanmakuVerticalTrack

class DanmakuVerticalTrack: NSObject, DanmakuTrack, CAAnimationDelegate {
    
    var positionY: CGFloat = 0 {
        didSet {
            cells.forEach {
                #if os(macOS)
                let originX = (view!.bounds.width - $0.bounds.width) / 2.0
                let originY = positionY - $0.bounds.height / 2.0
                $0.frame.origin = CGPoint(x: originX, y: originY)
                #else
                $0.layer.position = CGPoint(x: view!.bounds.width / 2.0, y: positionY)
                #endif
            }
        }
    }
    
    var index: UInt = 0
    
    var stopClosure: ((_ cell: DanmakuCell) -> Void)?
    
    var isOverlap: Bool = false
    
    var danmakuCount: Int {
        return cells.count
    }
    
    var cells: [DanmakuCell] = []
    
    var playingSpeed: Float = 1.0
    
    private weak var view: PlatformView?
    
    required init(view: PlatformView) {
        self.view = view
    }

    func updatePlayingSpeed(_ playingSpeed: Float, isPlaying: Bool) {
        guard self.playingSpeed != playingSpeed else { return }
        if isPlaying {
            cells.forEach {
                invalidateAnimation(for: $0, key: TOP_ANIMATION_KEY)
            }
        }
        self.playingSpeed = playingSpeed
        if isPlaying {
            cells.forEach {
                addAnimation(to: $0)
            }
        }
    }
    
    func shoot(danmaku: DanmakuCell) {
        cells.append(danmaku)
        #if os(macOS)
        let originX = (view!.bounds.width - danmaku.bounds.width) / 2.0
        let originY = positionY - danmaku.bounds.height / 2.0
        danmaku.frame = CGRect(x: originX, y: originY, width: danmaku.bounds.width, height: danmaku.bounds.height)
        #else
        danmaku.layer.position = CGPoint(x: view!.bounds.width / 2.0, y: positionY)
        #endif
        danmaku.model?.track = index
        prepare(danmaku: danmaku)
        // Hide until async rendering completes to prevent flash on appear
        #if os(macOS)
        danmaku.layer?.opacity = 0
        #else
        danmaku.layer.opacity = 0
        #endif
        addAnimation(to: danmaku)
    }
    
    func canShoot(danmaku: DanmakuCellModel) -> Bool {
        return isOverlap ? true : cells.count == 0
    }
    
    func play() {
        cells.forEach {
            addAnimation(to: $0)
        }
    }
    
    func play(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        if let layer = findCell.layer {
            layer.speed = 1.0
            layer.timeOffset = 0
        }
        #else
        addAnimation(to: findCell)
        #endif
        return true
    }
    
    func pause() {
        cells.forEach {
            invalidateAnimation(for: $0, key: TOP_ANIMATION_KEY)
        }
    }
    
    func pause(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        if let layer = findCell.layer {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0.0
            layer.timeOffset = pausedTime
        }
        #else
        invalidateAnimation(for: findCell, key: TOP_ANIMATION_KEY)
        #endif
        return true
    }
    
    func stop() {
        cells.forEach {
            invalidateAnimation(for: $0, key: TOP_ANIMATION_KEY)
            $0.removeFromSuperview()
            #if os(macOS)
            $0.layer?.removeAllAnimations()
            #else
            $0.layer.removeAllAnimations()
            #endif
        }
        cells.removeAll()
    }
    
    func sync(_ danmaku: DanmakuCell, at progress: Float) {
        guard let model = danmaku.model else { return }
        cells.append(danmaku)
        danmaku.animationTime = model.displayTime * Double(progress)
        danmaku.model?.track = index
        #if os(macOS)
        let originX = (view!.bounds.width - danmaku.bounds.width) / 2.0
        let originY = positionY - danmaku.bounds.height / 2.0
        danmaku.frame = CGRect(x: originX, y: originY, width: danmaku.bounds.width, height: danmaku.bounds.height)
        danmaku.layer?.opacity = 0
        #else
        danmaku.layer.position = CGPoint(x: view!.bounds.width / 2.0, y: positionY)
        danmaku.layer.opacity = 0
        #endif
    }
    
    func syncAndPlay(_ danmaku: DanmakuCell, at progress: Float) {
        sync(danmaku, at: progress)
        addAnimation(to: danmaku)
    }
    
    func canSync(_ danmaku: DanmakuCellModel, at progress: Float) -> Bool {
        return cells.isEmpty
    }
    
    func clean() {
        stop()
    }
    
    func animationDidStop(_ anim: CAAnimation, finished _: Bool) {
        guard let danmaku = anim.value(forKey: DANMAKU_CELL_KEY) as? DanmakuCell,
              generation(of: anim) == danmaku.animationGeneration else {
            return
        }
        recordElapsedTime(of: anim, for: danmaku)
        danmaku.animationGeneration &+= 1

        var findCell: DanmakuCell?
        cells.removeAll { (cell) -> Bool in
            let isTargetCell = cell == danmaku
            if isTargetCell {
                findCell = cell
            }
            return isTargetCell
        }
        if let cell = findCell {
            #if os(macOS)
            danmaku.layer?.removeAllAnimations()
            cell.layer?.opacity = 0
            danmaku.leaveTrack()
            stopClosure?(cell)
            #else
            danmaku.layer.removeAllAnimations()
            danmaku.layer.opacity = 0
            stopClosure?(cell)
            #endif
        }
    }
    
    private func addAnimation(to danmaku: DanmakuCell) {
        guard let cellModel = danmaku.model else { return }
        let rate = cellModel.displayTime == 0 ? 0 : max(0, 1 - danmaku.animationTime / cellModel.displayTime)
        #if os(macOS)
        // Ensure horizontally centered before scheduling fade-out, matching DanmuKitMac
        if let vw = view {
            let originX = (vw.bounds.width - danmaku.bounds.width) / 2.0
            let originY = positionY - danmaku.bounds.height / 2.0
            danmaku.frame.origin = CGPoint(x: originX, y: originY)
        }
        #endif
        let animation = CABasicAnimation(keyPath: "opacity")
        let startedAt = configureAnimation(animation, for: danmaku, playingSpeed: playingSpeed)
        animation.beginTime = startedAt + cellModel.displayTime * rate / Double(playingSpeed)
        animation.duration = 0
        animation.delegate = self
        // Omit fromValue so fade-out starts from the cell's current opacity
        // (e.g. user-adjusted alpha). Hardcoding 1 flashes full opacity first.
        animation.toValue = 0
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        #if os(macOS)
        danmaku.layer?.add(animation, forKey: TOP_ANIMATION_KEY)
        #else
        danmaku.layer.add(animation, forKey: TOP_ANIMATION_KEY)
        #endif
    }
    
}

func prepare(danmaku: DanmakuCell) {
    danmaku.animationGeneration &+= 1
    danmaku.animationTime = 0
    #if os(macOS)
    danmaku.layer?.opacity = 1
    #else
    danmaku.layer.opacity = 1
    #endif
}
