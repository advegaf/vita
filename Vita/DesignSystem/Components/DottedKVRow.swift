import SwiftUI

/// Key…value row with a dotted leader line (M40, from the confirm-sheet
/// mockup): gray label left, value right, dots bridging the gap. The value
/// can be plain text or any view (avatar chip, colored text).
struct DottedKVRow<Value: View>: View {
    var label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(VT.micro)
                .layoutPriority(1)
            Line()
                .stroke(VT.hairline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 5]))
                .frame(height: 1.5)
                .offset(y: -3)
            value
                .layoutPriority(1)
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

extension DottedKVRow where Value == Text {
    /// Plain-text value convenience: bold-ish ink value, tabular figures.
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = Text(value)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(VT.ink)
    }
}

#Preview {
    VStack(spacing: 4) {
        DottedKVRow("Vial size", "10 mg")
        DottedKVRow("Water added", "2.0 mL")
        DottedKVRow("Draw", "10 units")
        DottedKVRow(label: "Next site") {
            Text("→ left thigh")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
        }
    }
    .padding(VT.sCardPad)
    .vtCard()
    .padding(VT.sSection)
    .background(VT.canvas)
}
