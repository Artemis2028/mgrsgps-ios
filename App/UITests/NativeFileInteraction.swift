import XCTest

extension XCTestCase {
    func saveNativeFile(in app: XCUIApplication,file: StaticString = #filePath,line: UInt = #line) {
        let identified = app.buttons["DOCPicker.actionButton"]
        if identified.exists { identified.tap(); return }
        // iOS 26.5's local-provider Save has a label but no actionButton ID.
        // Scope it to Files so it cannot select the app's own Save toolbar.
        let picker = app.otherElements["Browse View (Picker)"]
        let save = picker.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8),app.debugDescription,file: file,line: line)
        save.tap()
    }
}
