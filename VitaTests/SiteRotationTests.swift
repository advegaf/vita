import XCTest
@testable import Vita

/// Pure rotation math (detached models — no container needed for reads).
final class SiteRotationTests: XCTestCase {

    private func item(slug: String = "bpc-157", route: String = "subcutaneous") -> ProtocolItem {
        let it = ProtocolItem()
        it.compoundSlug = slug
        it.routeRaw = route
        return it
    }

    private func log(_ slug: String, site: InjectionSite?, at: Date,
                     status: DoseStatus = .taken) -> DoseLog {
        let l = DoseLog()
        l.compoundSlug = slug
        l.siteRaw = site?.rawValue ?? ""
        l.statusRaw = status.rawValue
        l.loggedAt = at
        return l
    }

    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func testFirstSuggestionAndAdvance() {
        let it = item()
        XCTAssertEqual(SiteRotation.next(for: it, logs: []), .leftAbdomen)          // no history
        let logs = [log("bpc-157", site: .leftAbdomen, at: t(100))]
        XCTAssertEqual(SiteRotation.next(for: it, logs: logs), .rightAbdomen)       // advances
    }

    func testWrapsAtEndOfOrder() {
        let it = item()
        let logs = [log("bpc-157", site: .rightArm, at: t(100))]                    // last in order
        XCTAssertEqual(SiteRotation.next(for: it, logs: logs), .leftAbdomen)        // wraps
    }

    func testPerCompoundIndependence() {
        let a = item(slug: "bpc-157"), b = item(slug: "tb-500")
        let logs = [log("bpc-157", site: .leftThigh, at: t(100)),
                    log("tb-500", site: .rightGlute, at: t(200))]
        XCTAssertEqual(SiteRotation.next(for: a, logs: logs), .rightThigh)
        XCTAssertEqual(SiteRotation.next(for: b, logs: logs), .leftArm)
    }

    func testNonInjectableReturnsNil() {
        XCTAssertNil(SiteRotation.next(for: item(route: "oral"), logs: []))
        XCTAssertNil(SiteRotation.next(for: item(route: "nasal"), logs: []))
        XCTAssertNil(SiteRotation.next(for: item(route: ""), logs: []))             // unknown route
        XCTAssertNotNil(SiteRotation.next(for: item(route: "intramuscular"), logs: []))
    }

    func testLegacyAndSkippedLogsInvisible() {
        let it = item()
        let logs = [log("bpc-157", site: .leftGlute, at: t(100)),
                    log("bpc-157", site: nil, at: t(200)),                          // legacy, ignored
                    log("bpc-157", site: .rightArm, at: t(300), status: .skipped)]  // skipped, ignored
        XCTAssertEqual(SiteRotation.next(for: it, logs: logs), .rightGlute)         // follows t(100)
    }

    func testExcludingSkipsUpsertedRow() {
        let it = item()
        let own = log("bpc-157", site: .leftThigh, at: t(300))
        let older = log("bpc-157", site: .leftAbdomen, at: t(100))
        // Re-stamping `own` must rotate from the OLDER log, not from own's stale site.
        XCTAssertEqual(SiteRotation.next(for: it, logs: [own, older], excluding: own.id),
                       .rightAbdomen)
    }

    func testSiteRawRoundTrip() {
        let l = DoseLog()
        l.siteRaw = InjectionSite.rightThigh.rawValue
        XCTAssertEqual(l.site, .rightThigh)
        l.siteRaw = ""
        XCTAssertNil(l.site)
        l.siteRaw = "garbage"
        XCTAssertNil(l.site)
    }
}
