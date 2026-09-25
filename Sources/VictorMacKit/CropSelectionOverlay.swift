import AppKit
import QuartzCore

/// The selection UI for a screen region — ours, in place of `screencapture -i`.
///
/// **Two apps drive it, and they drive it differently.** Victor Addons puts it
/// up on ⌃P **held** and waits for a left-button drag; Walkie Talkie has one
/// under way already — the wheel is down and the hand is moving — so it hands
/// the anchor in and the box is live from the first frame. `begin(button:from:)`
/// is the whole of that difference: which button the poll watches for the
/// release, and whether there is a corner to start from.
///
/// **Why we stopped using the system's crosshair.** The selection had to learn
/// one thing macOS's own only offers on the **space bar**: a box you are still
/// dragging can be *moved* whole, instead of resized (and, with ⌥, drawn out
/// from its middle rather than from a corner). `screencapture -i` cannot
/// be told to read ⌘ for that, and translating ⌘ into a synthetic space keypress
/// means posting a key into a subprocess that owns the screen — one that
/// arrives, if the modifier leaks, as ⌘Space, i.e. Spotlight over the workshop's
/// projector. There is also nothing in it that can be asked to keep the box
/// *inside the screen*, which is the other half of the request.
///
/// Owning the selection pays for itself twice over: the crop rectangle is now
/// **known**, not reconstructed. The old `CropDragTracker` sampled
/// `CGEventSource.buttonState` every 8 ms behind screencapture's overlay purely
/// to guess where the drag had been, and the confirmation border then had to be
/// checked against the saved file's pixel dimensions before it dared draw
/// itself. Both are gone: we hand the exact rectangle to the capture *and* to
/// the border.
///
/// **How it is driven.** Not by AppKit's mouse events but by a 60 Hz poll of
/// session input state — `NSEvent.mouseLocation`, `CGEventSource.buttonState`,
/// `NSEvent.modifierFlags`, `CGEventSource.keyState` — the same technique the
/// drag tracker used, and for the same reason: it needs no key window, no app
/// activation and no focus stolen from whatever the room is looking at. The
/// panels still *accept* mouse events (they just drop them), which is what keeps
/// the drag from selecting text in the app underneath.
/// Which physical button the drag is being made with — i.e. the one whose
/// release ends the selection. `screencapture -i`'s answer is always the left
/// one; a gesture that *starts* with a button already down needs to say so.
public enum CropDragButton {
    case left
    case middle

    var cg: CGMouseButton { self == .left ? .left : .center }
}

/// The words and the colour, which are the only two things the two apps
/// disagree about. Everything else — the dimming, the readout, ⌘, ⌥, Esc —
/// is the same gesture in both, deliberately: Victor makes it in both apps,
/// minutes apart, in the same workshop.
///
/// The hint is a parameter and not a constant so an app can reword the legend,
/// but both callers take the English defaults below since 2026-09-16: Victor
/// Addons used to override them in Romanian, and one gesture reading
/// differently in the two apps — minutes apart, in the same workshop — was
/// worth more than the translation.
public struct CropSelectionStyle {
    public var accent: NSColor
    /// Shown before the drag begins, in the flavour that waits for one.
    public var hint: String
    /// **Always beside the size, and lit only while it is happening.** Victor,
    /// 2026-09-10: *"legenda «centre» și «move» să fie mereu prezentă când fac
    /// crop, dar să devină colorate cuvintele când chiar se întâmplă."*
    ///
    /// They were appended only while the modifier was down, which made them a
    /// *readout* — and a readout of a thing you already know you are doing, on
    /// the one row you look at while framing. As a permanent pair they are the
    /// legend for the two keys this gesture has, in the one place he is already
    /// looking, and the colour is then the readout: the word he is using goes
    /// from dim to the accent, so *nothing* is what the box is doing plainly.
    ///
    /// They name the **key**, not the effect, for the same reason: `⌘ move` on
    /// screen the whole time is how ⌘ gets learned, where `✥ move` — what these
    /// said while they were a readout — is a symbol for something he can see
    /// happening anyway.
    public var movingSuffix: String
    /// The other half of that pair; see `movingSuffix`.
    public var centeredSuffix: String
    /// **⇧ mid-drag: *this, moved to there*** (2026-09-24, Walkie Talkie only).
    /// Off by default, so an app that never asked for it keeps ⇧ meaning
    /// nothing. See `CropSelectionOverlay.Selection.movedTo`.
    public var allowsMove: Bool
    /// The legend word for ⇧, lit while a destination is being drawn.
    public var moveToSuffix: String
    /// Beside the pointer while the source is locked and the destination not
    /// yet drawn — the one moment nothing else on screen says what to do.
    public var moveHint: String

