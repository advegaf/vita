import XCTest
import SwiftData
@testable import Vita

@MainActor
final class ShopTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    // MARK: Catalog + pricing

    func testCatalogLoadsAndIsLarge() {
        let products = ShopCatalog.load()
        XCTAssertGreaterThan(products.count, 90)        // ~100 SKUs after dropping HGH/bac/acid
        XCTAssertFalse(products.contains { $0.compound.lowercased().contains("hgh") })
        XCTAssertFalse(products.contains { $0.compound.lowercased().contains("bac water") })
    }

    func testMarkupConstant() {
        XCTAssertEqual(Shop.markup, 1.40, accuracy: 1e-9)
    }

    func testVialPriceIsKitTimesMarkupRounded() {
        let p = ShopProduct(code: "X", compound: "Test", categoryRaw: "other", strength: "5 mg",
                            vialsPerKit: 10, kitCostUSD: 40, rx: false, catalogSlug: nil)
        XCTAssertEqual(p.vialPriceUSD, 56, accuracy: 1e-9)   // 40 * 1.4
        XCTAssertEqual(p.priceText, "$56")

        let reta = ShopProduct(code: "RT10", compound: "Retatrutide", categoryRaw: "weightLoss",
                               strength: "10 mg", vialsPerKit: 10, kitCostUSD: 104, rx: true, catalogSlug: nil)
        XCTAssertEqual(reta.vialPriceUSD, 146, accuracy: 1e-9)   // 145.6 → 146
    }

    func testGroupsCollapseStrengthsAndFromPrice() {
        let groups = ShopCatalog.groups()
        let sema = groups.first { $0.compound == "Semaglutide" }
        XCTAssertNotNil(sema)
        XCTAssertEqual(sema?.products.count, 5)              // 5/10/15/20/30 mg
        XCTAssertEqual(sema?.rx, true)
        XCTAssertEqual(sema?.fromPriceText, "from $56")      // cheapest = 5mg kit 40 → 56
        // strengths sorted low → high by price
        let prices = sema?.products.map(\.vialPriceUSD) ?? []
        XCTAssertEqual(prices, prices.sorted())
    }

    func testByCategoryIsOrderedAndNonEmpty() {
        let cats = ShopCatalog.byCategory()
        XCTAssertFalse(cats.isEmpty)
        let orders = cats.map { $0.0.order }
        XCTAssertEqual(orders, orders.sorted())
    }

    // MARK: Cart

    func testCartAddBumpsQuantityAndSubtotal() {
        let svc = ShopCartService(context: ctx())
        let p = ShopCatalog.groups().first { $0.compound == "BPC-157" }!.products[0]   // 5mg, $56
        svc.add(p)
        svc.add(p)                                          // same SKU → quantity 2, not a dupe row
        XCTAssertEqual(svc.items().count, 1)
        XCTAssertEqual(svc.count(), 2)
        XCTAssertEqual(svc.subtotalUSD(), p.vialPriceUSD * 2, accuracy: 1e-9)
    }

    func testCartQuantityToZeroRemoves() {
        let c = ctx()
        let svc = ShopCartService(context: c)
        let p = ShopCatalog.load().first!
        svc.add(p)
        let item = svc.items()[0]
        svc.setQuantity(item, 0)
        XCTAssertTrue(svc.items().isEmpty)
    }

    func testApprovalRoundTrips() {
        let c = ctx()
        let s = CatalogStore.fetchOrCreateSettings(c)
        XCTAssertEqual(s.shopApproval, .none)
        s.shopApproval = .pending
        XCTAssertEqual(s.shopApprovalRaw, "pending")
        XCTAssertEqual(s.shopApproval, .pending)
    }
}
