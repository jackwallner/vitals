import XCTest

final class DeepLinkTests: XCTestCase {
    func testEveryLinkRoundTripsThroughItsURL() {
        let links: [DeepLink] = [.today, .weeklyRecap] + DeepLink.Metric.allCases.map { .metric($0) }
        for link in links {
            XCTAssertEqual(DeepLink(url: link.url), link, link.url.absoluteString)
        }
    }

    func testMetricURLShape() {
        XCTAssertEqual(DeepLink.metric(.steps).url.absoluteString, "totalcalories://metric/steps")
    }

    func testRejectsForeignSchemesAndUnknownRoutes() {
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/metric/steps")!))
        XCTAssertNil(DeepLink(url: URL(string: "totalcalories://metric/sleep")!))
        XCTAssertNil(DeepLink(url: URL(string: "totalcalories://settings")!))
    }
}
