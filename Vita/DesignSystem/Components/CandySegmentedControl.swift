import SwiftUI

/// One segment of the candy control.
struct CandySegment: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    let glyph: Color  // glyph color for contrast on the segment color

    static func dimension(_ id: String, _ title: String, _ symbol: String, _ color: Color, glyphInk: Bool = false) -> CandySegment {
        CandySegment(id: id, title: title, symbol: symbol, color: color, glyph: glyphInk ? VT.ink : .white)
    }
}

/// The signature spine: an expand-on-select control. The active segment WIDENS
/// (interpolating-width spring), inactive segments shrink to ~44pt circles.
/// NOT a stock Picker, NOT a cross-fade. Reused as the detail dimension switcher
/// AND the Today Morning/Midday/Night index.
struct CandySegmentedControl: View {
    let segments: [CandySegment]
    @Binding var selection: String
    var onSelect: ((String) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(segments) { seg in
                segmentView(seg)
            }
        }
        .animation(reduceMotion ? VMotion.reduced : VMotion.segmentExpand, value: selection)
    }

    @ViewBuilder
    private func segmentView(_ seg: CandySegment) -> some View {
        let active = seg.id == selection
        Button {
            guard !active else { return }
            Haptics.segment()
            selection = seg.id
            onSelect?(seg.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: seg.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(seg.glyph)
                if active {
                    Text(seg.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(seg.glyph)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .frame(height: VT.segmentCircle)
            .frame(maxWidth: active ? .infinity : VT.segmentCircle)
            .background(
                Group {
                    if active {
                        Capsule().fill(seg.color)
                    } else {
                        Circle().fill(seg.color)
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seg.title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

// Convenience factories for the two app-wide uses.
extension CandySegmentedControl {
    static let dimensionSegments: [CandySegment] = [
        .dimension("dose", "Dose", "drop.fill", VT.dose),
        .dimension("timing", "Timing", "sun.max.fill", VT.timing, glyphInk: true),
        .dimension("why", "Why", "leaf.fill", VT.why),
    ]
    static let dayBlockSegments: [CandySegment] = [
        .dimension("morning", "Morning", "sunrise.fill", VT.timing, glyphInk: true),
        .dimension("midday", "Midday", "sun.max.fill", VT.dose),
        .dimension("night", "Night", "moon.fill", VT.why),
    ]
}

#Preview {
    struct Demo: View {
        @State var sel = "dose"
        var body: some View {
            VStack(spacing: 32) {
                CandySegmentedControl(segments: CandySegmentedControl.dimensionSegments, selection: $sel)
                CandySegmentedControl(segments: CandySegmentedControl.dayBlockSegments, selection: .constant("midday"))
            }
            .padding(24)
            .background(VT.canvas)
        }
    }
    return Demo()
}