    public init(accent: NSColor = .systemYellow,
                hint: String = "⌘ move  ·  ⌥ centre",
                movingSuffix: String = "⌘ move",
                centeredSuffix: String = "⌥ centre",
                allowsMove: Bool = false,
                moveToSuffix: String = "⇧ move to",
                moveHint: String = "wheel-drag where it goes") {
        self.accent = accent
        self.hint = hint
        self.movingSuffix = movingSuffix
        self.centeredSuffix = centeredSuffix
        self.allowsMove = allowsMove
        self.moveToSuffix = moveToSuffix
        self.moveHint = moveHint
    }
}

public final class CropSelectionOverlay {
    public struct Selection {
        /// Global Cocoa coordinates, whole points, entirely within `screen`.
        public let rect: NSRect
        public let screen: NSScreen
        /// **Where the thing in `rect` should go** — set only when the drag
        /// ended with ⇧ held and a second box drawn (`allowsMove`). Victor,
        /// 2026-09-24: *"the old shape will remain there, locked … and then an
        /// arrow should lay from the center of it to wherever the new shape
        /// that I'm moving right now is."* Same coordinates as `rect`.
        public let movedTo: NSRect?

        public init(rect: NSRect, screen: NSScreen, movedTo: NSRect? = nil) {
            self.rect = rect
            self.screen = screen
            self.movedTo = movedTo
        }
    }

    /// Nothing smaller than this is a selection — it is a click that slipped.
    private static let minimumSide: CGFloat = 6

    private static var active: CropSelectionOverlay?

    /// Where this module's one diagnostic line goes. Each app points it at its
    /// own log; unset, nothing is written.
    public static var log: ((String) -> Void)?

    /// **A release the poll cannot see, because an event tap upstream ate it.**
    ///
    /// Measured the first time Walkie Talkie drove this with the wheel: it
    /// swallows the middle-up so the app underneath is not handed the end of a
    /// gesture it never saw the middle of — and a swallowed release **never
    /// reaches session button state**, so `buttonState` went on answering *down*
    /// after the finger came up and the dimming sat on the screen with no way
    /// out but Esc. The button is the app's own to report in that case, and it
    /// is the only one that can.
    ///
    /// A release that lands before the overlay is up is kept for `begin`, since
    /// the two arrive by different routes and a quick flick beats the panels on
    /// screen. It is only honoured for `pendingReleaseWindow` — long enough for
    /// the hop, short enough that a stale one cannot end the *next* selection
    /// before it starts.
    private static var pendingReleaseAt: CFAbsoluteTime = 0
    private static let pendingReleaseWindow: CFTimeInterval = 0.5

    /// **The pointer moved, pushed by the caller that is eating the events.**
    ///
    /// A `driven` drag has every one of its motion events swallowed by an event
    /// tap before any window sees them, and the 60 Hz poll that works for a
    /// left-button drag then turns out to be the weak link: it is a *timer* on
    /// the main run loop, and a box that stops following the hand while the
    /// button is held is exactly what a starved timer looks like. Reported by
    /// Victor on the first real drag — *"nu văd live chenarul selectat în timp
    /// ce țin jos wheel-ul, văd doar un chenar mic inițial și apoi, când dau
    /// release, cel final"* — and not reproducible with posted events, which is
    /// the tell: the caller is holding the answer in its hand and was throwing
    /// it away.
    ///
    /// So the position comes *in* rather than being fetched, and it draws on
    /// arrival. The timer stays for what only it can see — Esc, the right
    /// button, ⌘ and ⌥ — and the box no longer depends on it being given a turn.
    ///
    /// The point is in **global CG** coordinates, y down from the primary
    /// display's top, because that is what an event carries; the flip happens
    /// here, once, where a screen can safely be asked about.
    ///
    /// Must be called on the main thread.
    public static func dragMoved(toCG point: CGPoint) {
        guard let overlay = active, overlay.driven else { return }
        guard let primary = NSScreen.screens.first else { return }
        overlay.pushed = NSPoint(x: point.x, y: primary.frame.maxY - point.y)
        overlay.pushes += 1
        overlay.tick()
    }

    /// **The source is locked and the wheel is up: the next press is the
    /// destination's** (2026-09-24). Told to the caller that owns the button,
    /// because that press must be claimed on sight — no drag threshold, ⇧ and ⌘
    /// allowed — where any other press would be a click to hand back. Called on
    /// the main thread, `true` when the overlay parks, `false` when the
    /// destination starts or the selection ends.
    public static var onAwaitingDestination: ((Bool) -> Void)?

    /// The button went down again while parked: draw the destination from
    /// here. Global CG coordinates, like `dragMoved(toCG:)`. Main thread.
    public static func destinationPressed(atCG point: CGPoint) {
        guard let overlay = active, overlay.movePhase == .parked,
              let primary = NSScreen.screens.first else { return }
        overlay.startDestination(at: NSPoint(x: point.x, y: primary.frame.maxY - point.y))
    }

    /// Take a parked selection down with nothing filed — the sentence it
    /// belonged to is over. A drag still under the hand is left alone. Main.
    public static func cancelIfParked() {
        guard let overlay = active, overlay.movePhase == .parked else { return }
        overlay.finish(nil)
    }

