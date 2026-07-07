import SwiftUI
import SwiftData

/// The cart + the medical-approval gate. Checkout is UI-only (no charge): an
/// approved cart shows a disabled "Coming soon" until the Stripe backend lands.
struct ShopCartView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ShopCartItem.addedAt) private var items: [ShopCartItem]
    @Query private var settings: [AppSettings]
    @State private var showIntake = false

    private var approval: ShopApproval { settings.first?.shopApproval ?? .none }
    private var subtotal: Double { items.reduce(0) { $0 + $1.lineTotalUSD } }

    var body: some View {
        NavigationStack {
            ZStack {
                VT.canvas.ignoresSafeArea()
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: VT.sCardGap) {
                            ForEach(items) { row($0) }
                            subtotalRow
                            gate
                        }
                        .padding(VT.sSection)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(VT.ink)
                }
            }
            .sheet(isPresented: $showIntake) { ApprovalIntakeView() }
        }
    }

    private func row(_ item: ShopCartItem) -> some View {
        HStack(spacing: 12) {
            CompoundTile(category: item.category, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.compound).font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                Text("\(item.strength), $\(Int(item.unitPriceUSD)) each")
                    .font(.system(size: 13)).vtTabular().foregroundStyle(VT.body)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stepper(item)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).vtCard()
    }

    private func stepper(_ item: ShopCartItem) -> some View {
        let svc = ShopCartService(context: context)
        return HStack(spacing: 10) {
            Button { svc.setQuantity(item, item.quantity - 1); Haptics.press() } label: {
                Image(systemName: item.quantity <= 1 ? "trash" : "minus")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(VT.ink)
                    .frame(width: 30, height: 30).background(VT.canvas, in: Circle())
            }.buttonStyle(.plain)
            Text("\(item.quantity)").font(.system(size: 15, weight: .semibold)).vtTabular()
                .frame(minWidth: 18)
            Button { svc.setQuantity(item, item.quantity + 1); Haptics.press() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(VT.ink)
                    .frame(width: 30, height: 30).background(VT.canvas, in: Circle())
            }.buttonStyle(.plain)
        }
    }

    private var subtotalRow: some View {
        HStack {
            Text("Subtotal").font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
            Spacer()
            Text("$\(Int(subtotal))").font(.system(size: 18, weight: .bold)).vtTabular().foregroundStyle(VT.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var gate: some View {
        switch approval {
        case .none:
            VStack(alignment: .leading, spacing: 10) {
                gateLine("lock.shield", VT.timing, "Medical approval required",
                         "A licensed provider reviews your request before anything ships.")
                CharcoalPillButton(title: "Start approval") { showIntake = true }
            }
            .padding(VT.sCardPad).vtCard()
        case .pending:
            gateCard("clock.fill", VT.timing, "Approval under review",
                     "We'll let you know once a provider has reviewed your request.")
        case .approved:
            VStack(alignment: .leading, spacing: 10) {
                gateLine("checkmark.seal.fill", VT.why, "You're approved",
                         "Online checkout is coming soon. We'll reach out to complete your order.")
                HStack(spacing: 8) { Image(systemName: "creditcard"); Text("Checkout coming soon") }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(VT.ink.opacity(0.35), in: Capsule())
            }
            .padding(VT.sCardPad).vtCard()
        }
    }

    private func gateCard(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { gateLine(icon, color, title, sub) }
            .padding(VT.sCardPad).vtCard()
    }

    private func gateLine(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
            }
            Text(sub).font(.system(size: 13)).foregroundStyle(VT.micro)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Your cart is empty.")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
            Text("Browse the shop to add a vial.")
                .font(.system(size: 15)).foregroundStyle(VT.body)
        }
        .frame(maxWidth: .infinity).padding(.top, 64)
    }
}
