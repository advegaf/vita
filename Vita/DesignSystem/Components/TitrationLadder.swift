import SwiftUI

/// Read-only vertical stepped list of a titration ladder (week + dose). A thin
/// connector spine ties the steps; the current step is accent-highlighted, past
/// muted, future normal. Driven by `[ScheduleService.TitrationStep]`.
struct TitrationLadder: View {
    let steps: [ScheduleService.TitrationStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        if step.id != 0 {
                            Rectangle().fill(VT.hairline).frame(width: 2).frame(maxHeight: .infinity)
                        }
                        Circle()
                            .fill(step.isCurrent ? VT.dose : (step.isPast ? VT.micro.opacity(0.5) : VT.ink.opacity(0.15)))
                            .frame(width: step.isCurrent ? 10 : 7, height: step.isCurrent ? 10 : 7)
                    }
                    .frame(width: 12)
                    HStack(spacing: 6) {
                        Text("Week \(step.weekStart)")
                            .font(.system(size: 13, weight: step.isCurrent ? .semibold : .regular))
                            .foregroundStyle(step.isCurrent ? VT.ink : VT.micro)
                        Text("·").foregroundStyle(VT.micro)
                        Text("\(vtFormatNumber(step.dose)) \(step.unit.label)")
                            .font(.system(size: 14, weight: step.isCurrent ? .semibold : .regular)).vtTabular()
                            .foregroundStyle(step.isCurrent ? VT.dose : (step.isPast ? VT.micro : VT.body))
                        if step.isCurrent {
                            Text("now").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(VT.dose, in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(.bottom, 10)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Week \(step.weekStart), \(vtFormatNumber(step.dose)) \(step.unit.label)\(step.isCurrent ? ", current" : "")")
            }
        }
    }
}

#Preview {
    TitrationLadder(steps: [
        .init(id: 0, weekStart: 1, dose: 0.25, unit: .mg, isCurrent: false, isPast: true),
        .init(id: 1, weekStart: 5, dose: 0.5, unit: .mg, isCurrent: true, isPast: false),
        .init(id: 2, weekStart: 9, dose: 1.0, unit: .mg, isCurrent: false, isPast: false),
    ])
    .padding(VT.sCardPad).vtCard().padding(VT.sSection).background(VT.canvas)
}
