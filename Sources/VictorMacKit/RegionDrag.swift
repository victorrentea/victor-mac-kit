import CoreGraphics

/// **The hand's half of a dragged region** — anchor, free corner, ⌘ moving the
/// box, ⌃ holding it square, all of it kept on the screen it started on.
///
/// Extracted from `CropSelectionOverlay` on 2026-10-04 when the 🔦 glass
/// spotlight in Victor Addons (⇧ + wheel-drag) needed the same gesture. Victor:
/// *"copiază-ți controalele din modul în care tai crop … behavior-ul efectiv
/// trebuie tot același"*. Two overlays, one set of keys, one implementation —
/// the drawing is each overlay's own business, this is not.
///
/// A value, fed one tick at a time: `readModifiers`, then `follow`, then
/// `rect(for:)`. Kept in that order because the ⌘ move remembers the box *as
/// it was squared* the moment ⌘ went down. Coordinates are whatever the caller
/// speaks, as long as `bounds` speaks it too (both overlays: global Cocoa).
public struct RegionDrag {
    /// The screen the drag started on; both corners are held inside it.
    public let bounds: CGRect
    /// The corner that stays put while the mouse drags the other one.
    public private(set) var anchor: CGPoint
    /// Free corner = mouse + this. Zero until an edge refuses to let the box
    /// follow the cursor; then it carries exactly how far behind it fell.
    public private(set) var freeOffset: CGVector = .zero
    /// ⌘ is held: the box travels with the mouse instead of being resized.
    public private(set) var moving = false
    /// ⌃ is held (and armed): the box is a square — `CropGeometry.squareCorner`.
    public private(set) var squaring = false
    /// ⌃ counts only once it has been seen *up* since the gesture opened, for a
    /// caller whose own trigger holds ⌃ (Victor Addons' ⌃P crop). Pass `true`
    /// when the trigger has nothing to do with ⌃.
    private var controlArmed: Bool
    /// Set on the ⌘ press, cleared on the release: where the mouse and the box
    /// were when the move began, so the translation is always measured from
    /// there rather than accumulated tick by tick.
    private var moveOrigin: (mouse: CGPoint, anchor: CGPoint, free: CGPoint, box: CGRect)?

    public init(anchor: CGPoint, within bounds: CGRect, controlArmed: Bool = false) {
        self.bounds = bounds
        self.anchor = CropGeometry.clamped(anchor, within: bounds)
        self.controlArmed = controlArmed
    }

    /// The modifiers as they stand this tick.
    public mutating func readModifiers(command: Bool, control: Bool) {
        moving = command
        if !control { controlArmed = true }
        squaring = controlArmed && control
    }

    /// Apply this tick's ⌘ move, if there is one.
    public mutating func follow(_ mouse: CGPoint) {
        if moving, moveOrigin == nil {
            moveOrigin = (mouse: mouse, anchor: anchor, free: freeCorner(for: mouse), box: rect(for: mouse))
        } else if !moving {
            moveOrigin = nil
        }
        guard let origin = moveOrigin else { return }
        // The box stops at the edges of its own screen rather than walking off,
        // and comes straight back when the mouse pulls away again.
        let raw = CGVector(dx: mouse.x - origin.mouse.x, dy: mouse.y - origin.mouse.y)
        let delta = CropGeometry.clampedTranslation(of: origin.box, by: raw, within: bounds)
        anchor = CGPoint(x: origin.anchor.x + delta.dx, y: origin.anchor.y + delta.dy)
        freeOffset = CGVector(dx: origin.free.x + delta.dx - mouse.x,
                              dy: origin.free.y + delta.dy - mouse.y)
    }

    /// The three steps of a tick in one call, for a caller with nothing to do
    /// between them.
    public mutating func update(mouse: CGPoint, command: Bool, control: Bool) -> CGRect {
        readModifiers(command: command, control: control)
        follow(mouse)
        return rect(for: mouse)
    }

    /// The box as it stands: corner-to-corner from the anchor.
    public func rect(for mouse: CGPoint) -> CGRect {
        CropGeometry.rect(from: anchor, to: freeCorner(for: mouse))
    }

    /// The corner the mouse is dragging, held inside `bounds` — and, while ⌃
    /// is held, onto the square's diagonal from the anchor.
    public func freeCorner(for mouse: CGPoint) -> CGPoint {
        let raw = CGPoint(x: mouse.x + freeOffset.dx, y: mouse.y + freeOffset.dy)
        let corner = CropGeometry.clamped(raw, within: bounds)
        return squaring ? CropGeometry.squareCorner(from: anchor, toward: corner, within: bounds) : corner
    }

    /// Forget a ⌘ move in progress; the next ⌘ tick starts a fresh one.
    public mutating func dropMove() { moveOrigin = nil }

    /// Hand a box back to the mouse: `anchor` stays, `free` is where the mouse
    /// corner is — however far that is from the pointer right now.
    public mutating func regrip(anchor: CGPoint, free: CGPoint, mouse: CGPoint) {
        self.anchor = anchor
        freeOffset = CGVector(dx: free.x - mouse.x, dy: free.y - mouse.y)
        moveOrigin = nil
    }

    /// A new box from `point`, on the same screen, keeping what the modifiers
    /// have already learnt (⌃ armed).
    public mutating func restart(at point: CGPoint) {
        anchor = CropGeometry.clamped(point, within: bounds)
        freeOffset = .zero
        moveOrigin = nil
    }
}
