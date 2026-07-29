# Atomic Playback-Rate Retiming Implementation Plan

> For agentic workers: execute this plan incrementally, preserving a visible
> RED/GREEN test sequence. Do not commit unless the user explicitly requests it.

**Goal:** Fix the iOS/tvOS track starvation caused by frequent playback-rate
changes while keeping existing on-screen danmaku continuously retimed.

**Architecture:** Move speed changes from an asynchronous whole-view
pause/replay cycle into a coalesced view-level update and an atomic track-level
retime operation. Isolate CAAnimation callbacks with per-animation generation
and timing metadata.

**Tech Stack:** Swift, UIKit/AppKit conditional code, Core Animation, XCTest,
Xcode iOS/tvOS builds.

**Global Constraints:**

- Work directly on `master` as requested.
- Do not commit until explicitly asked.
- Keep public API compatibility.
- Do not add timers, display links, or per-frame polling.

## Task 1: Lock in the two races with failing tests

**Files:**

- Modify: `Example/Tests/Tests.swift`

Add tests proving:

1. `playingSpeed = ...; pause()` remains paused after the old 10 ms resume
   window.
2. After a track animation is replaced, manually delivering the old
   animation's completion cannot remove the replacement.

Run the focused test target and confirm failures are caused by current
production behavior.

## Task 2: Add immutable animation identity and timing

**Files:**

- Modify: `Sources/DanmakuKit/Classes/Core/DanmakuCell.swift`
- Modify: `Sources/DanmakuKit/Classes/Core/DanmakuTrack.swift`

Add a monotonically increasing generation to each cell. Store generation,
start time, and speed on each installed animation. Before removing an animation,
account for its elapsed media time and invalidate its generation. Ignore stale
delegate callbacks.

## Task 3: Implement atomic track retiming

**Files:**

- Modify: `Sources/DanmakuKit/Classes/Core/DanmakuTrack.swift`

Extend the internal track protocol with a speed-update operation. Floating
tracks sample presentation frames before replacement. Fixed tracks retain their
cell and replace only the active timing animation. Paused tracks update their
configured speed without installing animations.

Run the stale-callback regression test and confirm it passes.

## Task 4: Coalesce view speed changes and preserve state

**Files:**

- Modify: `Sources/DanmakuKit/Classes/Core/DanmakuView.swift`

Replace `playingSpeed`'s delayed pause/play with a single pending main-queue
application. Flush pending speed before `play` and `shoot`. Make generic
configuration updates synchronous and preserve the prior view status.

Run the pause regression test and confirm it passes.

## Task 5: Stress and platform verification

**Files:**

- Modify: `Example/Tests/Tests.swift`

Add a rapid-switch regression that writes many speeds, waits one main-loop turn,
and verifies the final speed and track availability.

Run:

1. iOS Simulator tests for the Example workspace.
2. iOS build for the Example scheme.
3. tvOS build for the library/example-compatible target when available.
4. `git diff --check` and a final diff review.

Leave all changes unstaged and uncommitted for user review.
