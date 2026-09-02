import XCTest

final class OnboardingPitchRoutingTests: XCTestCase {

    private func table(
        salt: String = "s1",
        enroll: Int = 100,
        force: String? = nil,
        logsFood: [String: Int]? = ["a": 25, "b": 25, "c": 25, "e": 25],
        noFoodLog: [String: Int]? = ["a": 34, "c": 33, "d": 33],
        fallback: String = "a"
    ) -> [String: Any] {
        var segments: [String: Any] = [:]
        if let logsFood { segments["logs_food"] = logsFood }
        if let noFoodLog { segments["no_food_log"] = noFoodLog }
        var body: [String: Any] = [
            "salt": salt,
            "enroll_pct": enroll,
            "segments": segments,
            "fallback": fallback
        ]
        if let force { body["force"] = force }
        return ["onboarding_pitch": body]
    }

    // MARK: - Parsing

    /// Nothing in the dashboard means nothing changes: a build that cannot read
    /// a table must behave exactly like the release before it.
    func testMissingOrJunkTableIsDisabled() {
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: nil), .disabled)
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: [:]), .disabled)
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: ["other": "x"]), .disabled)
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: ["onboarding_pitch": "a"]), .disabled)
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: ["onboarding_pitch": 7]), .disabled)
    }

    /// A `.disabled` table draws the shipping pitch, never a blank screen.
    func testDisabledResolvesToCurrent() {
        for logsFood in [true, false, nil] as [Bool?] {
            XCTAssertEqual(
                OnboardingPitchRouting.disabled.variant(forID: "u1", logsFood: logsFood),
                .current
            )
        }
    }

    /// An arm name this build does not contain must not blank the screen, which
    /// is what lets a table name an arm before its build clears review.
    func testUnknownArmNamesAreDropped() {
        let routing = OnboardingPitchRouting.from(metadata: table(
            logsFood: ["a": 50, "some_future_arm": 50],
            noFoodLog: ["a": 100]
        ))
        for i in 0..<80 {
            let arm = routing.variant(forID: "user\(i)", logsFood: true)
            XCTAssertEqual(arm, .current, "unknown arm names must not be drawn")
        }
    }

    /// Weights are relative and an arm is retired with 0, so a table that
    /// zeroes everything still has to land somewhere drawable.
    func testAllZeroWeightsFallBack() {
        let routing = OnboardingPitchRouting.from(metadata: table(
            logsFood: ["a": 0, "b": 0],
            noFoodLog: ["a": 0]
        ))
        XCTAssertEqual(routing.variant(forID: "u1", logsFood: true), .current)
        XCTAssertEqual(routing.variant(forID: "u1", logsFood: false), .current)
    }

    // MARK: - Segment safety

    /// The whole reason the split is done in the app: a food-dependent arm must
    /// never reach someone with no food data, however the dashboard is edited.
    func testFoodOnlyArmsNeverReachNonLoggers() {
        let routing = OnboardingPitchRouting.from(metadata: table(
            logsFood: ["b": 100],
            noFoodLog: ["b": 50, "e": 50]  // a misconfigured dashboard
        ))
        for i in 0..<200 {
            for logsFood in [false, nil] as [Bool?] {
                let arm = routing.variant(forID: "user\(i)", logsFood: logsFood)
                XCTAssertFalse(
                    [.macroFood, .twoWeeksFood].contains(arm),
                    "\(arm.rawValue) needs food data and must not be drawn"
                )
            }
        }
    }

    /// `nil` is "never asked", not "no". Both route away from the food arms,
    /// and both must resolve to something drawable.
    func testNeverAskedRoutesWithNonLoggers() {
        let routing = OnboardingPitchRouting.from(metadata: table())
        var seen: Set<OnboardingPitchVariant> = []
        for i in 0..<300 { seen.insert(routing.variant(forID: "u\(i)", logsFood: nil)) }
        XCTAssertTrue(seen.isSubset(of: [.current, .lockedNumbers, .twoWeeks]))
    }

    /// A force that the segment cannot draw falls back rather than blanking.
    func testForceRespectsWhatTheSegmentCanDraw() {
        let forced = OnboardingPitchRouting.from(metadata: table(force: "b"))
        XCTAssertEqual(forced.variant(forID: "u1", logsFood: true), .macroFood)
        XCTAssertEqual(forced.variant(forID: "u1", logsFood: false), .current)
    }

    /// Ship-the-winner: force beats the weights and the enrollment ramp.
    func testForceOverridesWeightsAndEnrollment() {
        let forced = OnboardingPitchRouting.from(metadata: table(enroll: 0, force: "c"))
        for i in 0..<50 {
            XCTAssertEqual(forced.variant(forID: "u\(i)", logsFood: false), .lockedNumbers)
        }
    }

    // MARK: - Enrollment ramp

    /// 0 must survive parsing as 0. Defaulting it to 100 would silently enroll
    /// everyone the moment someone paused the test from the dashboard.
    func testZeroEnrollmentPausesWithoutBlanking() {
        let routing = OnboardingPitchRouting.from(metadata: table(enroll: 0))
        XCTAssertEqual(routing.enrollPercent, 0)
        for i in 0..<50 {
            XCTAssertEqual(routing.variant(forID: "u\(i)", logsFood: true), .current)
        }
    }

    func testPartialEnrollmentLandsInRange() {
        let routing = OnboardingPitchRouting.from(metadata: table(enroll: 20))
        let ids = (0..<2000).map { "user\($0)" }
        let enrolled = ids.filter { routing.variant(forID: $0, logsFood: true) != .current }
        // Arm `a` is a quarter of the logger split, so some enrolled users draw
        // the control too. The floor is what matters: the ramp is not ignored.
        let share = Double(enrolled.count) / Double(ids.count)
        XCTAssertGreaterThan(share, 0.05, "a 20% ramp should still enroll people")
        XCTAssertLessThan(share, 0.30, "a 20% ramp must not behave like 100%")
    }

    // MARK: - Assignment behaviour

    /// The arm must not move if onboarding is restarted, and must not be
    /// reseeded per process the way Swift's own hashing would be.
    func testAssignmentIsStableForTheSameID() {
        let routing = OnboardingPitchRouting.from(metadata: table())
        for i in 0..<100 {
            let id = "user\(i)"
            let first = routing.variant(forID: id, logsFood: true)
            for _ in 0..<5 {
                XCTAssertEqual(routing.variant(forID: id, logsFood: true), first)
            }
        }
    }

    /// Changing the salt is the documented way to reshuffle everyone, so it has
    /// to actually move a meaningful share of the population.
    func testSaltReshuffles() {
        let a = OnboardingPitchRouting.from(metadata: table(salt: "1984a"))
        let b = OnboardingPitchRouting.from(metadata: table(salt: "1984b"))
        let ids = (0..<500).map { "user\($0)" }
        let moved = ids.filter { a.variant(forID: $0, logsFood: true) != b.variant(forID: $0, logsFood: true) }
        XCTAssertGreaterThan(moved.count, 100, "a new salt should reassign a real share")
    }

    /// Every arm in a segment's table should actually be reachable, and only
    /// the arms named for that segment.
    func testEachSegmentDrawsOnlyItsOwnArms() {
        let routing = OnboardingPitchRouting.from(metadata: table())
        let ids = (0..<1200).map { "user\($0)" }

        let loggerArms = Set(ids.map { routing.variant(forID: $0, logsFood: true) })
        XCTAssertEqual(loggerArms, [.current, .macroFood, .lockedNumbers, .twoWeeksFood])

        let nonLoggerArms = Set(ids.map { routing.variant(forID: $0, logsFood: false) })
        XCTAssertEqual(nonLoggerArms, [.current, .lockedNumbers, .twoWeeks])
    }

    /// Weights should be roughly honoured, or "give the promising arm more
    /// traffic" is not a real dashboard control.
    func testWeightsAreApproximatelyHonoured() {
        let routing = OnboardingPitchRouting.from(metadata: table(
            logsFood: ["a": 10, "b": 90],
            noFoodLog: ["a": 100]
        ))
        let ids = (0..<3000).map { "user\($0)" }
        let bShare = Double(ids.filter { routing.variant(forID: $0, logsFood: true) == .macroFood }.count)
            / Double(ids.count)
        XCTAssertGreaterThan(bShare, 0.80)
        XCTAssertLessThan(bShare, 0.97)
    }

    /// An out-of-range percentage is clamped rather than trusted.
    func testEnrollmentIsClamped() {
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: table(enroll: 480)).enrollPercent, 100)
        XCTAssertEqual(OnboardingPitchRouting.from(metadata: table(enroll: -20)).enrollPercent, 0)
    }
}
