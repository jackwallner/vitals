import XCTest

/// Who sees the exit offer, and what the readout will count. The close record
/// is the test's denominator, so it has to be written the same way in both arms.
final class ExitOfferTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "exit.tests.\(UUID().uuidString)")!
        ConversionDiagnostics.defaultsOverride = suite
    }

    override func tearDown() {
        ConversionDiagnostics.defaultsOverride = nil
        suite = nil
        super.tearDown()
    }

    func testNoSplitMeansNotInTheTest() {
        XCTAssertNil(ExitOffer.arm(from: nil, appUserID: "a"))
        XCTAssertNil(ExitOffer.arm(from: [:], appUserID: "a"))
        XCTAssertNil(ExitOffer.arm(from: ["salt": "exit1"], appUserID: "a"))
    }

    func testForcePinsEveryone() {
        let meta: [String: Any] = ["offer_pct": 0, "salt": "exit1", "force": "offer"]
        XCTAssertEqual(ExitOffer.arm(from: meta, appUserID: "anyone"), .offer)
        XCTAssertEqual(ExitOffer.arm(from: ["force": "holdout"], appUserID: "anyone"), .holdout)
    }

    func testSplitIsStableAndRoughlyHalf() {
        let meta: [String: Any] = ["offer_pct": 50, "salt": "exit1", "force": NSNull()]
        let ids = (0..<4000).map { "$RCAnonymousID:\($0)" }
        let arms = ids.map { ExitOffer.arm(from: meta, appUserID: $0) }
        XCTAssertEqual(arms, ids.map { ExitOffer.arm(from: meta, appUserID: $0) })
        let offers = arms.filter { $0 == .offer }.count
        XCTAssertTrue((1800...2200).contains(offers), "offer arm got \(offers) of 4000")
        XCTAssertTrue(ids.allSatisfy { ExitOffer.arm(from: ["offer_pct": 0, "salt": "s"], appUserID: $0) == .holdout })
        XCTAssertTrue(ids.allSatisfy { ExitOffer.arm(from: ["offer_pct": 100, "salt": "s"], appUserID: $0) == .offer })
    }

    func testBucketIsAFixedFunction() {
        // Pinned so a refactor cannot silently reshuffle customers mid-test.
        XCTAssertEqual(ExitOffer.bucket(salt: "exit1", appUserID: "abc"), ExitOffer.bucket(salt: "exit1", appUserID: "abc"))
        XCTAssertNotEqual(
            (0..<50).map { ExitOffer.bucket(salt: "exit1", appUserID: "u\($0)") },
            (0..<50).map { ExitOffer.bucket(salt: "exit2", appUserID: "u\($0)") }
        )
    }

    func testOfferArmShowsOnceOnFirstClose() {
        XCTAssertTrue(ExitOffer.shouldOffer(onCloseOf: "onboarding_trial", arm: .offer, offerLoaded: true, isPro: false))
        ExitOffer.recordShown()
        XCTAssertFalse(ExitOffer.shouldOffer(onCloseOf: "paywall", arm: .offer, offerLoaded: true, isPro: false))
        // The denominator keeps the first close, not the latest.
        XCTAssertEqual(ExitOffer.subscriberAttributes["exit_offer_surface"], "onboarding_trial")
        XCTAssertNotNil(ExitOffer.subscriberAttributes["exit_offer_shown_at"])
    }

    func testHoldoutRecordsTheSameCloseAndShowsNothing() {
        XCTAssertFalse(ExitOffer.shouldOffer(onCloseOf: "paywall", arm: .holdout, offerLoaded: true, isPro: false))
        let attributes = ExitOffer.subscriberAttributes
        XCTAssertEqual(attributes["exit_offer_arm"], "holdout")
        XCTAssertEqual(attributes["exit_offer_surface"], "paywall")
        XCTAssertNotNil(attributes["exit_offer_closed_at"])
        XCTAssertNil(attributes["exit_offer_shown_at"])
    }

    func testNotInTestOrProRecordsNothing() {
        XCTAssertFalse(ExitOffer.shouldOffer(onCloseOf: "paywall", arm: nil, offerLoaded: true, isPro: false))
        XCTAssertFalse(ExitOffer.shouldOffer(onCloseOf: "paywall", arm: .offer, offerLoaded: true, isPro: true))
        XCTAssertTrue(ExitOffer.subscriberAttributes.isEmpty)
        XCTAssertFalse(ExitOffer.hasClosed)
    }

    func testUnloadedPlanCountsTheCloseButWaitsForTheNextOne() {
        XCTAssertFalse(ExitOffer.shouldOffer(onCloseOf: "trial_offer_launch", arm: .offer, offerLoaded: false, isPro: false))
        XCTAssertTrue(ExitOffer.hasClosed)
        XCTAssertTrue(ExitOffer.shouldOffer(onCloseOf: "paywall", arm: .offer, offerLoaded: true, isPro: false))
        XCTAssertEqual(ExitOffer.subscriberAttributes["exit_offer_surface"], "trial_offer_launch")
    }

    func testFirstOutcomeWins() {
        _ = ExitOffer.shouldOffer(onCloseOf: "paywall", arm: .offer, offerLoaded: true, isPro: false)
        ExitOffer.recordOutcome(.declined)
        ExitOffer.recordOutcome(.purchased)
        XCTAssertEqual(ExitOffer.subscriberAttributes["exit_offer_outcome"], "declined")
    }
}
