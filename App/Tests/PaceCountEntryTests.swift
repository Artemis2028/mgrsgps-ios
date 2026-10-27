import XCTest
@testable import MGRSGPS

final class PaceCountEntryTests: XCTestCase {
    func testAndroidEditingRangeDigitsAndIncompleteInput() {
        for invalid in ["","0","2","29","201","999"] { XCTAssertNil(PaceCountEntry.accepted(invalid)) }
        for valid in [30,65,100,200] { XCTAssertEqual(PaceCountEntry.accepted(String(valid)),valid) }
        XCTAssertEqual(PaceCountEntry.digits("a2b0c0d9"),"200")
        XCTAssertEqual(PaceCountEntry.digits("١٠٠"),"100")
        XCTAssertEqual(PaceCountEntry.digits("1000"),"100")
        XCTAssertEqual(PaceCountEntry.digits("abc"),"")
    }
}
