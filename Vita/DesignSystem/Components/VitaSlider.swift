import SwiftUI

/// The signature 1–10 slider (M8a). Integer magnetic detents with a crisp haptic
/// tick per integer crossed, a value bubble that rides ABOVE the knob (never under
/// the finger), a grow-on-grab knob with a deepening shadow, a spring-overshoot
/// settle on release, tap-track-to-jump, velocity-tolerant dragging, a Reduce-Motion
/// path, and full VoiceOver adjustability. Pure mapping/snapping math lives in
/// `VitaSliderMath` so it unit-tests with zero UI.
struct VitaSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...10
    var accent: Color
    var label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragging = false
    @State private var dragX: CGFloat? = nil
    @ScaledMetric(relativeTo: .body) private var bubbleClearance: CGFloat = 16

    private let trackHeight: CGFloat = 8
    private let knobRest: CGFloat = 28
    private let knobGrab: CGFloat = 36
    private let bubbleWidth: CGFloat = 40
    private var knobRadius: CGFloat { knobGrab / 2 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = knobCenterX(width: w)
            ZStack(alignment: .topLeading) {
                // Track background
                Capsule().fill(VT.ink.opacity(0.10))
                    .frame(height: trackHeight)
                    .position(x: w / 2, y: h / 2)
                // Filled track
                Capsule().fill(accent)
                    .frame(width: max(cx, knobRadius), height: trackHeight)
                    .position(x: max(cx, knobRadius) / 2, y: h / 2)
                // Quiet detent ticks
                ForEach(Array(range), id: \.self) { i in
                    Circle().fill(VT.ink.opacity(0.06)).frame(width: 3, height: 3)
                        .position(x: VitaSliderMath.centerX(forValue: i, width: w,
                                                            knobRadius: knobRadius, range: range), y: h / 2)
                }
                // Knob
                Circle().fill(VT.card)
                    .overlay(Circle().strokeBorder(accent, lineWidth: 2))
                    .overlay(Circle().fill(accent).frame(width: 6, height: 6))
                    .frame(width: dragging ? knobGrab : knobRest,
                           height: dragging ? knobGrab : knobRest)
                    .shadow(color: VT.ink.opacity(dragging ? 0.16 : 0.07),
                            radius: dragging ? 9 : 4, x: 0, y: dragging ? 4 : 2)
                    .position(x: cx, y: h / 2)
                    .animation(reduceMotion ? VMotion.reduced
                               : .spring(response: 0.28, dampingFraction: 0.7), value: dragging)
                // Value bubble — above the knob, clamped in-bounds
                bubble
                    .frame(width: bubbleWidth)
                    .opacity(dragging ? 1 : 0)
                    .scaleEffect(dragging ? 1 : 0.6, anchor: .bottom)
                    .position(x: VitaSliderMath.clampedBubbleX(center: cx, bubbleWidth: bubbleWidth, laneWidth: w),
                              y: h / 2 - knobGrab / 2 - bubbleClearance)
                    .animation(reduceMotion ? VMotion.reduced
                               : .spring(response: 0.25, dampingFraction: 0.8), value: dragging)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(drag(width: w))
        }
        .frame(height: knobGrab + bubbleClearance + 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) of \(range.upperBound)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: set(min(value + 1, range.upperBound))
            case .decrement: set(max(value - 1, range.lowerBound))
            @unknown default: break
            }
        }
    }

    private var bubble: some View {
        Text("\(value)")
            .font(VFont.value(17, relativeTo: .body)).vtTabular()
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(accent, in: Capsule())
            .shadow(color: VT.ink.opacity(0.12), radius: 4, x: 0, y: 2)
            .fixedSize()
    }

    /// Knob center: follows the finger continuously while dragging (liquid, 1:1),
    /// else driven by the snapped value (so release springs to the detent).
    private func knobCenterX(width: CGFloat) -> CGFloat {
        if let dx = dragX { return min(max(dx, knobRadius), width - knobRadius) }
        return VitaSliderMath.centerX(forValue: value, width: width, knobRadius: knobRadius, range: range)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { g in
                let raw = VitaSliderMath.value(forDragX: g.location.x, width: width,
                                               knobRadius: knobRadius, range: range)
                if raw != value {                       // exactly one tick per integer crossed
                    value = raw
                    if !reduceMotion { Haptics.segment() }
                }
                dragX = g.location.x
            }
            .onEnded { g in
                let snapped = VitaSliderMath.nearestDetent(forDragX: g.location.x, width: width,
                                                           knobRadius: knobRadius, range: range)
                if snapped != value { value = snapped; if !reduceMotion { Haptics.segment() } }
                withAnimation(reduceMotion ? VMotion.reduced : VMotion.sliderSettle) { dragX = nil }
            }
    }

    private func set(_ v: Int) {
        guard v != value else { return }
        value = v
        if !reduceMotion { Haptics.segment() }
        withAnimation(reduceMotion ? VMotion.reduced : VMotion.sliderSettle) { dragX = nil }
    }
}