    /// Must be called on the main thread.
    public static func endDrag() {
        if let overlay = active {
            overlay.released = true
        } else {
            pendingReleaseAt = CFAbsoluteTimeGetCurrent()
        }
    }

    /// Put the crosshair up. `completion` runs on the main thread, **after** the
    /// overlay is off the screen and the window server has had time to forget
    /// it — the capture that follows must not photograph our own dimming.
    ///
    /// `anchor` is the corner a drag **already in progress** started from, in
    /// global Cocoa coordinates. Passing one skips the crosshair entirely: the
    /// box is being dragged from the first tick, and the first thing on screen
    /// is a rectangle rather than an invitation to draw one.
    ///
    /// Must be called on the main thread.
    public static func begin(button: CropDragButton = .left,
                             from anchor: NSPoint? = nil,
                             style: CropSelectionStyle = CropSelectionStyle(),
                             completion: @escaping (Selection?) -> Void) {
        if active != nil { completion(nil); return }
        let overlay = CropSelectionOverlay(button: button, driven: anchor != nil,
                                           style: style, completion: completion)
        overlay.released = CFAbsoluteTimeGetCurrent() - pendingReleaseAt < pendingReleaseWindow
        pendingReleaseAt = 0
        active = overlay
        overlay.show(startingAt: anchor)
    }

    // MARK: - State

    private let completion: (Selection?) -> Void
    private let button: CropDragButton
    private let style: CropSelectionStyle
    private var panels: [(panel: NSPanel, view: CropOverlayView, screen: NSScreen)] = []
    private var timer: Timer?

    /// The corner that stays put while the mouse drags the other one.
    private var anchor: NSPoint = .zero
    /// Free corner = mouse + this. Zero until an edge refuses to let the box
    /// follow the cursor; then it carries exactly how far behind it fell.
    private var freeOffset: CGVector = .zero
    private var dragging = false
    /// The driving button is up, told to us rather than read — see `endDrag`.
    private var released = false
    /// Where the caller last saw the pointer — see `dragMoved(toCG:)`. Preferred
    /// over `NSEvent.mouseLocation` whenever it is there, because it is the
    /// position the event was *made* at rather than wherever the pointer has
    /// since got to.
    private var pushed: NSPoint?
    /// **The drag was handed in, so the button is the caller's to report.**
    ///
    /// A caller that owns the gesture through an event tap has, by then, already
    /// decided the button's fate — and either decision makes session button
    /// state the wrong thing to poll. Swallow the press and the state never says
    /// *down*, so the very first tick would end a selection that has not started;
    /// swallow the release and it never says *up*, so it never ends at all.
    /// Measured on Walkie Talkie's wheel drag, which does one of those in each of
    /// its two gesture modes: the first tick ended the selection instantly in
    /// one, and in the other the dimming stayed up with the finger long since
    /// lifted — and the window server went on believing the middle button was
    /// held, seven hours later, dragging an editor tab around behind the cursor.
    ///
    /// So in this mode the button is *not read at all*. `endDrag` is the whole
    /// of it, with Esc and the right button still there as the ways out that do
    /// not depend on the caller being alive.
    private let driven: Bool
    private var startScreen: NSScreen?
    /// Set on the ⌘ press, cleared on the release: where the mouse and the box
    /// were when the move began, so the translation is always measured from
    /// there rather than accumulated. `centered` is remembered too — ⌥ changes
    /// what the box *is*, so toggling it mid-move restarts the measurement.
    private var moveOrigin: (mouse: NSPoint, anchor: NSPoint, free: NSPoint, box: NSRect, centered: Bool)?
    /// **The box locked by ⇧, and how to give it back.** While ⇧ is held the
    /// first box stands still as the *source* and a second one is drawn from
    /// the pointer, corner to corner like the first (⌘ and ⌥ act on it).
    /// Letting ⇧ go drops the second box and hands the first one back to the
    /// hand, exactly the shape it was — *"if I release Shift then the whole
    /// thing falls back to the previous shape"*.
    private var moveSource: (box: NSRect, anchor: NSPoint, free: NSPoint)?
    /// **Where the ⇧ move is** (2026-09-24, Victor: *"while shift down, an
    /// arrow from center of first rectangle should follow my mouse, then stay
    /// on center of 2nd box when drawn by wheel drag"*):
    /// `pointing` — ⇧ pressed with the wheel still down: the source is locked
    /// and the arrow follows the pointer; ⇧ let go here gives the box back.
    /// `parked` — the wheel came up with the source locked: sticky, ⇧ no longer
    /// needed, the arrow still follows. `drawing` — the wheel went down again
    /// and the destination is being dragged; its release ships the move, or,
    /// too small to be a box, parks again.
    enum MovePhase { case none, pointing, parked, drawing }
    private(set) var movePhase: MovePhase = .none
    private var finished = false
    /// How the box was kept up to date, reported once when the selection ends.
    /// The question it answers is the one that took a bug report to ask: *was
    /// the box actually being redrawn while the button was down?*
    private var startedAt = Date()
    private var ticks = 0
    private var pushes = 0
    private var worstGap: TimeInterval = 0
    private var lastTick = Date()

