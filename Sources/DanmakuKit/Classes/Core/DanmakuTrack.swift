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
/// Absolute center-X path stored on the floating animation (independent of keyPath).
let DANMAKU_FROM_CENTER_X_KEY = "DANMAKU_FROM_CENTER_X_KEY"
let DANMAKU_TO_CENTER_X_KEY = "DANMAKU_TO_CENTER_X_KEY"

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
            guard oldValue != positionY else { return }
            cells.forEach { cell in
                #if os(macOS)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                var frame = cell.frame
                frame.origin.y = positionY - frame.height / 2.0
                cell.frame = frame
                CATransaction.commit()
                #else
                cell.layer.position.y = positionY
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
    
    var playingSpeed: Float = 1.0
    
    private var cells: [DanmakuCell] = []
    
    private weak var view: PlatformView?
    
    required init(view: PlatformView) {
        self.view = view
    }

    func updatePlayingSpeed(_ playingSpeed: Float, isPlaying: Bool) {
        guard self.playingSpeed != playingSpeed else { return }
        self.playingSpeed = playingSpeed
        #if os(macOS)
        if isPlaying {
            cells.forEach {
                pauseLayerClock(of: $0)
                resumeLayerClock(of: $0, speed: playingSpeed)
            }
        }
        #else
        guard isPlaying else { return }
        cells.forEach {
            freezeAnimation(on: $0)
        }
        cells.forEach {
            addAnimation(to: $0)
        }
        #endif
    }
    
    func shoot(danmaku: DanmakuCell) {
        cells.append(danmaku)
        #if os(macOS)
        // Rest geometry stays fixed for the whole flight; scroll is
        // transform.translation.x (AppKit must not reconcile frame vs position).
        let w = max(danmaku.bounds.width, 1)
        let h = max(danmaku.bounds.height, 1)
        let viewW = view!.bounds.width
        let originX = viewW
        let originY = positionY - h / 2.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        danmaku.frame = CGRect(x: originX, y: originY, width: w, height: h)
        if let layer = danmaku.layer {
            layer.transform = CATransform3DIdentity
            resetLayerClock(layer)
        }
        CATransaction.commit()
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
        // Only the previous (newest) cell matters: floating cells enter from the
        // right, so older cells are further left. Checking every cell over-blocks
        // and leaves unnaturally large gaps.
        guard let cell = cells.last else { return true }
        return canShoot(danmaku, withoutCollidingWith: cell)
    }

    private func canShoot(
        _ danmaku: DanmakuCellModel,
        withoutCollidingWith cell: DanmakuCell
    ) -> Bool {
        guard let cellModel = cell.model else { return true }

        // Prefer bounds.width: frame.origin can be stale under CA while size is stable.
        let viewWidth = view!.bounds.width
        let preCellWidth = max(cell.bounds.width, 1)
        let nextCellWidth = max(danmaku.size.width, 1)
        let preWidth = viewWidth + preCellWidth
        let nextWidth = viewWidth + nextCellWidth
        let preRight = currentFrameMaxX(of: cell)
        guard preWidth > 0, cellModel.displayTime > 0, danmaku.displayTime > 0 else { return true }

        // Entrance gate: previous right edge must leave a small gap past the right
        // border so the next cell can spawn off-screen without overlap.
        // 4pt is enough for anti-kiss; 10pt was visually sparse under high volume.
        let entranceGap: CGFloat = 4
        let distance = viewWidth - preRight - entranceGap
        guard distance >= 0 else { return false }

        // Same or lower speed (usually same displayTime + shorter/equal width):
        // never catches up → allow as soon as entrance gap is free.
        let preV = preWidth / CGFloat(cellModel.displayTime)
        let nextV = nextWidth / CGFloat(danmaku.displayTime)
        guard nextV > preV else { return true }

        // Faster follower (typically wider text): classical pursuit.
        // Remaining time of leader ≈ fraction of full path still ahead of its right edge.
        let preCellTime = (preRight / preWidth) * CGFloat(cellModel.displayTime)
        let catchUpTime = distance / (nextV - preV)
        return catchUpTime >= preCellTime
    }

    private func currentFrameMaxX(of cell: DanmakuCell) -> CGFloat {
        // Prefer on-screen pixels (presentation), then animation metadata.
        // Time-based math alone drifts from CA and causes gap/overlap after timing changes.
        if let centerX = presentationCenterX(of: cell) {
            return max(centerX + cell.bounds.width / 2.0, 0)
        }
        if let positionX = currentAnimatedPositionX(of: cell) {
            return max(positionX + cell.bounds.width / 2.0, 0)
        }
        let presentedMaxX = cell.realFrame.maxX
        if presentedMaxX.isFinite {
            return max(presentedMaxX, 0)
        }
        // Still animating but geometry unreadable: block this track once (safe).
        if animation(for: cell, key: FLOATING_ANIMATION_KEY) != nil {
            let viewW = view?.bounds.width ?? 0
            return viewW + max(cell.bounds.width, 1)
        }
        return 0
    }

    /// Live center X from the presentation layer (what the user actually sees).
    private func presentationCenterX(of cell: DanmakuCell) -> CGFloat? {
        #if os(macOS)
        guard let presentation = cell.layer?.presentation() else { return nil }
        let x = presentation.frame.midX
        #else
        guard let presentation = cell.layer.presentation() else { return nil }
        let x = presentation.position.x
        #endif
        return x.isFinite ? x : nil
    }

    /// On-screen center X when baking a freeze.
    /// **Presentation first** — wall-clock progress often disagrees with pixels and
    /// was the main cause of left/right jumps on pause and speed change.
    private func freezeSampleCenterX(of cell: DanmakuCell) -> CGFloat {
        if let presented = presentationCenterX(of: cell) {
            return presented
        }
        if let animated = currentAnimatedPositionX(of: cell) {
            return animated
        }
        #if os(macOS)
        if let layer = cell.layer {
            let modelX = cell.frame.midX + layer.transform.m41
            if modelX.isFinite { return modelX }
        }
        let mid = cell.frame.midX
        if mid.isFinite { return mid }
        #else
        let modelX = cell.layer.position.x
        if modelX.isFinite { return modelX }
        #endif
        return (view?.bounds.width ?? 0) + max(cell.bounds.width, 1) / 2.0
    }

    /// Derive center X from the running animation's from/to + progress.
    /// Used when presentation is unavailable (e.g. just after remove).
    private func currentAnimatedPositionX(of cell: DanmakuCell) -> CGFloat? {
        guard let animation = animation(for: cell, key: FLOATING_ANIMATION_KEY) as? CABasicAnimation else {
            return nil
        }

        let progress = floatingAnimationProgress(animation, on: cell)

        if let fromAbs = (animation.value(forKey: DANMAKU_FROM_CENTER_X_KEY) as? NSNumber)?.doubleValue,
           let toAbs = (animation.value(forKey: DANMAKU_TO_CENTER_X_KEY) as? NSNumber)?.doubleValue,
           fromAbs.isFinite,
           toAbs.isFinite {
            let positionX = fromAbs + (toAbs - fromAbs) * progress
            return positionX.isFinite ? CGFloat(positionX) : nil
        }

        guard let fromX = numberValue(animation.fromValue),
              let toX = numberValue(animation.toValue),
              fromX.isFinite,
              toX.isFinite else {
            return nil
        }

        let positionX = fromX + (toX - fromX) * progress
        return positionX.isFinite ? CGFloat(positionX) : nil
    }

    /// Progress in [0, 1]. Prefer geometry from presentation (matches pixels),
    /// then layer timebase, then wall-clock stamp.
    private func floatingAnimationProgress(_ animation: CAAnimation, on cell: DanmakuCell) -> Double {
        let duration = animation.duration
        guard duration > 0, duration.isFinite else { return 1 }

        // Geometric progress from live pixels — immune to beginTime/clock skew.
        if let fromAbs = (animation.value(forKey: DANMAKU_FROM_CENTER_X_KEY) as? NSNumber)?.doubleValue,
           let toAbs = (animation.value(forKey: DANMAKU_TO_CENTER_X_KEY) as? NSNumber)?.doubleValue,
           fromAbs.isFinite,
           toAbs.isFinite {
            let span = toAbs - fromAbs
            if abs(span) > 0.5, let x = presentationCenterX(of: cell).map(Double.init) {
                return min(max((x - fromAbs) / span, 0), 1)
            }
        }

        #if os(macOS)
        let layerTime = cell.layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
        #else
        let layerTime = cell.layer.convertTime(CACurrentMediaTime(), from: nil)
        #endif
        if animation.beginTime > 0 {
            return min(max((layerTime - animation.beginTime) / duration, 0), 1)
        }
        if let startedAt = (animation.value(forKey: DANMAKU_ANIMATION_STARTED_AT_KEY) as? NSNumber)?.doubleValue {
            return min(max((CACurrentMediaTime() - startedAt) / duration, 0), 1)
        }
        return min(max((layerTime - animation.beginTime) / duration, 0), 1)
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let d = value as? Double { return d }
        if let f = value as? CGFloat { return Double(f) }
        if let f = value as? Float { return Double(f) }
        if let i = value as? Int { return Double(i) }
        return nil
    }
    
    func play() {
        #if os(macOS)
        // Resume CA timebase only — never reinstall / never touch frame (prevents track hop).
        cells.forEach { resumeLayerClock(of: $0, speed: playingSpeed) }
        #else
        // iOS: re-install remaining path from baked center after freeze.
        cells.forEach {
            addAnimation(to: $0)
        }
        #endif
    }
    
    func play(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        resumeLayerClock(of: findCell, speed: playingSpeed)
        #else
        addAnimation(to: findCell)
        #endif
        return true
    }
    
    func pause() {
        #if os(macOS)
        // Freeze presentation in place via layer clock. Do NOT bake frame/position —
        // that was rewriting Y and jumping cells to lower tracks on AppKit.
        cells.forEach { pauseLayerClock(of: $0) }
        #else
        cells.forEach {
            freezeAnimation(on: $0)
        }
        #endif
    }
    
    func pause(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        pauseLayerClock(of: findCell)
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
        let cellW = max(danmaku.bounds.width, 1)
        let cellH = max(danmaku.bounds.height, 1)
        let totalWidth = view!.frame.width + cellW
        let originX = view!.frame.width - totalWidth * CGFloat(progress)
        let syncFrame = CGRect(
            x: originX,
            y: positionY - cellH / 2.0,
            width: cellW,
            height: cellH
        )
        cells.append(danmaku)
        #if os(macOS)
        danmaku.layer?.opacity = 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        danmaku.frame = syncFrame
        danmaku.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
        #else
        danmaku.layer.opacity = 1
        danmaku.frame = syncFrame
        danmaku.layer.position = CGPoint(x: syncFrame.midX, y: positionY)
        #endif
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

        let viewW = view!.bounds.width
        let cellW = max(danmaku.bounds.width, 1)
        // Full right→left center travel: (viewW + cellW/2) → (-cellW/2).
        let fullTravel = viewW + cellW
        let endCenterX = -cellW / 2.0
        let speed = max(playingSpeed, 0.01)

        #if os(macOS)
        // AppKit owns the view-backed layer's frame; animation only translates X.
        // Pause and playback rate use the layer clock, so geometry never gets baked.
        guard let layer = danmaku.layer else { return }

        let fromCenterX = danmaku.frame.midX
        let remainingTravel = max(fromCenterX - endCenterX, 0)
        let rate = fullTravel > 0 ? min(remainingTravel / fullTravel, 1) : 0
        let toCenterX = endCenterX

        let duration = floatingAnimationDuration(
            displayTime: cellModel.displayTime,
            rate: rate,
            speed: 1
        )

        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        _ = configureAnimation(animation, for: danmaku, playingSpeed: speed)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.delegate = self
        animation.fromValue = NSNumber(value: 0.0)
        animation.toValue = NSNumber(value: Double(-remainingTravel))
        animation.setValue(NSNumber(value: Double(fromCenterX)), forKey: DANMAKU_FROM_CENTER_X_KEY)
        animation.setValue(NSNumber(value: Double(toCenterX)), forKey: DANMAKU_TO_CENTER_X_KEY)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards

        resetLayerClock(layer)
        layer.speed = speed
        let layerNow = layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.beginTime = layerNow
        animation.setValue(NSNumber(value: CACurrentMediaTime()), forKey: DANMAKU_ANIMATION_STARTED_AT_KEY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
        layer.add(animation, forKey: FLOATING_ANIMATION_KEY)
        #else
        let fromCenterX = danmaku.layer.position.x
        let remainingTravel = max(fromCenterX - endCenterX, 0)
        let rate = fullTravel > 0 ? min(remainingTravel / fullTravel, 1) : 0
        let toCenterX = endCenterX

        let animation = CABasicAnimation(keyPath: "position.x")
        _ = configureAnimation(animation, for: danmaku, playingSpeed: speed)
        animation.duration = floatingAnimationDuration(
            displayTime: cellModel.displayTime,
            rate: rate,
            speed: speed
        )
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.delegate = self
        animation.fromValue = NSNumber(value: Double(fromCenterX))
        animation.toValue = NSNumber(value: Double(toCenterX))
        animation.setValue(NSNumber(value: Double(fromCenterX)), forKey: DANMAKU_FROM_CENTER_X_KEY)
        animation.setValue(NSNumber(value: Double(toCenterX)), forKey: DANMAKU_TO_CENTER_X_KEY)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.beginTime = CACurrentMediaTime()
        animation.setValue(NSNumber(value: animation.beginTime), forKey: DANMAKU_ANIMATION_STARTED_AT_KEY)
        danmaku.layer.add(animation, forKey: FLOATING_ANIMATION_KEY)
        #endif
    }

    // MARK: macOS layer clock

    #if os(macOS)
    /// Reset media timing so a new animation is not stuck paused or time-shifted.
    private func resetLayerClock(_ layer: CALayer) {
        layer.speed = 1.0
        layer.timeOffset = 0
        layer.beginTime = 0
    }

    /// Freeze presentation exactly where it is (Apple CA pause recipe).
    private func pauseLayerClock(of cell: DanmakuCell) {
        guard let layer = cell.layer else { return }
        if layer.speed == 0 { return }
        let t = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = t
    }

    /// Resume after `pauseLayerClock` at the requested playback rate.
    private func resumeLayerClock(of cell: DanmakuCell, speed: Float) {
        guard let layer = cell.layer else { return }
        let rate = max(speed, 0.01)
        if layer.speed == 0 {
            let pausedTime = layer.timeOffset
            let parentTime = layer.superlayer?.convertTime(CACurrentMediaTime(), from: nil)
                ?? CACurrentMediaTime()
            layer.speed = rate
            layer.timeOffset = 0
            layer.beginTime = parentTime - pausedTime / Double(rate)
        } else {
            layer.speed = rate
        }
    }

    #endif

    /// Duration for the remaining fraction of a floating path.
    /// A zero raw duration (already off-screen) still gets one frame so
    /// `animationDidStop` runs and the track is released — never leave a stuck cell.
    private func floatingAnimationDuration(displayTime: Double, rate: CGFloat, speed: Float) -> CFTimeInterval {
        let raw = (displayTime * Double(rate)) / Double(speed)
        if raw > 0, raw.isFinite {
            return raw
        }
        return 1.0 / 120.0
    }

    /// iOS: bake on-screen center into model and remove animation.
    /// macOS pause/speed no longer call this (layer clock instead). Kept for any
    /// shared callers and for the iOS speed-change path.
    private func freezeAnimation(on danmaku: DanmakuCell) {
        let midX = freezeSampleCenterX(of: danmaku)
        guard midX.isFinite else {
            invalidateAnimation(for: danmaku, key: FLOATING_ANIMATION_KEY)
            return
        }
        #if os(macOS)
        // Should not be on the pause path; if invoked, only freeze the clock.
        pauseLayerClock(of: danmaku)
        #else
        danmaku.layer.position = CGPoint(x: midX, y: positionY)
        invalidateAnimation(for: danmaku, key: FLOATING_ANIMATION_KEY)
        #endif
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
        self.playingSpeed = playingSpeed
        #if os(macOS)
        // Opacity timer is authored at 1×; live rate = layer.speed.
        guard isPlaying else { return }
        cells.forEach { cell in
            guard let layer = cell.layer, layer.speed != 0 else { return }
            layer.speed = max(playingSpeed, 0.01)
        }
        #else
        if isPlaying {
            cells.forEach {
                invalidateAnimation(for: $0, key: TOP_ANIMATION_KEY)
            }
        }
        if isPlaying {
            cells.forEach {
                addAnimation(to: $0)
            }
        }
        #endif
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
        #if os(macOS)
        cells.forEach { resumeVerticalClock(of: $0) }
        #else
        cells.forEach {
            addAnimation(to: $0)
        }
        #endif
    }
    
    func play(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        resumeVerticalClock(of: findCell)
        #else
        addAnimation(to: findCell)
        #endif
        return true
    }
    
    func pause() {
        #if os(macOS)
        cells.forEach { pauseVerticalClock(of: $0) }
        #else
        cells.forEach {
            invalidateAnimation(for: $0, key: TOP_ANIMATION_KEY)
        }
        #endif
    }
    
    func pause(_ danmaku: DanmakuCellModel) -> Bool {
        guard let findCell = cells.first(where: { (c) -> Bool in
            return c.model?.isEqual(to: danmaku) ?? false
        }) else { return false }
        #if os(macOS)
        pauseVerticalClock(of: findCell)
        #else
        invalidateAnimation(for: findCell, key: TOP_ANIMATION_KEY)
        #endif
        return true
    }

    #if os(macOS)
    private func pauseVerticalClock(of cell: DanmakuCell) {
        guard let layer = cell.layer, layer.speed != 0 else { return }
        let t = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = t
    }

    private func resumeVerticalClock(of cell: DanmakuCell) {
        guard let layer = cell.layer else { return }
        let rate = max(playingSpeed, 0.01)
        if layer.speed == 0 {
            let pausedTime = layer.timeOffset
            layer.speed = 1.0
            layer.timeOffset = 0
            layer.beginTime = 0
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.beginTime = now - pausedTime
            layer.speed = rate
        } else {
            layer.speed = rate
        }
    }
    #endif
    
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
        // Ensure horizontally centered before scheduling fade-out
        if let vw = view {
            let originX = (vw.bounds.width - danmaku.bounds.width) / 2.0
            let originY = positionY - danmaku.bounds.height / 2.0
            danmaku.frame.origin = CGPoint(x: originX, y: originY)
        }
        // Author hold time at 1×; apply playback rate via layer.speed.
        let animation = CABasicAnimation(keyPath: "opacity")
        _ = configureAnimation(animation, for: danmaku, playingSpeed: 1.0)
        if let layer = danmaku.layer {
            layer.speed = 1.0
            layer.timeOffset = 0
            layer.beginTime = 0
            let layerNow = layer.convertTime(CACurrentMediaTime(), from: nil)
            animation.beginTime = layerNow + cellModel.displayTime * rate
            animation.duration = 0
            animation.delegate = self
            animation.toValue = 0
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            layer.add(animation, forKey: TOP_ANIMATION_KEY)
            layer.speed = max(playingSpeed, 0.01)
        }
        #else
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
        danmaku.layer.add(animation, forKey: TOP_ANIMATION_KEY)
        #endif
    }
    
}

func prepare(danmaku: DanmakuCell) {
    danmaku.animationGeneration &+= 1
    danmaku.animationTime = 0
    #if os(macOS)
    if let layer = danmaku.layer {
        layer.opacity = 1
        // Cell reuse must not inherit a paused/time-shifted clock.
        layer.speed = 1.0
        layer.timeOffset = 0
        layer.beginTime = 0
    }
    #else
    danmaku.layer.opacity = 1
    #endif
}
