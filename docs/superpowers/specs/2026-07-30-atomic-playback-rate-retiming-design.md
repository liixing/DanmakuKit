# Atomic Playback-Rate Retiming Design

## Problem

Frequent changes to `DanmakuView.playingSpeed` can leave one danmaku track
permanently occupied even though no cell is visible. The track only becomes
usable after `clean()` (normally triggered by seek).

The failure has two interacting causes:

1. `DanmakuView.update` pauses immediately and schedules an unversioned
   `play()` 10 ms later. An older delayed resume can run after a newer pause or
   speed update.
2. Tracks keep animation timing in mutable cell/track state. A callback from an
   animation that was removed during retiming can observe the timing and speed
   of a newer animation, or remove the cell that now belongs to that newer
   animation generation.

Fixed-position tracks only accept a new cell when `cells` is empty, so one
stale cell blocks the entire track indefinitely. Seeking calls `clean()`, which
explains why seek recovers it.

## Required Behavior

- Existing on-screen danmaku changes speed continuously on the next main-loop
  turn; it must not wait for the next segment or newly created cell.
- A pause, stop, or clean performed after a speed assignment must not be
  overridden by work scheduled by an older assignment.
- Callbacks from removed animations must not mutate or remove a newer
  animation generation.
- Multiple speed assignments in the same main-loop turn apply only the latest
  value.
- The normal animation path adds no timer and no per-frame polling.
- iOS and tvOS use the same corrected DanmakuKit implementation.

## Design

### Atomic track retiming

Each track exposes a speed-update operation. When the view is playing, it:

1. Samples every active floating cell's presentation frame.
2. Accounts for elapsed media time using the speed captured by that specific
   animation.
3. Invalidates the current animation generation before removing the animation.
4. Installs a new animation immediately from the sampled position with the new
   speed.

When the view is paused, only the track speed changes because pause has already
captured the cells' progress.

### Animation generation isolation

Each installed animation carries immutable metadata:

- generation identifier
- wall-clock start time
- playback speed

The cell holds the currently valid generation. `animationDidStop` ignores a
callback whose generation no longer matches. Timing is calculated from the
animation's metadata, never from the track's current speed.

If Core Animation removes the currently valid animation unexpectedly, the
track retires that cell immediately. Intentional pause/retime removals advance
the generation first, so their callbacks are ignored and their cells remain
available for resume.

### View-level speed coalescing

`playingSpeed` schedules one main-queue application. Further assignments before
that block runs replace only the pending value. The block reads the current
view status and retimes tracks without cycling the whole view through
`pause()`/`play()`.

Operations that must observe the newest value (`play` and `shoot`) flush a
pending speed change synchronously first.

### State-safe generic updates

Other configuration changes preserve whether the view was playing. They no
longer schedule an unconditional delayed `play()`.

## Performance

An applied speed change remains O(number of active cells), as in the previous
pause/replay implementation. Same-turn coalescing reduces redundant work during
rapid rate switching. Normal playback adds only constant metadata per animation
and no ongoing CPU work.

## Verification

Deterministic regression tests cover:

- an old speed update cannot resume a subsequently paused view
- a stale animation completion cannot remove the current animation generation
- rapid speed assignments settle on the final speed while tracks remain usable

The Example test target is then built and run for an iOS Simulator. The library
is also compiled for tvOS to validate the shared code path.
