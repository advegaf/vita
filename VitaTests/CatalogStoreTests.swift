import XCTest
import SwiftData
@testable import Vita

@MainActor
final class CatalogStoreTests: XCTestCase {

    /// Retains the container for the lifetime of the test (a temporary container
    /// deallocates and leaves its context dangling).
    private var container: ModelContainer!
    private var ctx: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = VitaContainer.make(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
    }

    /// CloudKit-legality gate: an illegal @Model graph (missing inverse, etc.) throws here.
    func testContainerBuilds() {
        XCTAssertNotNil(container)
    }

    func testSeedLoadsCatalogAndGoals() throws {
        CatalogStore.bootstrap(ctx)
        let compounds = try ctx.fetch(FetchDescriptor<CatalogCompound>())
        XCTAssertGreaterThan(compounds.count, 40, "expected the full catalog to seed")
        XCTAssertTrue(compounds.contains { $0.slug == "bpc-157" })
        XCTAssertTrue(compounds.contains { $0.slug == "semaglutide" })

        let goals = try ctx.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(goals.count, GoalKind.allCases.count)
    }

    func testSeedIsIdempotent() throws {
        CatalogStore.bootstrap(ctx)
        let first = try ctx.fetch(FetchDescriptor<CatalogCompound>()).count
        CatalogStore.bootstrap(ctx)
        let second = try ctx.fetch(FetchDescriptor<CatalogCompound>()).count
        XCTAssertEqual(first, second, "re-seeding must not duplicate compounds")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<UserProfile>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AppSettings>()).count, 1)
    }

    func testAddDedupes() throws {
        CatalogStore.bootstrap(ctx)
        let svc = StackService(context: ctx)
        let bpc = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<CatalogCompound>()).first { $0.slug == "bpc-157" }
        )
        XCTAssertNotNil(svc.commit(svc.draft(for: bpc)))
        XCTAssertNil(svc.commit(svc.draft(for: bpc)), "adding the same compound twice must be a no-op")
        XCTAssertEqual(svc.items().count, 1)
        XCTAssertTrue(svc.isInStack("bpc-157"))
    }

    func testRxOverrideAppliesAndToleratesOrphans() throws {
        CatalogStore.bootstrap(ctx)
        let settings = CatalogStore.fetchOrCreateSettings(ctx)
        settings.customRxOverrides = ["bpc-157=rx", "does-not-exist=rx"]
        CatalogStore.applyRxOverrides(ctx, settings: settings)
        let bpc = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<CatalogCompound>()).first { $0.slug == "bpc-157" }
        )
        XCTAssertEqual(bpc.rxStatusRaw, "rx")
    }

    func testAddSeedsDoseAndSchedule() throws {
        CatalogStore.bootstrap(ctx)
        let svc = StackService(context: ctx)
        let sema = try XCTUnwrap(
            try ctx.fetch(FetchDescriptor<CatalogCompound>()).first { $0.slug == "semaglutide" }
        )
        let item = try XCTUnwrap(svc.commit(svc.draft(for: sema)))
        XCTAssertEqual(item.doseUnitRaw, "mg")
        XCTAssertGreaterThan(item.doseAmount, 0)        // midpoint of the seed range
        XCTAssertNotNil(item.schedule)
        XCTAssertEqual(item.kindRaw, "scheduled")
    }
}
