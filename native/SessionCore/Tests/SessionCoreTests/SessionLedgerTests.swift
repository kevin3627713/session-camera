import XCTest
@testable import SessionCore

final class SessionLedgerTests: XCTestCase {
    func testOnlyCurrentSessionIsAdmitted() {
        var ledger = SessionLedger()
        let current = ledger.issueTicket()
        XCTAssertTrue(ledger.admit(current))
        XCTAssertTrue(ledger.contains(current))
        XCTAssertFalse(ledger.admit(CaptureTicket(sessionID: UUID())))
    }

    func testLatePhotoAndVideoCallbacksCannotLeakAcrossSessionReset() {
        var ledger = SessionLedger()
        let photoInFlight = ledger.issueTicket()
        let videoInFlight = ledger.issueTicket()
        ledger.reset()
        XCTAssertFalse(ledger.admit(photoInFlight))
        XCTAssertFalse(ledger.admit(videoInFlight))
        XCTAssertTrue(ledger.admit(ledger.issueTicket()))
    }

    func testStaleEditorCannotRestorePreviousSessionPhoto() {
        var ledger = SessionLedger()
        let editing = ledger.issueTicket()
        XCTAssertTrue(ledger.admit(editing))
        ledger.reset()
        XCTAssertFalse(ledger.contains(editing))
        XCTAssertFalse(ledger.admit(editing))
    }

    func testDuplicateCaptureIsNotAddedTwice() {
        var ledger = SessionLedger()
        let capture = ledger.issueTicket()
        XCTAssertTrue(ledger.admit(capture))
        XCTAssertFalse(ledger.admit(capture))
    }

    func testRemovalCannotAffectAnotherSession() {
        var ledger = SessionLedger()
        let first = ledger.issueTicket()
        ledger.admit(first)
        ledger.reset()
        let second = ledger.issueTicket()
        ledger.admit(second)
        ledger.remove(first)
        XCTAssertTrue(ledger.contains(second))
        ledger.remove(second)
        XCTAssertFalse(ledger.contains(second))
    }

    func testRelaunchDoesNotRestorePreviousLedger() {
        var previous = SessionLedger()
        let capture = previous.issueTicket()
        previous.admit(capture)
        let relaunched = SessionLedger()
        XCTAssertNotEqual(previous.sessionID, relaunched.sessionID)
        XCTAssertFalse(relaunched.contains(capture))
    }

    func testRepeatedResetsAlwaysInvalidateAllTickets() {
        var ledger = SessionLedger()
        for _ in 0..<100 {
            let capture = ledger.issueTicket()
            XCTAssertTrue(ledger.admit(capture))
            ledger.reset()
            XCTAssertFalse(ledger.contains(capture))
        }
    }
}
