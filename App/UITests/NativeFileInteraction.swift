import XCTest

extension XCTestCase {
    /// A saved export is not necessarily indexed in Recents. Hosted iOS 26.5
    /// starts the backup picker there with an empty list; browse the local
    /// provider used by these native save/reopen fixtures instead.
    func openSavedNativeFile(_ name: String,in app: XCUIApplication,startingInIcons: Bool = false,file: StaticString = #filePath,line: UInt = #line) {
        let match = NSPredicate(format: "label CONTAINS %@",name)
        // Search suggestions can also contain the requested text. Match a
        // document's basename/extension prefix, not an ancestor or suggestion.
        let documentMatch = NSPredicate(format:"identifier == %@ OR identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",name,name+".",name+", ",name,name+".",name+", ")
        var item = app.cells.matching(documentMatch).firstMatch
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
        if startingInIcons && (files.value as? String)?.localizedCaseInsensitiveContains("Icon") != true {
            let more = navigation.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout:8),app.debugDescription,file:file,line:line); more.tap()
            let icons = app.buttons["Icons"]
            XCTAssertTrue(icons.waitForExistence(timeout:8),app.debugDescription,file:file,line:line); icons.tap()
            let settled = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
                (files.value as? String)?.localizedCaseInsensitiveContains("Icon") == true
            },object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:8),.completed,app.debugDescription,file:file,line:line)
        }
        // Use Files' native list layout for activation. Hosted icon cells can
        // expose valid thumbnail frames while ignoring coordinate/cell taps.
        if (files.value as? String)?.localizedCaseInsensitiveContains("Icon") == true {
            let more = navigation.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout:8),app.debugDescription,file:file,line:line)
            more.tap()
            let list = app.buttons["List"]
            XCTAssertTrue(list.waitForExistence(timeout:8),app.debugDescription,file:file,line:line)
            list.tap()
            let settled = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
                (files.value as? String)?.localizedCaseInsensitiveContains("List") == true
            },object:nil)
            XCTAssertEqual(XCTWaiter.wait(for:[settled],timeout:8),.completed,app.debugDescription,file:file,line:line)
            item = files.cells.matching(documentMatch).firstMatch
        }
        if !item.exists {
            // Repeated native export tests retain older documents. Ask the
            // local provider for this exact fresh filename instead of assuming
            // it lies within a fixed number of alphabetically sorted pages.
            let search = navigation.searchFields["Search"]
            XCTAssertTrue(search.waitForExistence(timeout: 8),app.debugDescription,file: file,line: line)
            search.tap(); search.typeText(name+"\n")
            // Files keeps its underlying folder collection in the AX tree
            // while presenting a second File View for search results.
            files = app.collectionViews.matching(identifier: "File View").allElementsBoundByIndex.last(where: { $0.isHittable }) ?? files
            item = files.cells.matching(documentMatch).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout:15),app.debugDescription,file:file,line:line)
        }
        let tabs = app.tabBars["DOC.browsingModeTabBar"]
        // List rows expose a filename and a separate preview/drag thumbnail.
        // Hosted112 left the document unopened after three thumbnail gestures;
        // activate its exact filename, keeping the thumbnail only as fallback.
        func target() -> XCUIElement {
            let filename = item.staticTexts.matching(match).firstMatch
            if filename.exists { return filename }
            let thumbnails = item.images.allElementsBoundByIndex.filter { !$0.frame.isEmpty && $0.frame.width.isFinite && $0.frame.height.isFinite }
            if let thumbnail = thumbnails.max(by: { $0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height }) { return thumbnail }
            return item
        }
        func unobscured() -> Bool {
            let visible = target()
            guard visible.exists && visible.isHittable else { return false }
            let top = navigation.exists ? navigation.frame.maxY : files.frame.minY
            let bottom = tabs.exists ? tabs.frame.minY : files.frame.maxY
            let iconY = target().frame.midY
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
            scroll(down: item.exists && target().frame.midY < top+8)
        }
        XCTAssertTrue(item.exists,app.debugDescription,file: file,line: line)
        XCTAssertTrue(unobscured(),app.debugDescription,file: file,line: line)
        // Activate the resolved document label in the collection view's valid
        // coordinate space, even when the app AX origin is invalid.
        for attempt in 0..<3 {
            if attempt == 0 {
                let point = CGPoint(x: target().frame.midX,y: target().frame.midY)
                files.coordinate(withNormalizedOffset: .zero).withOffset(.init(dx: point.x-files.frame.minX,dy: point.y-files.frame.minY)).tap()
            } else if attempt == 1 {
                // The hosted collection can retain a valid frame yet ignore
                // coordinate activation. Re-resolve this exact cell and use
                // UIKit's native hit point while the same picker remains.
                target().tap()
            } else {
                // If single activation leaves the same provider visible,
                // try its native double-tap opening gesture on that exact row.
                target().doubleTap()
            }
            // Files can ignore the first tap while finishing its
            // provider transition. Acknowledge dismissal before proceeding;
            // never tap again once the app's import review replaces Files.
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !files.exists },object: nil)
            if XCTWaiter.wait(for: [dismissed],timeout: 10) == .completed { return }
        }
        XCTAssertFalse(files.exists,"The selected file did not leave the native picker: " + app.debugDescription,file: file,line: line)
    }

    func chooseNativeExportLocation(in app: XCUIApplication,file: StaticString = #filePath,line: UInt = #line) {
        let name = app.textFields["export-filename"]
        XCTAssertTrue(name.waitForExistence(timeout: 30),app.debugDescription,file:file,line:line)
        let choose = app.buttons["export-choose-location"]
        XCTAssertTrue(choose.isEnabled,app.debugDescription,file:file,line:line); choose.tap()
        let picker = app.otherElements["Browse View (Picker)"]
        XCTAssertTrue(picker.waitForExistence(timeout:30),app.debugDescription,file:file,line:line)
    }

    func saveNativeFile(in app: XCUIApplication,file: StaticString = #filePath,line: UInt = #line) {
        if app.textFields["export-filename"].exists { chooseNativeExportLocation(in:app,file:file,line:line) }
        let picker = app.otherElements["Browse View (Picker)"]
        XCTAssertTrue(picker.waitForExistence(timeout:30),app.debugDescription,file:file,line:line)
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
