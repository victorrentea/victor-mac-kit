import XCTest
import AppKit
@testable import VictorMacKit

/// **Esc ends a crop only when it is the user's** (2026-11-03): an Esc the
/// caller stamped as its own passes the tap and leaves the box where it is.
final class CropEscapeTests: XCTestCase {
    private let stamp: Int64 = 0x7774_4241_434B_0000
    private let esc: CGKeyCode = 53

    override func tearDown() {
        CropSelectionOverlay.ownEventStamp = nil
        super.tearDown()
    }

    private func press(stamped: Bool) throws -> CGEvent {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        if stamped { source.userData = stamp }
        return try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: esc, keyDown: true))
    }

    func testTheCallersOwnEscIsRecognised() throws {
        CropSelectionOverlay.ownEventStamp = stamp
        XCTAssertTrue(CropSelectionOverlay.isCallersOwn(try press(stamped: true)))
    }

    func testHisEscIsNot() throws {
        CropSelectionOverlay.ownEventStamp = stamp
        XCTAssertFalse(CropSelectionOverlay.isCallersOwn(try press(stamped: false)))
    }

    func testACallerWithNoStampOwnsNothing() throws {
        XCTAssertFalse(CropSelectionOverlay.isCallersOwn(try press(stamped: false)))
        XCTAssertFalse(CropSelectionOverlay.isCallersOwn(try press(stamped: true)))
    }

    /// The whole path: a real overlay, the tap's handler, the two presses.
    func testOnlyHisEscEndsARunningCrop() throws {
        CropSelectionOverlay.ownEventStamp = stamp
        var ended: [CropSelectionOverlay.Selection?] = []
        CropSelectionOverlay.begin(button: .middle, from: NSPoint(x: 400, y: 400),
                                   style: CropSelectionStyle(allowsMove: true)) { ended.append($0) }
        addTeardownBlock { CropSelectionOverlay.cancelForTesting() }

        let own = try press(stamped: true)
        XCTAssertNotNil(CropSelectionOverlay.handleEscapeTap(type: .keyDown, event: own), "passed on")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(ended.isEmpty, "the crop survives the caller's own ⌃Escape")

        let his = try press(stamped: false)
        XCTAssertNil(CropSelectionOverlay.handleEscapeTap(type: .keyDown, event: his), "eaten")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(ended.count, 1)
        XCTAssertNil(ended.first ?? nil, "his Esc cancels, with nothing filed")
    }
}