    private init(button: CropDragButton, driven: Bool, style: CropSelectionStyle,
                 completion: @escaping (Selection?) -> Void) {
        self.button = button
        self.driven = driven
        self.style = style
        self.completion = completion
    }

    // MARK: - Lifecycle

    private func show(startingAt anchor: NSPoint?) {
        for screen in NSScreen.screens {
            let panel = CropPanel(contentRect: screen.frame,
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered,
                                  defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Accepting the mouse is the whole point of the window: the clicks
            // of the drag must land here and nowhere else.
            panel.ignoresMouseEvents = false
            // **Deliberately capturable**, unlike everything Walkie Talkie draws
            // near the pointer. It was `sharingType = .none` for an afternoon,
            // as belt and braces over the beat that already separates the panels
            // coming down from the shutter — and the price of those braces is
            // that the selection cannot be *reviewed*: not by a screenshot, not
            // by a person driving the Mac remotely, not by anything but a pair
            // of eyes on the glass at the moment it happens. That is exactly how
            // a box that stopped following the mouse went unnoticed. The beat is
            // what keeps the dimming out of the picture and always was.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let view = CropOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                       scale: screen.backingScaleFactor,
                                       style: style)
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append((panel, view, screen))
        }

        // A drag handed in is already under way: the button is down, the hand is
        // moving, and waiting for a press that has *already happened* would sit
        // there dimming the screen until he pressed the wheel a second time.
        if let anchor { startDrag(at: anchor) }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    private func finish(_ selection: Selection?) {
        guard !finished else { return }
        finished = true
        if movePhase != .none { Self.onAwaitingDestination?(false) }
        let seconds = Date().timeIntervalSince(startedAt)
        CropSelectionOverlay.log?(String(
            format: "✂️ selection over %.1fs — %d frames (%d pushed, %d polled), worst gap %.0fms",
            seconds, ticks, pushes, ticks - pushes, worstGap * 1000))
        timer?.invalidate()
        timer = nil
        for entry in panels { entry.panel.orderOut(nil) }

        // The panels are gone from AppKit's point of view; the compositor needs
        // a beat before the pixels behind them are what a capture would see.
        let done = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            CropSelectionOverlay.active = nil
            done(selection)
        }
        panels.removeAll()
    }

    // MARK: - The loop

