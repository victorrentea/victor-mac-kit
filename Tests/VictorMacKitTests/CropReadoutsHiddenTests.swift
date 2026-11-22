import XCTest
import AppKit
@testable import VictorMacKit

/// **`CropSelectionStyle.readoutsHidden`** (2026-11-22, Walkie Talkie's teaser): no
/// legend pill, no size badges, no hint beside the pointer, no distances on the
/// crosshair — the box, the source, the arrow and the crosshair's lines stay. Off by
/// default. `CROP_PNG=<dir>` writes the pictures for a look.
final class CropReadoutsHiddenTests: XCTestCase {
    private let size = NSSize(width: 500, height: 360)
    private let box = NSRect(x: 180, y: 120, width: 160, height: 110)
    private let source = NSRect(x: 30, y: 230, width: 100, height: 80)

    func testEveryReadoutIsShownUnlessAsked() {
        XCTAssertFalse(CropSelectionStyle().readoutsHidden)
    }

    /// A box being drawn: the legend under it and the two size badges are dark pills.
    func testABoxWearsNoPills() throws {
        XCTAssertGreaterThan(try pills(hidden: false, selection: box, name: "readouts-box-shown.png"), 800)
        XCTAssertEqual(try pills(hidden: true, selection: box, name: "readouts-box-hidden.png"), 0)
    }

    /// Before the drag: four distances on the crosshair; hidden, its lines are still drawn.
    func testTheCrosshairKeepsItsLinesAndLosesItsNumbers() throws {
        XCTAssertGreaterThan(try pills(hidden: false, selection: nil, name: "readouts-crosshair-shown.png"), 800)
        XCTAssertEqual(try pills(hidden: true, selection: nil, name: "readouts-crosshair-hidden.png"), 0)
        var style = CropSelectionStyle()
        style.readoutsHidden = true
        let rep = try shot(style, selection: nil, source: nil, name: nil)
        // On the vertical guide, well away from the pointer: the accent over the dimming.
        let c = try XCTUnwrap(rep.colorAt(x: 300, y: 20)?.usingColorSpace(.deviceRGB))
        let beside = try XCTUnwrap(rep.colorAt(x: 320, y: 20)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(c.redComponent - c.blueComponent, beside.redComponent - beside.blueComponent + 0.1, "the guide is still yellow")
    }

    /// A move, the destination not yet drawn: `click to drop it here …` beside the pointer.
    func testAMoveSaysNothingBesideThePointer() throws {
        let shown = try pills(hidden: false, selection: nil, source: source, name: "readouts-move-shown.png")
        let hidden = try pills(hidden: true, selection: nil, source: source, name: "readouts-move-hidden.png")
        XCTAssertGreaterThan(shown, 2000)
        // The arrow's shadow may leave a few dark pixels; a pill is thousands.
        XCTAssertLessThan(hidden, 150)
    }

    /// How many pixels are as dark as a pill (black at 72 % over the dimmed page).
    private func pills(hidden: Bool, selection: NSRect?, source: NSRect? = nil, name: String) throws -> Int {
        var style = CropSelectionStyle(allowsMove: true, moveSourceColor: .systemRed,
                                       moveDestinationColor: .systemGreen, moveArrowColor: .white)
        style.readoutsHidden = hidden
        let rep = try shot(style, selection: selection, source: source, name: name)
        var dark = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if max(c.redComponent, c.greenComponent, c.blueComponent) < 0.3 { dark += 1 }
        } }
        return dark
    }

    private func shot(_ style: CropSelectionStyle, selection: NSRect?, source: NSRect?, name: String?) throws -> NSBitmapImageRep {
        let image = try XCTUnwrap(CropSelectionOverlay.snapshot(size: size, style: style, selection: selection,
                                                                source: source, cursor: NSPoint(x: 300, y: 150)))
        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        if let name, let dir = ProcessInfo.processInfo.environment["CROP_PNG"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        return rep
    }
}
