import XCTest

final class TodaySnapshotResolverTests: XCTestCase {
    private typealias Stats = TodaySnapshotResolver.Stats
    private let live = Stats(active: 400, resting: 1_200, steps: 6_000)
    private let cached = Stats(active: 300, resting: 1_100, steps: 5_000)
    private let zero = Stats(active: 0, resting: 0, steps: 0)

    func testLiveWinsWhenItHasNumbers() {
        XCTAssertEqual(TodaySnapshotResolver.resolve(live: live, cached: cached, protectedDataAvailable: true), live)
    }

    func testLockedReadFallsBackToCache() {
        XCTAssertEqual(TodaySnapshotResolver.resolve(live: zero, cached: cached, protectedDataAvailable: false), cached)
    }

    func testLockedWithNoCacheHasNoAnswer() {
        XCTAssertNil(TodaySnapshotResolver.resolve(live: zero, cached: nil, protectedDataAvailable: false))
        XCTAssertNil(TodaySnapshotResolver.resolve(live: nil, cached: nil, protectedDataAvailable: false))
    }

    func testUnlockedEmptyDayIsAnHonestZero() {
        XCTAssertEqual(TodaySnapshotResolver.resolve(live: zero, cached: nil, protectedDataAvailable: true), zero)
    }
}