    private func tick() {
        let now = Date()
        ticks += 1
        worstGap = max(worstGap, now.timeIntervalSince(lastTick))
        lastTick = now
        let mouse = pushed ?? NSEvent.mouseLocation
        let held = !released
            && (driven || CGEventSource.buttonState(.combinedSessionState, button: button.cg))
        // The right button cancels, and it is never the one being dragged with —
        // no caller asks for that, and it is the escape hatch that works even if
        // the caller driving the button has stopped answering.
        let rightDown = CGEventSource.buttonState(.combinedSessionState, button: .right)
        let escape = CGEventSource.keyState(.combinedSessionState, key: 53)

        // Esc and right-click both mean "never mind": no file, clipboard and
        // folder left exactly as they were.
        if escape || rightDown { finish(nil); return }

        guard dragging else {
            if held {
                startDrag(at: mouse)
            } else {
                render(selection: nil, cursor: mouse, moving: false)
            }
            return
        }

        guard let bounds = startScreen?.frame else { finish(nil); return }
        let flags = NSEvent.modifierFlags
        let moving = flags.contains(.command)
        // ⌥ held: the point the drag started from stops being a corner and
        // becomes the *middle* of the box, with the mouse still on a corner.
        let centered = flags.contains(.option)

        // ⇧ with the wheel down: lock the box as the source; the arrow follows
        // the pointer until a destination is drawn. See `MovePhase`.
        let shifted = style.allowsMove && flags.contains(.shift)
        switch movePhase {
        case .none:
            let box = currentRect(for: mouse, centered: centered)
            if shifted, held, box.width >= Self.minimumSide, box.height >= Self.minimumSide {
                moveSource = (box: box, anchor: anchor, free: freeCorner(for: mouse))
                moveOrigin = nil
                movePhase = .pointing
            }
        case .pointing where !held:
            // The wheel came up with the box locked: park, hands free.
            movePhase = .parked
            pushed = nil      // nothing is swallowed now; the pointer is polled
            Self.onAwaitingDestination?(true)
        case .pointing where !shifted:
            // ⇧ let go with the wheel still down: the box, back in the hand.
            if let source = moveSource {
                anchor = source.anchor
                freeOffset = CGVector(dx: source.free.x - mouse.x, dy: source.free.y - mouse.y)
            }
            moveSource = nil
            moveOrigin = nil
            movePhase = .none
        default:
            break
        }
        if movePhase == .pointing || movePhase == .parked {
            render(selection: nil, cursor: mouse, moving: false, source: moveSource?.box, pointing: true)
            return
        }

        if moving, moveOrigin?.centered != centered {
            moveOrigin = (mouse: mouse, anchor: anchor, free: grabbedCorner(for: mouse, centered: centered),
                          box: currentRect(for: mouse, centered: centered), centered: centered)
        } else if !moving {
            moveOrigin = nil
        }

        if let origin = moveOrigin {
            // ⌘ held: the box travels with the mouse instead of being resized —
            // and stops at the edges of its own screen rather than walking off.
            let raw = CGVector(dx: mouse.x - origin.mouse.x, dy: mouse.y - origin.mouse.y)
            let delta = CropGeometry.clampedTranslation(of: origin.box, by: raw, within: bounds)
            anchor = NSPoint(x: origin.anchor.x + delta.dx, y: origin.anchor.y + delta.dy)
            freeOffset = CGVector(dx: origin.free.x + delta.dx - mouse.x,
                                  dy: origin.free.y + delta.dy - mouse.y)
        }

        let rect = currentRect(for: mouse, centered: centered)
        render(selection: rect, cursor: mouse, moving: moving, centered: centered,
               source: moveSource?.box)

        guard !held else { return }

        // Button up: this is the crop — or the destination of a move. A
        // destination too small to be one (a click, not a drag) parks again:
        // the source stays locked and the arrow goes back to the pointer.
        let drawn = CropGeometry.rounded(rect)
        let big = { (r: NSRect) in r.width >= Self.minimumSide && r.height >= Self.minimumSide }
        guard let screen = startScreen else { finish(nil); return }
        if movePhase == .drawing, let source = moveSource.map({ CropGeometry.rounded($0.box) }) {
            if big(drawn) {
                finish(Selection(rect: source, screen: screen, movedTo: drawn))
            } else {
                movePhase = .parked
                pushed = nil
                Self.onAwaitingDestination?(true)
                render(selection: nil, cursor: mouse, moving: false, source: moveSource?.box, pointing: true)
            }
            return
        }
        guard big(drawn) else { finish(nil); return }
        finish(Selection(rect: drawn, screen: screen))
    }

    private func startDrag(at mouse: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { finish(nil); return }
        startScreen = screen
        anchor = CropGeometry.clamped(mouse, within: screen.frame)
        freeOffset = .zero
        moveOrigin = nil
        moveSource = nil
        movePhase = .none
        dragging = true
    }

    /// The destination's corner: the second press, with the source locked.
    private func startDestination(at point: NSPoint) {
        guard let bounds = startScreen?.frame else { return }
        movePhase = .drawing
        released = false
        anchor = CropGeometry.clamped(point, within: bounds)
        freeOffset = .zero
        moveOrigin = nil
        pushed = point
        Self.onAwaitingDestination?(false)
        tick()
    }

    /// The box as it stands this tick: corner-to-corner from the anchor, or —
    /// with ⌥ down — centred on the anchor with the mouse on a corner.
    private func currentRect(for mouse: NSPoint, centered: Bool) -> NSRect {
        let free = freeCorner(for: mouse)
        guard centered, let bounds = startScreen?.frame else {
            return CropGeometry.rect(from: anchor, to: free)
        }
        return CropGeometry.centeredRect(center: anchor, corner: free, within: bounds)
    }

    /// The corner a ⌘-move takes hold of: the one the *box* actually has, not
    /// the raw mouse corner. In centred mode an edge may already be holding the
    /// half-extent back, and carrying that unused reach into the move would let
    /// the box grow on its way across the screen instead of just travelling.
    private func grabbedCorner(for mouse: NSPoint, centered: Bool) -> NSPoint {
        let free = freeCorner(for: mouse)
        guard centered else { return free }
        let box = currentRect(for: mouse, centered: true)
        return NSPoint(x: free.x >= anchor.x ? box.maxX : box.minX,
                       y: free.y >= anchor.y ? box.maxY : box.minY)
    }

    /// The corner the mouse is dragging, held inside the starting screen.
    private func freeCorner(for mouse: NSPoint) -> NSPoint {
        let raw = NSPoint(x: mouse.x + freeOffset.dx, y: mouse.y + freeOffset.dy)
        guard let bounds = startScreen?.frame else { return raw }
        return CropGeometry.clamped(raw, within: bounds)
    }

    // MARK: - Drawing

