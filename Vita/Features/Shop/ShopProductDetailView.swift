import SwiftUI
import SwiftData

/// One compound's product page: pick a strength, see the per-vial price, view the
/// COA, add to cart. Educational framing + prescription note preserved.
struct ShopProductDetailView: View {
    let group: ShopGroup

    @Environment(\.modelContext) private var context
    @Query private var compounds: [CatalogCompound]
    @State private var selectedCode: String
    @State private var added = false
    @State private var showCOANote = false

    init(group: ShopGroup) {
        self.group = group
        _selectedCode = State(initialValue: group.products.first?.code ?? "")
    }

    private var selected: ShopProduct {
        group.products.first { $0.code == selectedCode } ?? group.products[0]
    }
    private var about: String? {
        guard let slug = group.catalogSlug else { return nil }
        return compounds.first { $0.slug == slug }?.about
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                header
                priceCard
                if group.products.count > 1 { strengthCard }
                coaCard
                if let about { aboutCard(about) }
                disclaimer
                addButton
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRODUCT")
                .font(.system(size: 12, weight: .medium)).tracking(0.4).foregroundStyle(VT.micro)
            HStack(spacing: 8) {
                Text(group.compound).font(.vtPicker).foregroundStyle(VT.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if group.rx { RxBadge() }
                Spacer(minLength: 0)
            }
        }
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead("Price.", color: VT.dose)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selected.priceText).font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                    .contentTransition(.numericText())
                Text("per vial (\(selected.strength))")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
            }
            Text("Single vial. Kits of \(selected.vialsPerKit) available on request.")
                .font(.system(size: 13)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Strength.", color: VT.timing)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.products) { p in
                        PillToggle(title: p.strength, isOn: p.code == selectedCode, fillsWidth: false) {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedCode = p.code }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var coaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation { showCOANote.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass").foregroundStyle(VT.why)
                    Text("Certificate of Analysis")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(VT.micro)
                }
            }
            .buttonStyle(.plain)
            if showCOANote {
                Text("COA for this batch is available on request. Lab documents will appear here.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func aboutCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (vtLead("About.", color: VT.why) + Text(" ") + vtBody(text))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(VT.sCardPad).vtCard()
    }

    private var disclaimer: some View {
        Text(group.rx
             ? "Prescription compound. Requires medical approval before it can be dispensed. Educational, not medical advice."
             : "Educational, not medical advice. Dispensed only after medical approval.")
            .font(.system(size: 12)).foregroundStyle(VT.micro)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var addButton: some View {
        if added {
            HStack(spacing: 8) { Image(systemName: "checkmark"); Text("Added to cart") }
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(VT.why, in: Capsule()).padding(.top, 4)
        } else {
            CharcoalPillButton(title: "Add to cart") {
                ShopCartService(context: context).add(selected)
                Haptics.press()
                withAnimation { added = true }
            }
            .padding(.top, 4)
        }
    }
}
