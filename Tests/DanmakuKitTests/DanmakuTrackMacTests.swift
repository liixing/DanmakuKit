#if os(macOS)
import AppKit
import QuartzCore
import XCTest
@testable import DanmakuKit

final class DanmakuTrackMacTests: XCTestCase {
    func testMacTrackAcceptsFollowerAtTwentyPointGap() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 40),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        container.wantsLayer = true
        window.contentView = container
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let track = DanmakuFloatingTrack(view: container)
        track.positionY = 20

        let leader = TestDanmakuCell(frame: CGRect(x: 320, y: 10, width: 80, height: 20))
        leader.model = TestDanmakuModel(size: leader.frame.size, displayTime: 2)
        container.addSubview(leader)
        track.shoot(danmaku: leader)

        let follower = TestDanmakuModel(
            identifier: "follower",
            size: leader.frame.size,
            displayTime: 2
        )
        let deadline = Date(timeIntervalSinceNow: 0.5)
        while Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
            guard let frame = leader.layer?.presentation()?.frame else { continue }
            let gap = container.bounds.width - frame.maxX
            if gap >= 20, gap <= 22 {
                XCTAssertTrue(track.canShoot(danmaku: follower), "Track overblocked at gap \(gap)")
                return
            }
        }
        XCTFail("Leader never reached the measured gap")
    }

    func testRealViewNeverCollapsesTracksOrOverlapsDuringPauseAndRateChanges() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let danmakuView = DanmakuView(frame: window.contentView!.bounds)
        danmakuView.autoresizingMask = [.width, .height]
        danmakuView.trackHeight = 30
        danmakuView.enableCellReusable = true
        window.contentView = danmakuView
        window.orderFront(nil)
        danmakuView.play()

        func visibleCenters() -> [ObjectIdentifier: CGPoint] {
            Dictionary(uniqueKeysWithValues: danmakuView.subviews.compactMap { view in
                guard let cell = view as? TestDanmakuCell,
                      let layer = cell.layer,
                      layer.animation(forKey: FLOATING_ANIMATION_KEY) != nil
                else { return nil }
                let frame = layer.presentation()?.frame ?? cell.frame
                return (ObjectIdentifier(cell), CGPoint(x: frame.midX, y: frame.midY))
            })
        }

        func assertNoVisibleJump(_ action: () -> Void, tick: Int) {
            let before = visibleCenters()
            action()
            CATransaction.flush()
            let after = visibleCenters()
            for (cell, oldCenter) in before {
                guard let newCenter = after[cell] else { continue }
                XCTAssertEqual(newCenter.x, oldCenter.x, accuracy: 5, "X jumped at tick \(tick)")
                XCTAssertEqual(newCenter.y, oldCenter.y, accuracy: 0.5, "Y jumped at tick \(tick)")
            }
        }

        for tick in 0..<220 {
            switch tick {
            case 40:
                assertNoVisibleJump({
                    danmakuView.pause()
                    danmakuView.playingSpeed = 2
                    danmakuView.layoutSubtreeIfNeeded()
                    danmakuView.recalculateTracks()
                    danmakuView.play()
                }, tick: tick)
            case 80:
                assertNoVisibleJump({ danmakuView.playingSpeed = 0.5 }, tick: tick)
            case 120:
                assertNoVisibleJump({ danmakuView.playingSpeed = 3 }, tick: tick)
            case 160:
                assertNoVisibleJump({ danmakuView.playingSpeed = 1 }, tick: tick)
            default:
                break
            }

            for item in 0..<6 {
                let model = TestDanmakuModel(
                    identifier: "stress-\(tick)-\(item)",
                    size: CGSize(width: 30 + (tick * 17 + item * 37) % 150, height: 20),
                    displayTime: 1.2
                )
                if danmakuView.canShoot(danmaku: model) {
                    danmakuView.shoot(danmaku: model)
                }
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            let visible = danmakuView.subviews.compactMap { $0 as? TestDanmakuCell }
                .compactMap { cell -> (TestDanmakuCell, CGRect)? in
                    guard let layer = cell.layer,
                          layer.animation(forKey: FLOATING_ANIMATION_KEY) != nil,
                          let track = cell.model?.track
                    else { return nil }
                    let presented = layer.presentation()
                    let center = CGPoint(
                        x: presented?.frame.midX ?? cell.frame.midX + layer.transform.m41,
                        y: presented?.frame.midY ?? cell.frame.midY
                    )
                    let expectedY = CGFloat(track) * 30 + 15
                    XCTAssertEqual(
                        center.y,
                        expectedY,
                        accuracy: 0.5,
                        "Track collapsed at tick \(tick): model track \(track), visible Y \(center.y), "
                            + "viewFrame \(cell.frame), layerPosition \(layer.position), "
                            + "presentationPosition \(String(describing: presented?.position)), "
                            + "presentationFrame \(String(describing: presented?.frame))"
                    )
                    return (
                        cell,
                        CGRect(
                            x: center.x - cell.bounds.width / 2,
                            y: center.y - cell.bounds.height / 2,
                            width: cell.bounds.width,
                            height: cell.bounds.height
                        )
                    )
                }

            for leftIndex in visible.indices {
                for rightIndex in visible.index(after: leftIndex)..<visible.endIndex {
                    let left = visible[leftIndex]
                    let right = visible[rightIndex]
                    if left.0.model?.track == right.0.model?.track {
                        let gap = max(
                            right.1.minX - left.1.maxX,
                            left.1.minX - right.1.maxX
                        )
                        XCTAssertGreaterThanOrEqual(
                            gap,
                            6,
                            "Unsafe same-track gap at tick \(tick): \(gap)"
                        )
                    }
                    let overlap = left.1.intersection(right.1).intersection(danmakuView.bounds)
                    guard overlap.width > 1, overlap.height > 1 else { continue }
                    XCTFail(
                        "Danmaku overlap at tick \(tick), speed \(danmakuView.playingSpeed): "
                            + "tracks \(left.0.model?.track.map(String.init) ?? "nil")/"
                            + "\(right.0.model?.track.map(String.init) ?? "nil"), overlap \(overlap)"
                    )
                    window.orderOut(nil)
                    return
                }
            }
        }
        window.orderOut(nil)
    }

}

private final class TestDanmakuCell: DanmakuCell {}

private struct TestDanmakuModel: DanmakuCellModel {
    let cellClass: DanmakuCell.Type = TestDanmakuCell.self
    let size: CGSize
    var track: UInt?
    let displayTime: Double
    let type: DanmakuCellType = .floating
    let identifier: String

    init(
        identifier: String = "mac-animation-continuity",
        size: CGSize = CGSize(width: 80, height: 20),
        displayTime: Double = 8
    ) {
        self.identifier = identifier
        self.size = size
        self.displayTime = displayTime
    }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        identifier == cellModel.identifier
    }
}
#endif