    private func render(selection: NSRect?, cursor: NSPoint, moving: Bool, centered: Bool = false,
                        source: NSRect? = nil, pointing: Bool = false) {
        for entry in panels {
            let origin = entry.screen.frame.origin
            let toLocal = { (r: NSRect) in NSRect(x: r.minX - origin.x, y: r.minY - origin.y,
                                                  width: r.width, height: r.height) }
            entry.view.render(selection: selection.map(toLocal),
                              cursor: NSPoint(x: cursor.x - origin.x, y: cursor.y - origin.y),
                              size: selection.map { CGSize(width: $0.width.rounded(), height: $0.height.rounded()) },
                              moving: moving,
                              centered: centered,
                              source: source.map(toLocal),
                              pointing: pointing)
        }
    }
}

/// Borderless, and deliberately never key: the overlay is watched, not typed
/// into, and stealing the keyboard from the app behind it would outlive the
/// selection.
private final class CropPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit drags a window back onto a display and **below the menu bar**,
    /// which for a panel whose whole job is to cover one screen exactly means
    /// the top 25 points of it cannot be selected. The frame handed here is a
    /// screen's own, so it is already where it should be.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One screen's worth of overlay. Layers, not `draw(_:)`: the only thing that
/// changes 60 times a second is a path and a string, and repainting a retina
/// screen's worth of dimming to move a rectangle is how a crosshair starts to
/// feel heavy.
private final class CropOverlayView: NSView {
    private let dim = CAShapeLayer()
    private let border = CAShapeLayer()
    /// The ⇧-locked source box, dashed, and the arrow from its centre to the
    /// destination's.
    private let sourceBorder = CAShapeLayer()
    private let arrow = CAShapeLayer()
    private let vGuide = CALayer()
    private let hGuide = CALayer()
    private let sizeLabel: PillLabel
    private let hint: PillLabel
    /// Before the drag: the distance from the pointer to each screen edge, in
    /// pixels, on the middle of the guide that reaches it (left, right, bottom,
    /// top), and a filled arrowhead where each guide meets its edge.
    private let edgeLabels: [PillLabel]
    private let edgeArrows = CAShapeLayer()
    /// While dragging: the width in pixels above the top side, the height to
    /// the left of the left side — outside the box, so what is being framed
    /// stays clean.
    private let widthLabel: PillLabel
    private let heightLabel: PillLabel
    private let scale: CGFloat

    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private static let hintFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let style: CropSelectionStyle

    init(frame: NSRect, scale: CGFloat, style: CropSelectionStyle) {
        self.style = style
        self.scale = scale
        sizeLabel = PillLabel(font: Self.labelFont, scale: scale)
        hint = PillLabel(font: Self.hintFont, scale: scale)
        edgeLabels = (0..<4).map { _ in PillLabel(font: Self.labelFont, scale: scale) }
        widthLabel = PillLabel(font: Self.labelFont, scale: scale)
        heightLabel = PillLabel(font: Self.labelFont, scale: scale)
        super.init(frame: frame)
        wantsLayer = true
        guard let root = layer else { return }
        root.backgroundColor = NSColor.clear.cgColor

        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.32).cgColor
        root.addSublayer(dim)

        border.fillColor = nil
        border.strokeColor = style.accent.cgColor
        border.lineWidth = 2
        root.addSublayer(border)

        sourceBorder.fillColor = nil
        sourceBorder.strokeColor = style.accent.cgColor
        sourceBorder.lineWidth = 2
        sourceBorder.lineDashPattern = [6, 4]
        sourceBorder.isHidden = true
        root.addSublayer(sourceBorder)

        arrow.fillColor = style.accent.cgColor
        arrow.strokeColor = style.accent.cgColor
        arrow.lineWidth = 3
        arrow.lineCap = .round
        arrow.lineJoin = .round
        arrow.shadowColor = NSColor.black.cgColor
        arrow.shadowOpacity = 0.6
        arrow.shadowRadius = 2
        arrow.shadowOffset = .zero
        arrow.isHidden = true
        root.addSublayer(arrow)

        for guide in [vGuide, hGuide] {
            guide.backgroundColor = style.accent.withAlphaComponent(0.55).cgColor
            root.addSublayer(guide)
        }

        edgeArrows.fillColor = style.accent.cgColor
        edgeArrows.strokeColor = nil
        root.addSublayer(edgeArrows)
        edgeLabels.forEach { root.addSublayer($0.layer) }
        root.addSublayer(widthLabel.layer)
        root.addSublayer(heightLabel.layer)

