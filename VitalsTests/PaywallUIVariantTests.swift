import XCTest

final class PaywallUIVariantTests: XCTestCase {
    /// The dashboard drives this key, so anything it can send has to land on a
    /// layout that exists. Absent, empty, wrong key, wrong value: all catalog.
    func testAnythingUnrecognisedFallsBackToCatalog() {
        XCTAssertEqual(PaywallUIVariant.from(metadata: nil), .catalog)
        XCTAssertEqual(PaywallUIVariant.from(metadata: [:]), .catalog)
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["other": "x"]), .catalog)
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["upgrade_tab": "hosted"]), .catalog)
        // A variant added for a build that is not live yet, and the old value
        // this release retired: neither may blank the screen.
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["upgrade_tab": "some_future_layout"]), .catalog)
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["upgrade_tab": "timeline"]), .catalog)
        // Wrong type for the value, not just a wrong string.
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["upgrade_tab": 7]), .catalog)
    }

    func testKnownKeys() {
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["upgrade_tab": "catalog"]), .catalog)
        XCTAssertEqual(PaywallUIVariant.from(metadata: ["upgrade_tab": "feature_led"]), .featureLed)
    }

    /// The raw values are a dashboard contract: renaming one silently retires a
    /// live experiment arm.
    func testRawValuesMatchTheDashboardContract() {
        XCTAssertEqual(PaywallUIVariant.catalog.rawValue, "catalog")
        XCTAssertEqual(PaywallUIVariant.featureLed.rawValue, "feature_led")
        XCTAssertEqual(PaywallUIVariant.metadataKey, "upgrade_tab")
    }

    func testDebugLaunchOverrideIsOffByDefault() {
        XCTAssertNil(DebugLaunchConfig.upgradeTabOverride)
        XCTAssertFalse(DebugLaunchConfig.seedHealth)
        XCTAssertFalse(DebugLaunchConfig.forceSetupComplete)
    }
}

final class SupportMailTests: XCTestCase {
    private let snapshot = SupportMail.Snapshot(
        appVersion: "1.8.2",
        build: "171",
        systemVersion: "26.0",
        deviceModel: "iPhone17,1",
        localeIdentifier: "en_US",
        timeZone: "America/Los_Angeles",
        isPro: false,
        appUserID: "app_user_abc",
        healthAuthorized: true
    )

    func testSubjectsStayDistinct() {
        XCTAssertEqual(SupportMail.Kind.getHelp.subject, "Total Calories: Get Help")
        XCTAssertEqual(SupportMail.Kind.featureRequest.subject, "Total Calories: Feature Request")
    }

    func testGetHelpBodyCarriesDiagnosticsAndNoNewSecrets() {
        let block = SupportMail.diagnosticsBlock(snapshot)
        XCTAssertTrue(block.contains("1.8.2 (171)"))
        XCTAssertTrue(block.contains("iPhone17,1"))
        XCTAssertTrue(block.contains("RC user: app_user_abc"))
        XCTAssertTrue(block.contains("Health: authorized"))
        XCTAssertTrue(block.contains("Vitals+: off"))
        XCTAssertFalse(block.lowercased().contains("token"))
        XCTAssertFalse(block.lowercased().contains("appl_"))
    }

    func testFeatureRequestBodyIsAOneLiner() {
        let body = SupportMail.body(kind: .featureRequest, snapshot: snapshot)
        XCTAssertTrue(body.contains("Total Calories 1.8.2 (171)"))
        XCTAssertFalse(body.contains("RC user"))
        XCTAssertFalse(body.contains("Health:"))
    }

    func testMailtoURLsEncodeSubject() {
        let help = SupportMail.url(kind: .getHelp, snapshot: snapshot)
        let idea = SupportMail.url(kind: .featureRequest, snapshot: snapshot)
        XCTAssertEqual(help?.scheme, "mailto")
        XCTAssertTrue(help?.absoluteString.contains("Get%20Help") == true)
        XCTAssertTrue(idea?.absoluteString.contains("Feature%20Request") == true)
        XCTAssertNotEqual(help, idea)
    }
}
