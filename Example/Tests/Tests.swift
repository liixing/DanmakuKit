import UIKit
import XCTest
@testable import DanmakuKit

final class PlaybackRateRetimingTests: XCTestCase {

    func testSpeedChangeDoesNotResumeViewAfterExplicitPause() {
        let danmakuView = DanmakuView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        danmakuView.play()

        danmakuView.playingSpeed = 2
        danmakuView.pause()

        let settled = expectation(description: "pending speed update settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            if case .pause = danmakuView.status {
                // Expected.
            } else {
                XCTFail("A stale speed update resumed a view that was explicitly paused")
            }
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)
    }

    func testStaleVerticalAnimationCompletionDoesNotRemoveReplacementAnimation() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let track = DanmakuVerticalTrack(view: container)
        track.positionY = 15

        let cell = TestDanmakuCell(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        cell.model = TestDanmakuModel(identifier: "stale-callback", type: .top)
        container.addSubview(cell)
        track.shoot(danmaku: cell)

        let staleAnimation = try XCTUnwrap(cell.layer.animation(forKey: TOP_ANIMATION_KEY))
        track.pause()
        track.play()
        XCTAssertNotNil(cell.layer.animation(forKey: TOP_ANIMATION_KEY))

        track.animationDidStop(staleAnimation, finished: true)

        XCTAssertEqual(track.danmakuCount, 1, "An old callback removed the cell owned by a newer animation")
        XCTAssertNotNil(cell.layer.animation(forKey: TOP_ANIMATION_KEY))
    }

    func testUnexpectedCurrentAnimationRemovalReleasesVerticalTrack() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let track = DanmakuVerticalTrack(view: container)
        let cell = TestDanmakuCell(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let model = TestDanmakuModel(identifier: "removed-animation", type: .top)
        cell.model = model
        container.addSubview(cell)
        track.shoot(danmaku: cell)

        let removedAnimation = try XCTUnwrap(cell.layer.animation(forKey: TOP_ANIMATION_KEY))
        track.animationDidStop(removedAnimation, finished: false)

        XCTAssertEqual(track.danmakuCount, 0)
        XCTAssertTrue(track.canShoot(danmaku: model), "A cell without an animation must not block the track")
    }

    func testRapidSpeedAssignmentsRetimesExistingCellsOnceToFinalSpeed() throws {
        let danmakuView = DanmakuView(frame: CGRect(x: 0, y: 0, width: 320, height: 20))
        danmakuView.play()
        danmakuView.shoot(danmaku: TestDanmakuModel(identifier: "floating", type: .floating))
        danmakuView.shoot(danmaku: TestDanmakuModel(identifier: "top", type: .top))
        danmakuView.shoot(danmaku: TestDanmakuModel(identifier: "bottom", type: .bottom))

        let activeCells = try XCTUnwrap(danmakuView.subviews as? [TestDanmakuCell])
        XCTAssertEqual(activeCells.count, 3)
        let initialGenerations = Dictionary(
            uniqueKeysWithValues: activeCells.compactMap { cell in
                cell.model.map { ($0.identifier, cell.animationGeneration) }
            }
        )

        for index in 0..<200 {
            danmakuView.playingSpeed = 0.5 + Float(index % 8) * 0.5
        }
        danmakuView.playingSpeed = 4

        let settled = expectation(description: "coalesced speed update applied")
        DispatchQueue.main.async {
            for cell in activeCells {
                guard let model = cell.model else {
                    XCTFail("Active cell lost its model")
                    continue
                }
                let key = model.type == .floating ? FLOATING_ANIMATION_KEY : TOP_ANIMATION_KEY
                guard let animation = cell.layer.animation(forKey: key) else {
                    XCTFail("\(model.identifier) lost its animation after rapid speed changes")
                    continue
                }
                let appliedSpeed = (animation.value(forKey: DANMAKU_ANIMATION_SPEED_KEY) as? NSNumber)?.floatValue
                XCTAssertEqual(appliedSpeed, 4)
                XCTAssertEqual(
                    cell.animationGeneration,
                    initialGenerations[model.identifier].map { $0 + 2 },
                    "Same-turn speed changes should install only one replacement animation"
                )
            }
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)
    }

    func testCrossRunLoopSpeedStressKeepsEveryTrackAnimated() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 20))
        let danmakuView = DanmakuView(frame: CGRect(x: 0, y: 0, width: 320, height: 20))
        window.addSubview(danmakuView)
        window.isHidden = false
        danmakuView.play()
        danmakuView.shoot(danmaku: TestDanmakuModel(identifier: "stress-floating", type: .floating))
        danmakuView.shoot(danmaku: TestDanmakuModel(identifier: "stress-top", type: .top))
        danmakuView.shoot(danmaku: TestDanmakuModel(identifier: "stress-bottom", type: .bottom))

        for index in 0..<200 {
            danmakuView.playingSpeed = 0.5 + Float(index % 8) * 0.5
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        danmakuView.playingSpeed = 2
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

        let activeCells = try XCTUnwrap(danmakuView.subviews as? [TestDanmakuCell])
        XCTAssertEqual(activeCells.count, 3, "A track lost its cell during repeated animation replacement")
        for cell in activeCells {
            let type = try XCTUnwrap(cell.model?.type)
            let key = type == .floating ? FLOATING_ANIMATION_KEY : TOP_ANIMATION_KEY
            let animation = try XCTUnwrap(
                cell.layer.animation(forKey: key),
                "A track retained its cell without a live animation"
            )
            let appliedSpeed = (animation.value(forKey: DANMAKU_ANIMATION_SPEED_KEY) as? NSNumber)?.floatValue
            XCTAssertEqual(appliedSpeed, 2)
        }
    }

    func testFloatingSpeedRetimingKeepsTheTrackPositionAfterLayoutChange() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        window.isHidden = false

        let track = DanmakuFloatingTrack(view: container)
        track.positionY = 15
        let cell = TestDanmakuCell(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        cell.model = TestDanmakuModel(identifier: "layout-retime", type: .floating)
        container.addSubview(cell)
        track.shoot(danmaku: cell)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

        track.positionY = 75
        track.updatePlayingSpeed(2, isPlaying: true)

        XCTAssertEqual(
            cell.layer.position.y,
            75,
            accuracy: 0.001,
            "Speed retiming must not restore the stale presentation-layer row"
        )
    }

    func testExpandingThenShrinkingDisplayAreaKeepsEveryFloatingTrackUsable() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let danmakuView = DanmakuView(frame: window.bounds)
        window.addSubview(danmakuView)
        window.isHidden = false
        danmakuView.trackHeight = 30
        danmakuView.displayArea = 0.5
        danmakuView.enableCellReusable = true
        danmakuView.play()

        var tracksUsedAfterResize = Set<UInt>()
        for tick in 0..<220 {
            if (20..<70).contains(tick) {
                danmakuView.update {
                    danmakuView.displayArea = 0.5 + CGFloat(tick - 19) * 0.01
                }
            } else if (70..<120).contains(tick) {
                danmakuView.update {
                    danmakuView.displayArea = 1 - CGFloat(tick - 69) * 0.01
                }
            }

            let models = (0..<6).map { item in
                TestDanmakuModel(
                    identifier: "display-area-\(tick)-\(item)",
                    type: .floating,
                    size: CGSize(width: 20 + (tick * 13 + item * 29) % 160, height: 20),
                    displayTime: 0.35
                )
            }
            models.forEach(danmakuView.shoot(danmaku:))
            if tick >= 160 {
                tracksUsedAfterResize.formUnion(models.compactMap(\.track))
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }

        XCTAssertEqual(
            tracksUsedAfterResize,
            Set([0, 1]),
            "Restoring the original display area permanently lost a floating track"
        )
    }

    func testLongPressRateChangesDoNotStarveAnyFloatingTrack() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let danmakuView = DanmakuView(frame: window.bounds)
        window.addSubview(danmakuView)
        window.isHidden = false
        danmakuView.trackHeight = 30
        danmakuView.enableCellReusable = true
        danmakuView.play()

        var tracksUsedAfterLongPress = Set<UInt>()
        for tick in 0..<300 {
            if tick < 100 {
                danmakuView.playingSpeed = 1 + Float(tick % 40) * 0.1
            } else if tick == 100 {
                danmakuView.playingSpeed = 1
            }

            let models = (0..<8).map { item in
                TestDanmakuModel(
                    identifier: "long-press-\(tick)-\(item)",
                    type: .floating,
                    size: CGSize(width: 20 + (tick * 17 + item * 31) % 180, height: 20),
                    displayTime: 0.4
                )
            }
            models.forEach(danmakuView.shoot(danmaku:))
            if tick >= 180 {
                tracksUsedAfterLongPress.formUnion(models.compactMap(\.track))
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }

        let liveCellDiagnostics = danmakuView.subviews.compactMap { view -> String? in
            guard let cell = view as? TestDanmakuCell,
                  let animation = cell.layer.animation(forKey: FLOATING_ANIMATION_KEY) else {
                return nil
            }
            return "track=\(cell.model?.track.map(String.init) ?? "nil") "
                + "frameX=\(cell.frame.origin.x) realX=\(cell.realFrame.origin.x) "
                + "duration=\(animation.duration) begin=\(animation.beginTime) "
                + "generation=\(cell.animationGeneration)"
        }
        XCTAssertEqual(
            tracksUsedAfterLongPress,
            Set([0, 1, 2, 3]),
            "A floating track stayed unavailable after long-press playback-rate changes ended. "
                + liveCellDiagnostics.joined(separator: " | ")
        )
    }

    func testRapidRateChangesNeverAllowFloatingCellsToOverlap() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        let danmakuView = DanmakuView(frame: window.bounds)
        window.addSubview(danmakuView)
        window.isHidden = false
        danmakuView.trackHeight = 30
        danmakuView.enableCellReusable = true
        danmakuView.play()

        for tick in 0..<300 {
            if tick < 100 {
                danmakuView.playingSpeed = 1 + Float(tick % 40) * 0.1
            } else if tick == 100 {
                danmakuView.playingSpeed = 1
            }

            let models = (0..<8).map { item in
                TestDanmakuModel(
                    identifier: "collision-\(tick)-\(item)",
                    type: .floating,
                    size: CGSize(width: 20 + (tick * 17 + item * 31) % 180, height: 20),
                    displayTime: 0.4
                )
            }
            models.forEach(danmakuView.shoot(danmaku:))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            let activeCells = danmakuView.subviews.compactMap { view -> TestDanmakuCell? in
                guard let cell = view as? TestDanmakuCell,
                      cell.layer.animation(forKey: FLOATING_ANIMATION_KEY) != nil else {
                    return nil
                }
                return cell
            }
            let visibleFrames = activeCells.map { cell -> (TestDanmakuCell, CGRect) in
                (cell, cell.realFrame)
            }

            for leftIndex in visibleFrames.indices {
                for rightIndex in visibleFrames.index(after: leftIndex)..<visibleFrames.endIndex {
                    let left = visibleFrames[leftIndex]
                    let right = visibleFrames[rightIndex]
                    let visibleOverlap = left.1
                        .intersection(right.1)
                        .intersection(danmakuView.bounds)
                    guard visibleOverlap.width > 1, visibleOverlap.height > 1 else { continue }
                    XCTFail(
                        "Floating danmaku overlapped at tick \(tick), speed \(danmakuView.playingSpeed), "
                            + "tracks \(left.0.model?.track.map(String.init) ?? "nil")/"
                            + "\(right.0.model?.track.map(String.init) ?? "nil"): "
                            + "\(left.0.model?.identifier ?? "nil") \(left.1) intersects "
                            + "\(right.0.model?.identifier ?? "nil") \(right.1), "
                            + "visible overlap \(visibleOverlap)"
                    )
                    return
                }
            }
        }
    }

    func testNewlyReusedFloatingCellImmediatelyBlocksItsTrack() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 30))
        let danmakuView = DanmakuView(frame: window.bounds)
        window.addSubview(danmakuView)
        window.isHidden = false
        danmakuView.trackHeight = 30
        danmakuView.enableCellReusable = true
        danmakuView.play()

        danmakuView.shoot(
            danmaku: TestDanmakuModel(
                identifier: "completed",
                type: .floating,
                size: CGSize(width: 60, height: 20),
                displayTime: 0.02
            )
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        danmakuView.shoot(
            danmaku: TestDanmakuModel(
                identifier: "reused",
                type: .floating,
                size: CGSize(width: 60, height: 20),
                displayTime: 8
            )
        )

        XCTAssertFalse(
            danmakuView.canShoot(
                danmaku: TestDanmakuModel(
                    identifier: "next",
                    type: .floating,
                    size: CGSize(width: 60, height: 20),
                    displayTime: 8
                )
            ),
            "A reused cell still presenting its previous offscreen position admitted another cell into the same track"
        )
    }

    func testImmediateRateChangeDoesNotRestoreAReusedCellsPreviousPosition() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 30))
        let danmakuView = DanmakuView(frame: window.bounds)
        window.addSubview(danmakuView)
        window.isHidden = false
        danmakuView.trackHeight = 30
        danmakuView.enableCellReusable = true
        danmakuView.play()

        danmakuView.shoot(
            danmaku: TestDanmakuModel(
                identifier: "completed-before-retiming",
                type: .floating,
                size: CGSize(width: 60, height: 20),
                displayTime: 0.02
            )
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        danmakuView.shoot(
            danmaku: TestDanmakuModel(
                identifier: "reused-before-retiming",
                type: .floating,
                size: CGSize(width: 60, height: 20),
                displayTime: 8
            )
        )
        danmakuView.playingSpeed = 3
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))

        let cell = try XCTUnwrap(
            danmakuView.subviews.compactMap { $0 as? TestDanmakuCell }.first {
                $0.model?.identifier == "reused-before-retiming"
            }
        )
        let animation = try XCTUnwrap(
            cell.layer.animation(forKey: FLOATING_ANIMATION_KEY) as? CABasicAnimation
        )
        let fromX = try XCTUnwrap((animation.fromValue as? NSNumber)?.doubleValue)
        XCTAssertGreaterThan(
            fromX,
            300,
            "Retiming a newly reused cell must not restore its previous generation's offscreen presentation position"
        )
    }

    func testImmediateRateChangeAfterReusingFloatingCellKeepsFiniteGeometry() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 30))
        let container = UIView(frame: window.bounds)
        window.addSubview(container)
        window.isHidden = false

        let track = DanmakuFloatingTrack(view: container)
        track.positionY = 15
        let cell = TestDanmakuCell(frame: CGRect(x: 320, y: 0, width: 20, height: 20))
        cell.model = TestDanmakuModel(
            identifier: "first-generation",
            type: .floating,
            size: cell.bounds.size,
            displayTime: 8
        )
        container.addSubview(cell)
        track.shoot(danmaku: cell)

        let completedAnimation = try XCTUnwrap(cell.layer.animation(forKey: FLOATING_ANIMATION_KEY))
        track.animationDidStop(completedAnimation, finished: true)
        XCTAssertTrue(
            cell.layer.position.x.isFinite,
            "Completed reusable cells must not poison their presentation layer with infinite geometry"
        )

        cell.frame = CGRect(x: 320, y: 0, width: 20, height: 20)
        cell.model = TestDanmakuModel(
            identifier: "reused-generation",
            type: .floating,
            size: cell.bounds.size,
            displayTime: 8
        )
        track.shoot(danmaku: cell)
        track.updatePlayingSpeed(3, isPlaying: true)

        let replacement = try XCTUnwrap(cell.layer.animation(forKey: FLOATING_ANIMATION_KEY))
        XCTAssertTrue(cell.layer.position.x.isFinite, "Retiming restored non-finite geometry from the pooled cell")
        XCTAssertTrue(replacement.duration.isFinite, "Non-finite reused geometry created an animation that never ends")
    }

}

private final class TestDanmakuCell: DanmakuCell {}

private final class TestDanmakuModel: DanmakuCellModel {

    let cellClass: DanmakuCell.Type = TestDanmakuCell.self
    let size: CGSize
    var track: UInt?
    let displayTime: Double
    let type: DanmakuCellType
    let identifier: String

    init(
        identifier: String,
        type: DanmakuCellType,
        size: CGSize = CGSize(width: 100, height: 30),
        displayTime: Double = 60
    ) {
        self.identifier = identifier
        self.type = type
        self.size = size
        self.displayTime = displayTime
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        return identifier == cellModel.identifier
    }
}
