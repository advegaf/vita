import SwiftUI

// Inter Tight for headlines + big dose values; SF Pro (system) for body.
// Falls back gracefully to the system font if the bundled face fails to register.

enum VFont {
    static let family = "Inter Tight"

    private static let available: Bool = {
        UIFont(name: family, size: 12) != nil
    }()

    /// Headline / display face. Tight, bold grotesk with a mandatory trailing period in copy.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo: Font.TextStyle = .largeTitle) -> Font {
        if available {
            return .custom(family, size: size, relativeTo: relativeTo).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// Big dose values — same face, with tabular figures applied at the call site.
    static func value(_ size: CGFloat, relativeTo: Font.TextStyle = .title) -> Font {
        display(size, weight: .heavy, relativeTo: relativeTo)
    }
}

extension Font {
    /// Screen headline: ~34–40pt, two lines, tight, period-punctuated.
    static var vtHeadline: Font { VFont.display(34, weight: .bold, relativeTo: .largeTitle) }
    /// The value-picker word (the "Monstera" slot → peptide name).
    static var vtPicker: Font { VFont.display(30, weight: .bold, relativeTo: .title) }
    /// Card lead word ("Dose." / "Timing." / "Why.").
    static var vtLeadWord: Font { VFont.display(22, weight: .bold, relativeTo: .title2) }
    /// Big dose number ("Draw to 20 units").
    static var vtDose: Font { VFont.value(28, relativeTo: .title) }
}

extension View {
    /// Headlines use tight tracking and near-1.0 line height.
    func vtHeadlineStyle() -> some View {
        self.font(.vtHeadline)
            .tracking(-0.8)
            .lineSpacing(-2)
            .foregroundStyle(VT.ink)
    }

    /// Tabular figures for every changing number (doses, countdowns, units).
    func vtTabular() -> some View { monospacedDigit() }
}
