import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turning a chosen rectangle into a file.
///
/// **It is taken as a whole-display shot and cropped here.** `screencapture -R`
/// is the obvious tool and does not work: on macOS 15.7 it answers *"could not
/// create image from display with rect"* for every rectangle, on every display,
/// with and without `-D`. Cropping ourselves costs one extra decode and buys
/// something back — the region is cut at the display's **real** pixel scale,
/// read off the capture itself rather than trusted from `backingScaleFactor`,
/// which mirrored displays and HiDPI modes both make a guess.
public enum CropCapture {

    /// Capture `selection` and write it as a JPEG at `url`.
    ///
    /// Safe to call from any thread: it shells out and decodes, and touches no
    /// AppKit state beyond reading the screen's frame off the selection.
    @discardableResult
    public static func capture(_ selection: CropSelectionOverlay.Selection,
                               to url: URL,
                               quality: CGFloat = 0.85) -> Bool {
        let display = displayNumber(for: selection.screen)
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("victor-crop-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temp) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", "-D", String(display), temp.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard let source = CGImageSourceCreateWithURL(temp as CFURL, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }

        let crop = CropGeometry.pixelCrop(of: selection.rect,
                                          onScreen: selection.screen.frame,
                                          imageWidth: CGFloat(full.width))
        guard let cropped = full.cropping(to: crop) else { return false }

        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let jpg = rep.representation(using: .jpeg,
                                           properties: [.compressionFactor: quality]) else { return false }
        return (try? jpg.write(to: url)) != nil
    }

    /// The 1-indexed display number `screencapture -D` expects for `screen`.
    ///
    /// **Off the active list, not the online one.** Online includes displays
    /// that are asleep or mirrored, so with a sleeping external monitor the
    /// index overshoots and `screencapture` rejects it outright — no file, and
    /// nothing on screen saying why.
    public static func displayNumber(for screen: NSScreen) -> Int {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return 1 }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }
        guard let index = displays.firstIndex(of: displayID), index < Int(count) else { return 1 }
        return index + 1
    }
}
