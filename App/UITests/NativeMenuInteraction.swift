import XCTest

extension XCTestCase {
    /// Native menu nodes can expose legacy Button / modern PopUpButton types
    /// with invalid activation points. Use the validated visible frame rather
    /// than element-relative coordinates or scroll-to-visible, then let each
    /// workflow assert the selected action's result.
    func tapNativeMenuItem(_ element: XCUIElement,file: StaticString = #filePath,line: UInt = #line) {
        tapVisibleControl(element,horizontal: 0.5,file: file,line: line)
    }

    /// Right-aligned Form text fields can expose a label-wide activation
    /// point. Tap within the actual value side without using an edge pixel.
    func tapTextInput(_ element: XCUIElement,file: StaticString = #filePath,line: UInt = #line) {
        // A floating keyboard Done control can overlap the value-side of
        // another Form row. Dismiss it before resolving the next input frame.
        dismissFieldKeyboard(file: file,line: line)
        tapVisibleControl(element,horizontal: 0.9,file: file,line: line)
    }

    func dismissFieldKeyboard(file: StaticString = #filePath,line: UInt = #line) {
        let app = XCUIApplication()
        for id in ["waypoint-keyboard-done","field-fix-keyboard-done"] {
            let done = app.buttons[id]
            if done.exists && done.isHittable {
                tapNativeMenuItem(done,file: file,line: line)
                let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
                    !app.keyboards.firstMatch.exists || !app.keyboards.firstMatch.isHittable
                },object: app)
                XCTAssertEqual(XCTWaiter.wait(for: [hidden],timeout: 5),.completed,file: file,line: line)
                return
            }
        }
    }

    private func tapVisibleControl(_ element: XCUIElement,horizontal: CGFloat,file: StaticString,line: UInt) {
        XCTAssertTrue(element.waitForExistence(timeout: 8),file: file,line: line)
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            let frame = element.frame, screen = XCUIApplication().frame
            return frame.minX.isFinite && frame.minY.isFinite && frame.width > 0 && frame.height > 0 && screen.contains(CGPoint(x: frame.minX+frame.width*horizontal,y: frame.midY))
        },object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [visible],timeout: 5),.completed,file: file,line: line)
        let app = XCUIApplication(), frame = element.frame, origin = app.frame.origin
        app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: frame.minX+frame.width*horizontal-origin.x,dy: frame.midY-origin.y)).tap()
    }
}