        root.addSublayer(sizeLabel.layer)
        root.addSublayer(hint.layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The panel accepts clicks purely so the app underneath never sees the
    /// drag; the selection itself is read from session input state.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    func render(selection: NSRect?, cursor: NSPoint, size: CGSize?, moving: Bool, centered: Bool,
                source: NSRect? = nil, pointing: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Even-odd: two boxes that overlap would cancel each other's hole, so
        // the source is only cut out of the dimming when the two are apart.
        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection { path.addRect(selection) }
        if let source, !(selection?.intersects(source) ?? false) { path.addRect(source) }
        dim.path = path

        if let source {
            sourceBorder.isHidden = false
            sourceBorder.path = CGPath(rect: source.insetBy(dx: -1, dy: -1), transform: nil)
            // The arrow's tip: the destination's centre once there is one, the
            // pointer while it is still being aimed.
            if let tip = selection.map({ CGPoint(x: $0.midX, y: $0.midY) }) ?? (pointing ? cursor : nil) {
                arrow.isHidden = false
                arrow.path = Self.arrowPath(from: CGPoint(x: source.midX, y: source.midY), to: tip)
            } else {
                arrow.isHidden = true
            }
        } else {
            sourceBorder.isHidden = true
            arrow.isHidden = true
        }

        if let selection, let size {
            border.isHidden = false
            border.path = CGPath(rect: selection.insetBy(dx: -1, dy: -1), transform: nil)
            border.lineWidth = moving ? 3 : 2
            vGuide.isHidden = true
            hGuide.isHidden = true
            hint.layer.isHidden = true
            edgeArrows.isHidden = true
            edgeLabels.forEach { $0.layer.isHidden = true }
            renderSideDimensions(of: selection)
            place(sizeLabel,
                  text: readout(moving: moving, centered: centered, movingTo: source != nil),
                  near: selection)
        } else {
            border.isHidden = true
            widthLabel.layer.isHidden = true
            heightLabel.layer.isHidden = true
            // Before the drag there is no box to look at, so the crosshair is
            // the whole screen's width and height crossing under the pointer —
            // ours, drawn, because the arrow belongs to whatever app is in front.
            vGuide.isHidden = false
            hGuide.isHidden = false
            vGuide.frame = CGRect(x: cursor.x.rounded(), y: 0, width: 1, height: bounds.height)
            hGuide.frame = CGRect(x: 0, y: cursor.y.rounded(), width: bounds.width, height: 1)
            renderEdgeDistances(cursor: cursor)
            sizeLabel.layer.isHidden = true
            // The hold is the one gesture nothing on screen reveals; ⌘ and ⌥
            // are the others. Say them once, while there is still nothing else
            // to read.
            place(hint, text: NSAttributedString(
                    string: pointing ? style.moveHint : style.hint,
                    attributes: [.font: Self.hintFont, .foregroundColor: NSColor.white]),
                  near: nil, cursor: cursor)
        }
    }

    /// The four guides read as dimension lines: how far the pointer is from
    /// each edge, in physical pixels (a retina reads twice its points), on the
    /// middle of the guide, and an arrowhead where the guide meets the edge.
    private func renderEdgeDistances(cursor: NSPoint) {
        let x = cursor.x.rounded(), y = cursor.y.rounded()
        let w = bounds.width, h = bounds.height
        // (distance in points, middle of the guide, arrow tip on the edge, arrow direction)
        let legs: [(CGFloat, CGPoint, CGPoint, CGVector)] = [
            (x,     CGPoint(x: x / 2, y: y),           CGPoint(x: 0, y: y + 0.5), CGVector(dx: -1, dy: 0)),
            (w - x, CGPoint(x: (x + w) / 2, y: y),     CGPoint(x: w, y: y + 0.5), CGVector(dx: 1, dy: 0)),
            (y,     CGPoint(x: x, y: y / 2),           CGPoint(x: x + 0.5, y: 0), CGVector(dx: 0, dy: -1)),
            (h - y, CGPoint(x: x, y: (y + h) / 2),     CGPoint(x: x + 0.5, y: h), CGVector(dx: 0, dy: 1)),
        ]
        let arrows = CGMutablePath()
        let head: CGFloat = 12, wing: CGFloat = 6
        for (i, (distance, middle, tip, dir)) in legs.enumerated() {
            let pill = edgeLabels[i]
            let size = pill.setText(NSAttributedString(
                string: "\(Int((distance * scale).rounded()))",
                attributes: [.font: Self.labelFont, .foregroundColor: NSColor.white]))
            pill.layer.frame = CGRect(x: min(max(middle.x - size.width / 2, 4), max(4, w - size.width - 4)),
                                      y: min(max(middle.y - size.height / 2, 4), max(4, h - size.height - 4)),
                                      width: size.width, height: size.height)
            guard distance > head else { continue }
            let base = CGPoint(x: tip.x - dir.dx * head, y: tip.y - dir.dy * head)
            arrows.move(to: tip)
            arrows.addLine(to: CGPoint(x: base.x - dir.dy * wing, y: base.y + dir.dx * wing))
            arrows.addLine(to: CGPoint(x: base.x + dir.dy * wing, y: base.y - dir.dx * wing))
            arrows.closeSubpath()
        }
        edgeArrows.isHidden = false
        edgeArrows.path = arrows
    }

