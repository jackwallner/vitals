import XCTest

final class TrialNoteTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "TrialNoteTests")
        defaults.removePersistentDomain(forName: "TrialNoteTests")
    }

    func testMissingOrUnknownMetadataIsTheLiveControl() {
        XCTAssertEqual(TrialNote.from(metadata: nil), .none)
        XCTAssertEqual(TrialNote.from(metadata: ["trial_note": "loud"]), .none)
        XCTAssertEqual(TrialNote.from(metadata: ["trial_note": 1]), .none)
        XCTAssertEqual(TrialNote.from(metadata: ["trial_note": "indie"]), .indie)
        XCTAssertEqual(TrialNote.offeringArm, .none)
    }

    func testWhatToFixOnlyAfterTheNoteAndARenewalSwitchedOff() {
        XCTAssertFalse(TrialNote.whatToFixDue(inTrial: true, willRenew: false, defaults), "never saw the note")
        TrialNote.markSeen(defaults)
        XCTAssertFalse(TrialNote.whatToFixDue(inTrial: true, willRenew: true, defaults), "still renewing")
        XCTAssertFalse(TrialNote.whatToFixDue(inTrial: false, willRenew: false, defaults), "paid, not a trial")
        XCTAssertTrue(TrialNote.whatToFixDue(inTrial: true, willRenew: false, defaults))
        TrialNote.markAsked(defaults)
        XCTAssertFalse(TrialNote.whatToFixDue(inTrial: true, willRenew: false, defaults), "asked once")
    }
}
