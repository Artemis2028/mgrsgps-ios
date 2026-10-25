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

    /// Use iOS's native selection menu instead of a hardware Command-A event.
    /// Hosted Xcode 26 can send that event without selecting the existing text.
    func replaceTextInput(_ element: XCUIElement,_ value: String,file: StaticString = #filePath,line: UInt = #line) {
        tapTextInput(element,file: file,line: line)
        let app = XCUIApplication()
        for _ in 0..<3 {
            let old = element.value as? String ?? ""
            if old.isEmpty { break }
            // Form accessibility frames include the label. Press the actual
            // trailing value, rather than the label-wide centre.
            element.coordinate(withNormalizedOffset: .init(dx: 0.999,dy: 0.5)).press(forDuration: 1.1)
            let selectAll = app.buttons["Select All"].firstMatch
            let menuItem = app.menuItems["Select All"].firstMatch
            if selectAll.waitForExistence(timeout: 1) { selectAll.tap() }
            else if menuItem.exists { menuItem.tap() }
            else {
                // A short numeric value may offer no selection menu. A press
                // at the label-wide centre can leave the caret before its last
                // digit. Tap the trailing value edge before deleting backwards.
                tapVisibleControl(element,horizontal: 0.999,file: file,line: line)
            }
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: max(1,old.utf16.count)))
            let remaining = element.value as? String ?? ""
            if remaining.isEmpty || remaining == element.placeholderValue { break }
        }
        let remaining = element.value as? String ?? ""
        XCTAssertTrue(remaining.isEmpty || remaining == element.placeholderValue,"Could not clear native input: \(remaining)",file: file,line: line)
        element.typeText(value)
        XCTAssertEqual(element.value as? String,value,file: file,line: line)
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
