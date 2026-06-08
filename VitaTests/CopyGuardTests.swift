import XCTest
@testable import Vita

/// Guards user-facing copy invariants.
final class CopyGuardTests: XCTestCase {

    /// No em dashes anywhere in the seeded catalog copy (the user banned them app-wide).
    @MainActor
    func testNoEmDashesInCatalog() throws {
        let seeds = try XCTUnwrap(CatalogStore.loadSeeds(), "catalog.json should load")
        for s in seeds {
            let fields: [String?] = [s.name, s.subcategory, s.rxRationale,
                                     s.mechanismBlurb, s.about, s.cycleGuidance, s.reconNote]
            for f in fields where f?.contains("—") == true {
                XCTFail("Em dash found in \(s.slug): \(f!)")
            }
        }
    }

    /// Every compound ships a descriptive About blurb for the add sheet.
    @MainActor
    func testEveryCompoundHasAbout() throws {
        let seeds = try XCTUnwrap(CatalogStore.loadSeeds())
        let missing = seeds.filter { ($0.about ?? "").isEmpty }.map(\.slug)
        XCTAssertTrue(missing.isEmpty, "Missing About text for: \(missing)")
    }
}
