import XCTest
import AppKit
@testable import VictorMacKit

/// **The parked box rides the pointer at half opacity** (2026-10-19): the
/// source's pixels drawn over the screen where a left click would drop them,
/// the arrow aimed at the ghost's centre. `CROP_PNG=<dir>` writes the snapshot.
final class CropGhostTests: XCTestCase {
    private let size = NSSize(width: 400, height: 300)
    private let source = NSRect(x: 40, y: 180, width: 100, height: 80)
    private let ghost = NSRect(x: 240, y: 40, width: 100, height: 80)

    func testGhostIsHalfTransparentOverTheScreen() throws {
        let style = CropSelectionStyle(allowsMove: true, moveSourceColor: .systemRed,
                                       moveDestinationColor: .systemGreen, moveArrowColor: .white)
        let blue = try XCTUnwrap(Self.solid(.systemBlue, size: ghost.size))
        let image = try XCTUnwrap(CropSelectionOverlay.snapshot(
            size: size, style: style, selection: nil, source: source,
            cursor: NSPoint(x: ghost.maxX, y: ghost.minY), ghost: (ghost, blue)))
        let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        if let dir = ProcessInfo.processInfo.environment["CROP_PNG"],
           let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("move-ghost.png"))
        }
        // Inside the ghost, away from the arrow: blue, but washed by the page under it.
        let c = color(rep, x: ghost.minX + 10, yUp: ghost.maxY - 10)
        XCTAssertGreaterThan(c.blueComponent, c.redComponent + 0.15, "the ghost is drawn")
        XCTAssertGreaterThan(c.redComponent, 0.2, "and only half opaque")
        // Outside it, nothing blue.
        let out = color(rep, x: ghost.minX - 30, yUp: ghost.maxY - 10)
        XCTAssertLessThan(abs(out.blueComponent - out.redComponent), 0.1)
    }

    private static func solid(_ color: NSColor, size: NSSize) -> CGImage? {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.setFillColor((color.usingColorSpace(.deviceRGB) ?? color).cgColor)
        ctx?.fill(CGRect(origin: .zero, size: size))
        return ctx?.makeImage()
    }

    private func color(_ rep: NSBitmapImageRep, x: CGFloat, yUp: CGFloat) -> NSColor {
        let c = rep.colorAt(x: Int(x), y: rep.pixelsHigh - 1 - Int(yUp)) ?? .clear
        return c.usingColorSpace(.deviceRGB) ?? .clear
    }
}
