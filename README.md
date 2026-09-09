# victor-mac-kit

The pieces **Victor Addons** and **Walkie Talkie** both need, kept in one place
so the gesture is literally the same code in both rather than approximately the
same code in two.

Today that is one gesture: **dragging out a region of the screen**.

| file | what it is |
|---|---|
| `CropGeometry` | the arithmetic — the box from two corners, ⌥ from the middle, ⌘ moving it, held inside its screen, and the flip into image pixels. Decided here, unit-tested here. |
| `CropSelectionOverlay` | the dimming, the rectangle, the size readout. One panel per screen, driven by a 60 Hz poll of session input state rather than by AppKit events, so it needs no key window and steals no focus from the room. |
| `CropCapture` | the chosen rectangle → a JPEG, by capturing the whole display and cropping at the display's real pixel scale. |

## Why the two apps disagree about so little

`CropSelectionStyle` is the whole surface of it: the accent colour and three
strings. Victor Addons speaks Romanian on screen; Walkie Talkie's overlay is
English-only, because its chip is on a projector in front of an international
room. Nothing else is per-app.

`begin(button:from:)` is the other difference and it is about *how the gesture
starts*. Victor Addons holds ⌃P, lets go, and then draws a box with the left
button. Walkie Talkie has a drag under way already — the wheel is down and the
hand is moving — so it hands in the corner it started from and the box is live
on the first frame.

## It is a path dependency, on purpose

Both apps declare `.package(path: "../victor-mac-kit")`. That means a fresh
clone of either one needs this folder checked out beside it — which is the
trade for being able to edit the shared code and rebuild the app in one step,
with no push, no version bump and no resolve. Both apps are only ever built on
Victor's Mac, from local, so that is the right side of the trade.
