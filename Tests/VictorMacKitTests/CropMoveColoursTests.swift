import XCTest
import AppKit
@testable import VictorMacKit

/// **The move in three colours** (2026-10-15): with `moveSourceColor` /
/// `moveDestinationColor` / `moveArrowColor` set, the locked source is ringed
/// in the first, the destination being drawn in the second; unset, both keep
/// the accent. `CROP_PNG=<dir>` writes the snapshot for a look.
final class CropMoveColoursTests: XCTestCase {
    private let size = NSSize(width: 400, height: 300)
    // Origin bottom-left, like the overlay's own coordinates.
    private let source = NSRect(x: 40, y: 180, width: 100, height: 80)
    private let destination = NSRect(x: 250, y: 40, width: 100, height: 80)

    func testSourceRedDestinationGreen() throws {
        let style = CropSelectionStyle(allowsMove: true, moveSourceColor: .systemRed,
                                       moveDestinationColor: .systemGreen, moveArrowColor: .white)
        let rep = try shot(style, name: "move-colours.png")
        // Just outside the source's top edge, and the destination's bottom edge.
        XCTAssertTrue(isRed(color(rep, x: 90, yUp: source.maxY + 1)), "source ring")
        XCTAssertTrue(isGreen(color(rep, x: 300, yUp: destination.minY - 1)), "destination ring")
    }

    func testUnsetKeepsTheAccent() throws {
        let rep = try shot(CropSelectionStyle(allowsMove: true), name: "move-accent.png")
        let c = color(rep, x: 300, yUp: destination.minY - 1)
        XCTAssertGreaterThan(c.redComponent, 0.8)
        XCTAssertGreaterThan(c.greenComponent, 0.6, "yellow, not red")
    }

    private func shot(_ style: CropSelectionStyle, name: String) throws -> NSBitmapImageRep {
        let image = try XCTUnwrap(CropSelectionOverlay.snapshot(size: size, style: style, selection: destination,
                                                                source: source, cursor: NSPoint(x: 300, y: 80)))
        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        if let dir = ProcessInfo.processInfo.environment["CROP_PNG"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        return rep
    }

    /// The bitmap's rows run from the top; the overlay's y runs up.
    private func color(_ rep: NSBitmapImageRep, x: CGFloat, yUp: CGFloat) -> NSColor {
        let c = rep.colorAt(x: Int(x), y: rep.pixelsHigh - 1 - Int(yUp)) ?? .clear
        return c.usingColorSpace(.deviceRGB) ?? .clear
    }
    private func isRed(_ c: NSColor) -> Bool { c.redComponent > 0.7 && c.greenComponent < 0.45 }
    private func isGreen(_ c: NSColor) -> Bool { c.greenComponent > 0.6 && c.redComponent < 0.5 }
}