/// Pure mapping/snapping core — unit-testable without any view.
enum VitaSliderMath {
    /// Continuous position 0…1 for a value (clamped).
    static func position(forValue v: Int, range: ClosedRange<Int>) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let c = min(max(v, range.lowerBound), range.upperBound)
        return CGFloat(c - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
    }
    /// Knob CENTER x for a value inside an inset track.
    static func centerX(forValue v: Int, width: CGFloat, knobRadius: CGFloat, range: ClosedRange<Int>) -> CGFloat {
        let usable = max(width - 2 * knobRadius, 0)
        return knobRadius + position(forValue: v, range: range) * usable
    }
    /// Continuous fraction 0…1 from a drag x (clamped to the inset track).
    static func fraction(forDragX x: CGFloat, width: CGFloat, knobRadius: CGFloat) -> CGFloat {
        let usable = max(width - 2 * knobRadius, 0)
        guard usable > 0 else { return 0 }
        return min(max((x - knobRadius) / usable, 0), 1)
    }
    /// Live integer value from a drag x (round-to-nearest, clamped).
    static func value(forDragX x: CGFloat, width: CGFloat, knobRadius: CGFloat, range: ClosedRange<Int>) -> Int {
        let f = fraction(forDragX: x, width: width, knobRadius: knobRadius)
        let span = CGFloat(range.upperBound - range.lowerBound)
        let v = range.lowerBound + Int((f * span).rounded())
        return min(max(v, range.lowerBound), range.upperBound)
    }
    /// Snap target on release (same rule; named for intent + tests).
    static func nearestDetent(forDragX x: CGFloat, width: CGFloat, knobRadius: CGFloat, range: ClosedRange<Int>) -> Int {
        value(forDragX: x, width: width, knobRadius: knobRadius, range: range)
    }
    /// Bubble x clamped inside the lane so it never spills past an edge.
    static func clampedBubbleX(center: CGFloat, bubbleWidth bw: CGFloat, laneWidth: CGFloat) -> CGFloat {
        min(max(center, bw / 2), max(laneWidth - bw / 2, bw / 2))
    }
}

/// A labeled slider row for the check-in sheet (metric lead word + value + slider).
struct MetricSlider: View {
    let metric: DiaryMetric
    @Binding var value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                vtLead(metric.title + ".", color: metric.accent, size: 16)
                Spacer()
                Text(value == 0 ? "–" : "\(value)")
                    .font(.system(size: 15, weight: .semibold)).vtTabular().foregroundStyle(VT.micro)
            }
            VitaSlider(value: $value, accent: metric.accent, label: metric.title)
        }
    }
}

#Preview {
    struct Demo: View {
        @State var energy = 7
        @State var sleep = 4
        @State var mood = 9
        @State var libido = 1
        var body: some View {
            VStack(spacing: VT.sSection) {
                MetricSlider(metric: .energy, value: $energy)
                MetricSlider(metric: .sleep, value: $sleep)
                MetricSlider(metric: .mood, value: $mood)
                MetricSlider(metric: .libido, value: $libido)
            }
            .padding(VT.sCardPad).vtCard()
            .padding(VT.sSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VT.canvas)
        }
    }
    return Demo()
}