    /// The box's size in physical pixels on its own sides, dimension-line
    /// style: the width centred **above the top side**, the height centred
    /// **left of the left side**. Each flips to the opposite side when the
    /// screen edge leaves no room, and never goes inside the box.
    private func renderSideDimensions(of box: NSRect) {
        let gap: CGFloat = 6
        let text = { (points: CGFloat) in NSAttributedString(
            string: "\(Int((points * self.scale).rounded()))",
            attributes: [.font: Self.labelFont, .foregroundColor: NSColor.white]) }

        let w = widthLabel.setText(text(box.width))
        var wy = box.maxY + gap
        if wy + w.height > bounds.height - 4 { wy = box.minY - gap - w.height }
        widthLabel.layer.frame = CGRect(x: min(max(box.midX - w.width / 2, 4), max(4, bounds.width - w.width - 4)),
                                        y: wy, width: w.width, height: w.height)

        let h = heightLabel.setText(text(box.height))
        var hx = box.minX - gap - h.width
        if hx < 4 { hx = box.maxX + gap }
        heightLabel.layer.frame = CGRect(x: hx,
                                         y: min(max(box.midY - h.height / 2, 4), max(4, bounds.height - h.height - 4)),
                                         width: h.width, height: h.height)
    }

    /// `⌘ move   ⌥ centre` under the box — the keys, each lit only while it
    /// is being held. The numbers moved onto the box's own sides.
    private func readout(moving: Bool, centered: Bool, movingTo: Bool) -> NSAttributedString {
        let font = Self.labelFont
        let out = NSMutableAttributedString()
        func legend(_ text: String, _ lit: Bool) {
            out.append(NSAttributedString(
                string: (out.length == 0 ? "" : "   ") + text,
                attributes: [.font: font,
                             // Dim rather than hidden: it is a legend the rest of
                             // the time, and a word that appears only once you are
                             // already doing the thing teaches nobody.
                             .foregroundColor: lit ? style.accent : NSColor(white: 1, alpha: 0.45)]))
        }
        legend(style.movingSuffix, moving)
        legend(style.centeredSuffix, centered)
        if style.allowsMove { legend(style.moveToSuffix, movingTo) }
        return out
    }

    /// A shaft and a filled head, the head's tip on `to`. Nothing when the two
    /// centres coincide — there is no direction to point in.
    private static func arrowPath(from: CGPoint, to: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 4 else { return path }
        let ux = dx / length, uy = dy / length
        let head = min(18, length * 0.4), wing = head * 0.55
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        path.move(to: from)
        path.addLine(to: base)
        path.move(to: to)
        path.addLine(to: CGPoint(x: base.x - uy * wing, y: base.y + ux * wing))
        path.addLine(to: CGPoint(x: base.x + uy * wing, y: base.y - ux * wing))
        path.closeSubpath()
        return path
    }

    /// The readout sits just under the selection, flipping above it when the box
    /// is against the bottom of the screen — never inside it, where it would be
    /// captured.
    private func place(_ pill: PillLabel, text: NSAttributedString, near rect: NSRect?, cursor: NSPoint = .zero) {
        let size = pill.setText(text)
        var x: CGFloat
        var y: CGFloat
        if let rect {
            x = rect.midX - size.width / 2
            y = rect.minY - size.height - 6
            if y < 4 { y = min(rect.maxY + 6, bounds.height - size.height - 4) }
        } else {
            x = cursor.x + 16
            y = cursor.y - size.height - 16
            if y < 4 { y = cursor.y + 16 }
        }
        pill.layer.frame = CGRect(x: min(max(x, 4), max(4, bounds.width - size.width - 4)),
                                  y: min(max(y, 4), max(4, bounds.height - size.height - 4)),
                                  width: size.width, height: size.height)
    }
}

/// A rounded dark pill with one line of text vertically centred in it.
/// `CATextLayer` draws from the top of its own box, so the text gets a layer of
/// its own inside the background rather than a frame fudged to look centred.
private final class PillLabel {
    let layer = CALayer()
    private let text = CATextLayer()
    private let font: NSFont
    private static let padding = CGSize(width: 9, height: 5)

    init(font: NSFont, scale: CGFloat) {
        self.font = font
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer.cornerRadius = 5
        layer.isHidden = true
        text.contentsScale = scale
        text.font = font
        text.fontSize = font.pointSize
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.isWrapped = false
        text.truncationMode = .none
        layer.addSublayer(text)
    }

    /// Sets the string and answers the pill size the caller has to place.
    ///
    /// **Attributed, since the readout carries two words in two colours.** A
    /// `CATextLayer` takes one happily; what it will not do is let a
    /// `foregroundColor` set on the layer win against the runs, which is the
    /// same trap `RelayWindow.applySelectionText` is written under in Walkie
    /// Talkie — so the colour lives in the string and nowhere else.
    @discardableResult
    func setText(_ string: NSAttributedString) -> CGSize {
        layer.isHidden = false
        text.string = string
        let measured = string.size()
        let size = CGSize(width: measured.width + Self.padding.width * 2,
                          height: measured.height + Self.padding.height * 2)
        text.frame = CGRect(x: 0, y: Self.padding.height,
                            width: size.width, height: measured.height)
        return size
    }
}
