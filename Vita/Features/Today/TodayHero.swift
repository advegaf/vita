import SwiftUI

/// The Today editorial hero (M40, Lumina-style): one display-size headline
/// mixing ink-black subjects with soft-gray connectors, emoji where the
/// language calls for warmth. Replaces the rings hero + old count headline.
struct TodayHero: View {
    enum State: Equatable {
        /// Next pending dose: block title, compound name, pending-in-block count, time text.
        case upNext(block: String, compound: String, count: Int, time: String)
        /// Something slipped: compound + its scheduled time.
        case overdue(compound: String, time: String)
        case allDone
        case restDay
    }

    var state: State

    var body: some View {
        headline
            .font(VFont.display(29, weight: .bold, relativeTo: .largeTitle))
            .tracking(-0.6)
            .lineSpacing(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .accessibilityAddTraits(.isHeader)
    }

    private func soft(_ s: String) -> Text { Text(s).foregroundStyle(VT.inkSoft) }
    private func hard(_ s: String) -> Text {
        // Times like "8:00 AM" must never break across lines mid-value.
        Text(s.replacingOccurrences(of: " ", with: "\u{00A0}")).foregroundStyle(VT.ink)
    }

    private var headline: Text {
        switch state {
        case let .upNext(block, compound, count, time):
            if count > 1 {
                return Text("\(soft("It's almost time for your "))\(hard("\(block.lowercased()) doses")) 💊\(soft("×\(count), starting at "))\(hard(time))")
            }
            return Text("\(soft("It's almost time for your "))\(hard("\(block.lowercased()) \(compound)"))\(soft(" planned at "))\(hard(time))")
        case let .overdue(compound, time):
            return Text("\(hard("Time to catch up"))\(soft(" on your "))\(hard(compound))\(soft(", planned at "))\(hard(time))")
        case .allDone:
            return Text("\(hard("That's everything"))\(soft(" for today "))\(hard("✨"))")
        case .restDay:
            return Text("\(hard("A rest day"))\(soft(" today "))\(hard("🌿"))")
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 28) {
        TodayHero(state: .upNext(block: "Morning", compound: "BPC-157", count: 1, time: "8:00 AM"))
        TodayHero(state: .upNext(block: "Morning", compound: "BPC-157", count: 2, time: "8:00 AM"))
        TodayHero(state: .overdue(compound: "TB-500", time: "9:00 AM"))
        TodayHero(state: .allDone)
        TodayHero(state: .restDay)
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
