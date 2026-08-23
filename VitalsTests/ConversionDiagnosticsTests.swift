import XCTest

/// The funnel record that answers "where did this customer convert, and how many
/// pitches did it take". Every assertion here is a claim that will be read off a
/// RevenueCat customer record later, so wrong values are worse than no values.
final class ConversionDiagnosticsTests: XCTestCase {

    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        // A throwaway suite per test: these counters live in the App Group and
        // would otherwise carry between tests and into the real container.
        let name = "conv.tests.\(UUID().uuidString)"
        suite = UserDefaults(suiteName: name)!
        ConversionDiagnostics.defaultsOverride = suite
    }

    override func tearDown() {
        ConversionDiagnostics.defaultsOverride = nil
        suite = nil
        super.tearDown()
    }

    func testImpressionIDsAreReducedToSurfaces() {
        XCTAssertEqual(
            ConversionDiagnostics.surface(fromImpressionID: "vitals_trial_offer_settings"),
            "trial_offer_settings"
        )
        // An id from somewhere that didn't follow the convention is kept whole
        // rather than mangled.
        XCTAssertEqual(ConversionDiagnostics.surface(fromImpressionID: "custom_id"), "custom_id")
    }

    func testCountsPitchesPerSurfaceAndInTotal() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_launch")
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_settings")
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_settings")

        XCTAssertEqual(ConversionDiagnostics.totalPitchViews, 3)
        XCTAssertEqual(ConversionDiagnostics.viewsBySurface["trial_offer_settings"], 2)
        XCTAssertEqual(ConversionDiagnostics.viewsBySurface["trial_offer_launch"], 1)
        XCTAssertEqual(ConversionDiagnostics.lastSurface, "trial_offer_settings")
        // The "total" bookkeeping key must not masquerade as a surface.
        XCTAssertNil(ConversionDiagnostics.viewsBySurface["total"])
    }

    func testConversionFreezesTheSurfaceAndCountAtTheMomentOfSale() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_launch")
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_settings")
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true)

        // Views after the sale must not rewrite how they converted.
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_sheet")

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_surface"], "trial_offer_settings")
        XCTAssertEqual(attributes["pitch_views_at_convert"], "2")
        XCTAssertEqual(attributes["converted_plan"], "yearly")
        XCTAssertEqual(attributes["converted_with_trial"], "true")
        XCTAssertEqual(attributes["pitch_views_total"], "3")
    }

    /// A renewal or a plan change is not a new answer to "what sold this person".
    func testOnlyTheFirstConversionIsRecorded() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_onboarding_trial")
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true)
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_settings")
        ConversionDiagnostics.recordConversion(plan: "lifetime", startedTrial: false)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_surface"], "onboarding_trial")
        XCTAssertEqual(attributes["converted_plan"], "yearly")
    }

    func testNoAttributesBeforeAnyPitchIsSeen() {
        XCTAssertTrue(ConversionDiagnostics.subscriberAttributes.isEmpty)
    }

    /// RevenueCat rejects attribute keys over 40 characters, and a surface name
    /// is not under our control once an impression id gets long.
    func testAttributeKeysStayInsideRevenueCatsLimit() {
        ConversionDiagnostics.recordPitchView(
            impressionID: "vitals_" + String(repeating: "a", count: 80)
        )
        for key in ConversionDiagnostics.subscriberAttributes.keys {
            XCTAssertLessThanOrEqual(key.count, 40, "attribute key too long: \(key)")
        }
    }

    /// Which arm produced the sale has to be frozen alongside it. RevenueCat
    /// reports the offering a customer was *assigned*; this records the layout
    /// the binary actually drew, and those differ whenever a build predates the
    /// arm and falls back to catalog.
    func testConversionRecordsTheVariantAndOfferingThatProducedIt() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_upgrade_tab")
        ConversionDiagnostics.recordConversion(
            plan: "yearly",
            startedTrial: true,
            variant: "feature_led",
            offeringID: "upgrade_feature_led"
        )

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_variant"], "feature_led")
        XCTAssertEqual(attributes["converted_offering"], "upgrade_feature_led")
    }

    /// The arm is optional so every existing call site keeps compiling and
    /// keeps recording. A conversion with no arm must not invent one.
    func testConversionWithoutAVariantReportsNoVariant() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_sheet")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertNil(attributes["converted_variant"])
        XCTAssertNil(attributes["converted_offering"])
        XCTAssertEqual(attributes["converted_plan"], "monthly")
    }

    /// Only the first conversion is ever written, and that rule has to hold for
    /// the arm too: a plan change months later must not relabel the sale as
    /// having come from whatever offering is current then.
    func testASecondConversionDoesNotRewriteTheVariant() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_upgrade_tab")
        ConversionDiagnostics.recordConversion(
            plan: "yearly", startedTrial: true, variant: "catalog", offeringID: "default"
        )
        ConversionDiagnostics.recordConversion(
            plan: "lifetime", startedTrial: false, variant: "feature_led", offeringID: "other"
        )

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_variant"], "catalog")
        XCTAssertEqual(attributes["converted_offering"], "default")
    }

    /// `converted_on` was a surface name under a key that reads as a date, so a
    /// customer record answered "when did they convert" with "settings". The
    /// surface keeps its own name now and the timestamp is a real one.
    func testConversionRecordsWhenItHappenedAndNotJustWhere() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_upgrade_tab")
        ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true)

        let attributes = ConversionDiagnostics.subscriberAttributes
        XCTAssertEqual(attributes["converted_surface"], "upgrade_tab")
        XCTAssertNil(attributes["converted_on"], "the misleading key is gone, not aliased")

        let stamp = try? XCTUnwrap(attributes["converted_at"])
        let parsed = ISO8601DateFormatter().date(from: stamp ?? "")
        XCTAssertNotNil(parsed, "converted_at is not an ISO 8601 date")
        XCTAssertEqual(parsed?.timeIntervalSinceNow ?? -999, 0, accuracy: 60)
    }

    func testDaysToConvertIsZeroOnTheSameDay() {
        ConversionDiagnostics.recordPitchView(impressionID: "vitals_trial_offer_launch")
        ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)
        XCTAssertEqual(ConversionDiagnostics.subscriberAttributes["days_to_convert"], "0")
        XCTAssertEqual(ConversionDiagnostics.subscriberAttributes["converted_with_trial"], "false")
    }
}
