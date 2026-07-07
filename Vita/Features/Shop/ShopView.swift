import SwiftUI
import SwiftData

/// The Shop tab. Browse vials by category, open a product to pick a strength, add
/// to cart. Commerce is UI-only for now: nothing charges, and prescription compounds
/// are dispensed only after medical approval (the gate lives in the cart).
struct ShopView: View {
    @Environment(\.modelContext) private var context
    @Query private var cart: [ShopCartItem]
    @Query private var settings: [AppSettings]

    @State private var search = ""
    @State private var showCart = false
    @FocusState private var searchFocused: Bool

    private let groupsByCategory = ShopCatalog.byCategory()
    private var cartCount: Int { cart.reduce(0) { $0 + $1.quantity } }
    private var approval: ShopApproval { settings.first?.shopApproval ?? .none }

    var body: some View {
        NavigationStack {
            ZStack {
                VT.canvas.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VT.sSection) {
                        header
                        framingNote
                        searchField
                        if approval != .none { approvalBanner }
                        if filtered.isEmpty {
                            noResults
                        } else {
                            ForEach(filtered, id: \.0) { cat, groups in
                                section(cat, groups)
                            }
                        }
                    }
                    .padding(VT.sSection)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .dismissesKeyboardOnTap()
            }
            .navigationDestination(for: ShopGroup.self) { ShopProductDetailView(group: $0) }
            .sheet(isPresented: $showCart) { ShopCartView() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ScreenHeader(eyebrow: "Shop", title: "Shop.")
            Spacer()
            ZStack(alignment: .topTrailing) {
                CircleIconButton(systemName: "bag", label: "Cart") { showCart = true }
                if cartCount > 0 {
                    Text("\(cartCount)")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(VT.catPink, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    private var framingNote: some View {
        Text("Educational, not medical advice. Prescription compounds are dispensed only after medical approval.")
            .font(.system(size: 13)).foregroundStyle(VT.micro)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var approvalBanner: some View {
        let (line, color): (String, Color) = approval == .approved
            ? ("You're approved to order.", VT.why)
            : ("Approval under review.", VT.timing)
        HStack(spacing: 8) {
            Image(systemName: approval == .approved ? "checkmark.seal.fill" : "clock.fill")
                .foregroundStyle(color)
            Text(line).font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12).vtCard()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(VT.micro)
            TextField("Search products", text: $search)
                .foregroundStyle(VT.ink).autocorrectionDisabled().focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(VT.micro)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(VT.card, in: Capsule())
        .overlay(Capsule().stroke(VT.hairline, lineWidth: 1))
    }

    // MARK: Sections

    private func section(_ cat: PeptideCategory, _ groups: [ShopGroup]) -> some View {
        VStack(alignment: .leading, spacing: VT.sCardGap) {
            Text(cat.title.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(0.4).foregroundStyle(VT.micro)
            VStack(spacing: 0) {
                ForEach(groups) { g in
                    NavigationLink(value: g) { row(g) }
                        .buttonStyle(.pressableCard)
                    if g.id != groups.last?.id {
                        Rectangle().fill(VT.hairline).frame(height: 1).padding(.leading, 72)
                    }
                }
            }
            .vtCard()
        }
    }

    private func row(_ g: ShopGroup) -> some View {
        HStack(spacing: 12) {
            CompoundTile(category: g.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.compound)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(2)
                Text(strengthSummary(g))
                    .font(.system(size: 13)).vtTabular().foregroundStyle(VT.body)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if g.rx { RxBadge() }
            Text(g.fromPriceText)
                .font(.system(size: 15, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func strengthSummary(_ g: ShopGroup) -> String {
        let n = g.products.count
        return n == 1 ? g.products[0].strength : "\(n) strengths"
    }

    private var noResults: some View {
        VStack(spacing: 6) {
            Text("No matches.").font(.vtHeadline).foregroundStyle(VT.ink)
            Text("Try a different name.").font(.system(size: 15)).foregroundStyle(VT.body)
        }
        .frame(maxWidth: .infinity).padding(.top, 48)
    }

    private var filtered: [(PeptideCategory, [ShopGroup])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groupsByCategory }
        return groupsByCategory.compactMap { cat, groups in
            let hits = groups.filter { $0.compound.lowercased().contains(q) }
            return hits.isEmpty ? nil : (cat, hits)
        }
    }
}

#Preview { ShopView() }
