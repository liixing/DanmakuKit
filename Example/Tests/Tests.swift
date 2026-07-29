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
}

private final class TestDanmakuCell: DanmakuCell {}

private final class TestDanmakuModel: DanmakuCellModel {

    let cellClass: DanmakuCell.Type = TestDanmakuCell.self
    let size = CGSize(width: 100, height: 30)
    var track: UInt?
    let displayTime: Double = 60
    let type: DanmakuCellType
    let identifier: String

    init(identifier: String, type: DanmakuCellType) {
        self.identifier = identifier
        self.type = type
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        return identifier == cellModel.identifier
    }
}
