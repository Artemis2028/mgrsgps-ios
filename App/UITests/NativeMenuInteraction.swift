import XCTest

extension XCTestCase {
    /// Native menu nodes can expose legacy Button / modern PopUpButton types
    /// with invalid activation points. Use the validated visible frame rather
    /// than element-relative coordinates or scroll-to-visible, then let each
    /// workflow assert the selected action's result.
    func tapNativeMenuItem(_ element: XCUIElement,file: StaticString = #filePath,line: UInt = #line) {
        tapVisibleControl(element,horizontal: 0.5,file: file,line: line)
    }
    func tapNativeSwitch(_ element: XCUIElement,file: StaticString = #filePath,line: UInt = #line) {
        // SwiftUI exposes both a label-wide switch and its actual UISwitch.
        let leaf = element.descendants(matching: .switch).allElementsBoundByIndex.last ?? element
        tapVisibleControl(leaf,horizontal: 0.5,file: file,line: line)
    }
    /// A hosted UIKit gesture can finish without changing a visible switch.
    /// Re-read the value before another action, so an acknowledged change is
    /// never toggled back. The alternate action uses UIKit's native hit point.
    func setNativeSwitch(_ element: XCUIElement,to enabled: Bool,file: StaticString = #filePath,line: UInt = #line) {
        let expected = enabled ? "1" : "0"
        for attempt in 0..<3 {
            if element.value as? String == expected { return }
            if attempt == 0 { tapNativeSwitch(element,file: file,line: line) }
            else {
                let leaf = element.descendants(matching: .switch).allElementsBoundByIndex.last ?? element
                XCTAssertTrue(leaf.isHittable,element.debugDescription,file: file,line: line)
                leaf.tap()
            }
            let applied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@",expected),object: element)
            if XCTWaiter.wait(for: [applied],timeout: 5) == .completed { return }
        }
        XCTFail("Native switch did not acknowledge value \(expected): \(element.debugDescription)",file: file,line: line)
    }
    /// Older runtimes report a scrolled row as hittable beneath the navigation
    /// bar; tapping its stale centre can activate Done instead of the switch.
    func revealSettingsControl(_ element: XCUIElement,in app: XCUIApplication,file: StaticString = #filePath,line: UInt = #line) {
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY+12, bottom = app.frame.maxY-60
            let scroll = app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app.scrollViews.firstMatch
            let origin = app.frame.origin
            let middle = (top+bottom)/2
            var movement = -(bottom-top)*0.45
            if element.exists {
                let frame = element.frame
                if frame.height > 0 && frame.minY >= top && frame.maxY <= bottom && element.isHittable { return }
                movement = min((bottom-top)*0.45,max(-(bottom-top)*0.45,middle-frame.midY))
            }
            // A full swipe can overshoot this short status row in both
            // directions indefinitely. Move toward the viewport centre with
            // a bounded drag and hold, so release does not add momentum.
            let x = max(app.frame.minX+20,scroll.frame.minX+20)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: x-origin.x,dy: middle-origin.y))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: x-origin.x,dy: middle+movement-origin.y))
            start.press(forDuration: 0.1,thenDragTo: end,withVelocity: .slow,thenHoldForDuration: 0.3)
        }
        XCTFail("Settings control never entered the visible content: \(element.debugDescription)",file: file,line: line)
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
        for id in ["waypoint-keyboard-done","field-fix-keyboard-done","tak-enroll-keyboard-done"] {
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
            guard frame.minX.isFinite && frame.minY.isFinite && frame.width > 0 && frame.height > 0 else { return false }
            // Hosted Files can expose a valid UIKit control beneath an app
            // window whose AX frame is {inf,inf,0,0}. Its native hit test is
            // still usable; never subtract that invalid application origin.
            if !screen.minX.isFinite || !screen.minY.isFinite || screen.isEmpty { return element.isHittable }
            return screen.contains(CGPoint(x: frame.minX+frame.width*horizontal,y: frame.midY))
        },object: element)
        guard XCTWaiter.wait(for: [visible],timeout: 5) == .completed else {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "control-frame-failure"; shot.lifetime = .keepAlways; add(shot)
            XCTFail("Control has no usable visible frame: \(element.debugDescription)\nApplication frame: \(XCUIApplication().frame)",file: file,line: line)
            return
        }
        let app = XCUIApplication(), frame = element.frame, origin = app.frame.origin
        if !origin.x.isFinite || !origin.y.isFinite || app.frame.isEmpty {
            element.coordinate(withNormalizedOffset: .init(dx: horizontal,dy: 0.5)).tap()
            return
        }
        app.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: frame.minX+frame.width*horizontal-origin.x,dy: frame.midY-origin.y)).tap()
    }
}
