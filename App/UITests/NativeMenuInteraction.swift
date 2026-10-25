import XCTest

extension XCTestCase {
    /// Native menu nodes can expose legacy Button / modern PopUpButton types
    /// with invalid activation points. Use the validated visible frame rather
    /// than element-relative coordinates or scroll-to-visible, then let each
    /// workflow assert the selected action's result.
    func tapNativeMenuItem(_ element: XCUIElement,file: StaticString = #filePath,line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8),file: file,line: line)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            let frame = element.frame, screen = XCUIApplication().frame
            return frame.minX.isFinite && frame.minY.isFinite && frame.width > 0 && frame.height > 0 && screen.contains(CGPoint(x: frame.midX,y: frame.midY))
        },object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [visible],timeout: 5),.completed,file: file,line: line)
        let app = XCUIApplication(), frame = element.frame, origin = app.frame.origin
        app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: frame.midX-origin.x,dy: frame.midY-origin.y)).tap()
    }
}
