import Foundation

/// Shop pricing + catalog. UI-only commerce surface (no real checkout yet).
/// Educational framing still applies; products are dispensed only after medical approval.
enum Shop {
    /// One vial sells at this multiple of the whole-kit supply cost (user-set).
    /// Every kit is `vialsPerKit` vials, so this is an intentionally fat margin.
    static let markup = 1.40
}

/// One purchasable SKU (a single vial at a given strength). Decoded from
/// `shop-products.json`; the price is DERIVED so the markup lives in one place.
struct ShopProduct: Codable, Identifiable, Hashable, Sendable {
    var code: String              // "SM5"
    var compound: String          // "Semaglutide" (group display name)
    var categoryRaw: String       // PeptideCategory raw, for the vial tint
    var strength: String          // "5 mg"
    var vialsPerKit: Int
    var kitCostUSD: Double         // the 1-kit supply price
    var rx: Bool                   // prescription compound → ℞ badge
    var catalogSlug: String?       // links to a CatalogCompound for About copy

    var id: String { code }
    var category: PeptideCategory { PeptideCategory(rawValue: categoryRaw) ?? .other }

    enum CodingKeys: String, CodingKey {
        case code, compound, strength, vialsPerKit, kitCostUSD, rx, catalogSlug
        case categoryRaw = "category"
    }

    /// Per-vial price = kit supply cost × markup, rounded to the dollar.
    var vialPriceUSD: Double { (kitCostUSD * Shop.markup).rounded() }
    var priceText: String { "$\(Int(vialPriceUSD))" }
}

/// A compound group (one shop row → a detail with selectable strengths).
struct ShopGroup: Identifiable, Hashable, Sendable {
    var compound: String
    var category: PeptideCategory
    var rx: Bool
    var catalogSlug: String?
    var products: [ShopProduct]    // sorted by price, low → high
    var id: String { compound }
    var fromPriceText: String { "from $\(Int(products.map(\.vialPriceUSD).min() ?? 0))" }
}

enum ShopCatalog {
    private struct File: Decodable { let products: [ShopProduct] }

    /// All SKUs from the bundled JSON (app or test host bundle).
    static func load() -> [ShopProduct] {
        for b in [Bundle.main, Bundle(for: VitaBundleMarker.self)] {
            if let url = b.url(forResource: "shop-products", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(File.self, from: data) {
                return file.products
            }
        }
        return []
    }

    /// Products grouped by compound (preserving first-seen order), strengths price-sorted.
    static func groups(_ products: [ShopProduct] = load()) -> [ShopGroup] {
        var order: [String] = []
        var byCompound: [String: [ShopProduct]] = [:]
        for p in products {
            if byCompound[p.compound] == nil { order.append(p.compound) }
            byCompound[p.compound, default: []].append(p)
        }
        return order.map { name in
            let items = (byCompound[name] ?? []).sorted { $0.vialPriceUSD < $1.vialPriceUSD }
            let first = items.first
            return ShopGroup(compound: name,
                             category: first?.category ?? .other,
                             rx: items.contains { $0.rx },
                             catalogSlug: items.compactMap(\.catalogSlug).first,
                             products: items)
        }
    }

    /// Grouped by category (catalog order), each holding its compound groups.
    static func byCategory(_ products: [ShopProduct] = load()) -> [(PeptideCategory, [ShopGroup])] {
        let all = groups(products)
        let dict = Dictionary(grouping: all, by: \.category)
        let cats = dict.keys.sorted { $0.order < $1.order }
        var out: [(PeptideCategory, [ShopGroup])] = []
        for cat in cats {
            let sorted = (dict[cat] ?? []).sorted { $0.compound < $1.compound }
            out.append((cat, sorted))
        }
        return out
    }
}

/// Local approval state for the medical gate (real prescriber/admin backend comes later).
enum ShopApproval: String, Codable, Sendable {
    case none, pending, approved
}
