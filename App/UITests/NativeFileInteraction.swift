import XCTest

extension XCTestCase {
    /// A saved export is not necessarily indexed in Recents. Hosted iOS 26.5
    /// starts the backup picker there with an empty list; browse the local
    /// provider used by these native save/reopen fixtures instead.
    func openSavedNativeFile(_ name: String,in app: XCUIApplication,file: StaticString = #filePath,line: UInt = #line) {
        let match = NSPredicate(format: "label CONTAINS %@",name)
        var item = app.cells.containing(match).firstMatch
        let browse = app.tabBars["DOC.browsingModeTabBar"].buttons["Browse"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10),app.debugDescription,file: file,line: line)
        browse.tap()
        let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        // Browse can reopen the provider directly. A virtualized filename is
        // not evidence that we are still on the provider-selection screen.
        if !item.waitForExistence(timeout: 3) && !navigation.staticTexts["On My iPhone"].exists {
            let local = app.cells.containing(.staticText,identifier: "On My iPhone").firstMatch
            XCTAssertTrue(local.waitForExistence(timeout: 8),app.debugDescription,file: file,line: line)
            local.tap()
        }
        var files = app.collectionViews["File View"].firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 8),app.debugDescription,file: file,line: line)
        if !item.exists {
            // Repeated native export tests retain older documents. Ask the
            // local provider for this exact fresh filename instead of assuming
            // it lies within a fixed number of alphabetically sorted pages.
            let search = navigation.searchFields["Search"]
            XCTAssertTrue(search.waitForExistence(timeout: 8),app.debugDescription,file: file,line: line)
            search.tap(); search.typeText(name+"\n")
            XCTAssertTrue(item.waitForExistence(timeout: 15),app.debugDescription,file: file,line: line)
            // Files keeps its underlying folder collection in the AX tree
            // while presenting a second File View for search results.
            files = app.collectionViews.matching(identifier: "File View").allElementsBoundByIndex.last(where: { $0.isHittable }) ?? files
            item = files.cells.containing(match).firstMatch
        }
        let tabs = app.tabBars["DOC.browsingModeTabBar"]
        func unobscured() -> Bool {
            guard item.exists && item.isHittable else { return false }
            let top = navigation.exists ? navigation.frame.maxY : files.frame.minY
            let bottom = tabs.exists ? tabs.frame.minY : files.frame.maxY
            let iconY = item.frame.minY+item.frame.height*0.25
            return iconY > top+8 && iconY < bottom-8
        }
        func scroll(down: Bool) {
            let top = navigation.exists ? navigation.frame.maxY : files.frame.minY
            let bottom = tabs.exists ? tabs.frame.minY : files.frame.maxY
            let height = bottom-top, origin = files.frame.origin
            // Files may expose an infinite application-window origin while
            // its collection view and controls retain valid UIKit frames.
            let start = files.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: files.frame.width/2,dy: top+height*(down ? 0.25 : 0.75)-origin.y))
            let end = files.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: files.frame.width/2,dy: top+height*(down ? 0.75 : 0.25)-origin.y))
            // A fast swipe leaves the target moving after XCTest's idle wait.
            // Drag only in the unobscured viewport, then hold before releasing.
            start.press(forDuration: 0.1,thenDragTo: end,withVelocity: .slow,thenHoldForDuration: 0.3)
        }
        // File cells are virtualized; saved documents beyond the first page
        // may not enter the accessibility tree until the browser scrolls.
        for _ in 0..<16 {
            if unobscured() { break }
            let top = navigation.exists ? navigation.frame.maxY : files.frame.minY
            scroll(down: item.exists && item.frame.minY+item.frame.height*0.25 < top+8)
        }
        XCTAssertTrue(item.exists,app.debugDescription,file: file,line: line)
        XCTAssertTrue(unobscured(),app.debugDescription,file: file,line: line)
        // In icon view the cell centre is the filename's upper edge. Hosted
        // Files can leave that text tap unhandled. Open the visible thumbnail,
        // using the collection view's valid space if the app AX origin is invalid.
        for attempt in 0..<3 {
            if attempt == 0 {
                let point = CGPoint(x: item.frame.midX,y: item.frame.minY+item.frame.height*0.25)
                files.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: point.x-files.frame.minX,dy: point.y-files.frame.minY)).tap()
            } else {
                // The hosted collection can retain a valid frame yet ignore
                // coordinate activation. Re-resolve this exact cell and use
                // UIKit's native hit point while the same picker remains.
                item.tap()
            }
            // Files can ignore the first thumbnail tap while finishing its
            // provider transition. Acknowledge dismissal before proceeding;
            // never tap again once the app's import review replaces Files.
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !files.exists },object: nil)
            if XCTWaiter.wait(for: [dismissed],timeout: 10) == .completed { return }
        }
        XCTAssertFalse(files.exists,"The selected file did not leave the native picker",file: file,line: line)
    }

    func saveNativeFile(in app: XCUIApplication,file: StaticString = #filePath,line: UInt = #line) {
        let picker = app.otherElements["Browse View (Picker)"]
        let filename = app.textFields["DOCPicker.filenameTextField"]
        for _ in 0..<3 {
            let identified = app.buttons["DOCPicker.actionButton"]
            let save = identified.exists ? identified : picker.buttons["Save"]
            XCTAssertTrue(save.waitForExistence(timeout: 8),app.debugDescription,file: file,line: line)
            save.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in !picker.exists && !filename.exists },object: nil)
            if XCTWaiter.wait(for: [dismissed],timeout: 10) == .completed { return }
            // Retry only while this same native save presentation remains;
            // never press an underlying app Save or start another export.
            guard picker.exists || filename.exists else { return }
        }
        XCTFail("Native save did not acknowledge dismissal",file: file,line: line)
    }
}
