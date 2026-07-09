import SwiftUI

/// The bottom tab bar, styled as a surface CARVED INTO the canvas rather than
/// floating glass: a fill one shade below the canvas, a soft inner shadow falling
/// from its top edge, and a hairline seam. The selected tab sits in a subtle
/// darker well (pressed-in), not a raised pill.
struct ConcaveTabBar: View {
    @Binding var selection: AppTab
    /// Collapse while the keyboard is up (matches the old system-bar behavior in
    /// Chat: typing hides the bar instead of stacking it above the keyboard).
    @State private var keyboardUp = false

    /// One shade below the canvas in both modes (the "carved" floor).
    private let floor = Color(light: "E9E4DC", dark: "0D0D0F")
    /// The selected item's well, one further step down.
    private let well = Color(light: "DFD9CF", dark: "17171A")
    private let seam = Color(light: "DCD7CD", dark: "26262B")

    private struct Item {
        let tab: AppTab
        let title: String
        let icon: String
        let tint: Color
    }

    private let items: [Item] = [
        .init(tab: .today, title: "Today", icon: "sun.max", tint: VT.dose),
        .init(tab: .stack, title: "Stack", icon: "pills", tint: VT.why),
        .init(tab: .diary, title: "Diary", icon: "chart.xyaxis.line", tint: VT.timing),
        .init(tab: .chat, title: "Chat", icon: "bubble.left.and.text.bubble.right", tint: VT.dose),
    ]

    var body: some View {
        Group {
            if !keyboardUp {
                HStack(spacing: 6) {
                    ForEach(items, id: \.tab) { item in
                        tabButton(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .background {
                    ZStack(alignment: .top) {
                        floor.ignoresSafeArea(edges: .bottom)
                        // The concave read: a soft shadow falling INTO the bar from
                        // its top edge, as if the canvas casts onto a recessed surface.
                        LinearGradient(colors: [Color.black.opacity(0.10), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 10)
                        Rectangle().fill(seam).frame(height: 1)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardUp = false }
        }
    }

    private func tabButton(_ item: Item) -> some View {
        let selected = selection == item.tab
        return Button {
            guard selection != item.tab else { return }
            Haptics.segment()
            selection = item.tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.icon)
                    .font(.system(size: 19, weight: selected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(item.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? item.tint : VT.micro)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? well : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Light") {
    VStack {
        Spacer()
        ConcaveTabBar(selection: .constant(.today))
    }
    .background(VT.canvas)
}

#Preview("Dark") {
    VStack {
        Spacer()
        ConcaveTabBar(selection: .constant(.stack))
    }
    .background(VT.canvas)
    .preferredColorScheme(.dark)
}
