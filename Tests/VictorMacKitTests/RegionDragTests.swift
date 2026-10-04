import XCTest
@testable import VictorMacKit

final class RegionDragTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testPlainDragIsCornerToCorner() {
        var drag = RegionDrag(anchor: CGPoint(x: 100, y: 100), within: screen, controlArmed: true)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 300, y: 250), command: false, control: false),
                       CGRect(x: 100, y: 100, width: 200, height: 150))
    }

    func testTheFreeCornerStaysOnTheStartingScreen() {
        var drag = RegionDrag(anchor: CGPoint(x: 1600, y: 100), within: screen, controlArmed: true)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 2400, y: 50), command: false, control: false),
                       CGRect(x: 1600, y: 50, width: 128, height: 50),
                       "the mouse walked onto the next display; the box did not")
    }

    // MARK: - ⌘ move

    func testCommandMovesTheBoxInsteadOfResizingIt() {
        var drag = RegionDrag(anchor: CGPoint(x: 100, y: 100), within: screen, controlArmed: true)
        _ = drag.update(mouse: CGPoint(x: 300, y: 300), command: false, control: false)
        _ = drag.update(mouse: CGPoint(x: 300, y: 300), command: true, control: false)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 350, y: 320), command: true, control: false),
                       CGRect(x: 150, y: 120, width: 200, height: 200))
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 400, y: 320), command: false, control: false),
                       CGRect(x: 150, y: 120, width: 250, height: 200),
                       "⌘ let go: the moved box is resized from where it was left")
    }

    func testCommandMoveStopsAtTheEdgeAndComesStraightBack() {
        var drag = RegionDrag(anchor: CGPoint(x: 100, y: 100), within: screen, controlArmed: true)
        _ = drag.update(mouse: CGPoint(x: 300, y: 300), command: true, control: false)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: -500, y: 300), command: true, control: false).minX, 0)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 310, y: 300), command: true, control: false),
                       CGRect(x: 110, y: 100, width: 200, height: 200),
                       "no overshoot is remembered from the push into the edge")
    }

    // MARK: - ⌃ square

    func testControlHoldsTheBoxSquare() {
        var drag = RegionDrag(anchor: CGPoint(x: 400, y: 400), within: screen, controlArmed: true)
        let box = drag.update(mouse: CGPoint(x: 600, y: 450), command: false, control: true)
        XCTAssertEqual(box, CGRect(x: 400, y: 400, width: 200, height: 200))
        XCTAssertTrue(drag.squaring)
    }

    func testControlHeldFromTheTriggerDoesNotSquareUntilLetGo() {
        // ⌃P: the crosshair opens with ⌃ still down.
        var drag = RegionDrag(anchor: CGPoint(x: 400, y: 400), within: screen, controlArmed: false)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 600, y: 450), command: false, control: true).height, 50)
        XCTAssertFalse(drag.squaring)
        _ = drag.update(mouse: CGPoint(x: 600, y: 450), command: false, control: false)
        XCTAssertEqual(drag.update(mouse: CGPoint(x: 600, y: 450), command: false, control: true).height, 200,
                       "seen up once, ⌃ means square from then on")
    }

    // MARK: - Handing a box back

    func testRegripKeepsTheShapeWhereverTheMouseIs() {
        var drag = RegionDrag(anchor: CGPoint(x: 100, y: 100), within: screen, controlArmed: true)
        drag.regrip(anchor: CGPoint(x: 100, y: 100), free: CGPoint(x: 300, y: 200), mouse: CGPoint(x: 900, y: 900))
        XCTAssertEqual(drag.rect(for: CGPoint(x: 900, y: 900)), CGRect(x: 100, y: 100, width: 200, height: 100))
    }

    func testRestartDrawsANewBoxOnTheSameScreen() {
        var drag = RegionDrag(anchor: CGPoint(x: 100, y: 100), within: screen, controlArmed: true)
        _ = drag.update(mouse: CGPoint(x: 300, y: 300), command: false, control: false)
        drag.restart(at: CGPoint(x: 1000, y: 500))
        XCTAssertEqual(drag.rect(for: CGPoint(x: 1100, y: 600)), CGRect(x: 1000, y: 500, width: 100, height: 100))
    }
}
