import Foundation
import SwiftData

/// Cart writes + reads for the shop (M36). Mirrors StackService: `@MainActor struct`.
/// UI-only commerce; no payment is taken here.
@MainActor
struct ShopCartService {
    let context: ModelContext

    func items() -> [ShopCartItem] {
        let all = (try? context.fetch(FetchDescriptor<ShopCartItem>())) ?? []
        return all.sorted { $0.addedAt < $1.addedAt }
    }

    func count() -> Int { items().reduce(0) { $0 + $1.quantity } }

    func subtotalUSD() -> Double { items().reduce(0) { $0 + $1.lineTotalUSD } }

    /// Add a vial; if the same SKU is already in the cart, bump its quantity.
    func add(_ product: ShopProduct) {
        if let existing = items().first(where: { $0.productCode == product.code }) {
            existing.quantity += 1
        } else {
            let it = ShopCartItem()
            it.productCode = product.code
            it.compound = product.compound
            it.strength = product.strength
            it.categoryRaw = product.categoryRaw
            it.unitPriceUSD = product.vialPriceUSD
            it.quantity = 1
            context.insert(it)
        }
        context.saveLogged("ShopCartService.add")
    }

    func setQuantity(_ item: ShopCartItem, _ q: Int) {
        if q <= 0 { context.delete(item) } else { item.quantity = q }
        context.saveLogged("ShopCartService.setQuantity")
    }

    func remove(_ item: ShopCartItem) {
        context.delete(item)
        context.saveLogged("ShopCartService.remove")
    }

    func clear() {
        for it in items() { context.delete(it) }
        context.saveLogged("ShopCartService.clear")
    }
}
