import SwiftUI
import UIKit

// MARK: - Color hex helper

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8: // RRGGBBAA
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default: // RRGGBB
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Trait-adaptive token: resolves to `light` or `dark` per the live
    /// userInterfaceStyle (reacts to system changes AND the in-app override).
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { tc in
            UIColor(Color(hex: tc.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - The vita ("fields"-family) design tokens — a closed, semantic set.
// A card is NEVER filled with an accent. Accent appears only as a lead word,
// a small dot, or a segment knob.

enum VT {

    // Dark = warm graphite ("Style B", restored by user request): a barely-warm
    // near-neutral (canvas 141312). Neutral enough to avoid the brown-soup feel,
    // warm enough that the warm accent family (why latte, overdue terracotta,
    // timing tan) harmonizes instead of glowing.

    // Surfaces
    static let canvas   = Color(light: "F1EEE9", dark: "141312") // app background (never a card)
    static let card     = Color(light: "FFFFFF", dark: "1E1C1A") // every card / sheet
    static let hairline = Color(light: "EAE6DF", dark: "34302C") // divider / dark card border

    // Text
    static let ink   = Color(light: "1A1A1A", dark: "F3EEE7") // headlines, charcoal pill, bolded terms
    /// Label/glyph color sitting ON a filled surface (the ink pill, a selected toggle,
    /// the done checkmark): white in light, warm near-black in dark — because every
    /// dark-mode fill (ink, accents) is a light tone, so a dark label reads on all.
    static let onInk = Color(light: "FFFFFF", dark: "141312")
    static let body  = Color(light: "6E6E6E", dark: "B5AEA5") // body copy
    static let micro = Color(light: "9A958C", dark: "989187") // disclaimers, captions (>=4.5 on dark card)

    // Accents (semantic — each does double duty as dimension + day-state)
    static let dose   = Color(light: "2BB3F3", dark: "4FC3F7") // Dose  + "due-now / action"
    static let timing = Color(light: "FFC22E", dark: "FFCB4D") // Timing + "upcoming"
    static let why    = Color(light: "3E2B22", dark: "DDB9A4") // Why + "logged / done" (flips to light on dark)
    static let overdue = Color(light: "C0593F", dark: "D97E63") // overdue ONLY (never iOS error-red)

    // Category tints — matched to the vial render hues (one per category, closed set)
    static let catBlue   = Color(light: "3FA9E0", dark: "5CB8ED")  // Weight Loss
    static let catPurple = Color(light: "9B7FE0", dark: "B29AEB")  // Cognitive
    static let catBrown  = Color(light: "8A7059", dark: "B0917A")  // Muscle & Recovery (lifts so it doesn't vanish)
    static let catPink   = Color(light: "EC9CB4", dark: "F0A9BE")  // Sexual Health
    static let catYellow = Color(light: "E8B43C", dark: "ECC05A")  // General Health
    static let catGray   = Color(light: "9A958C", dark: "A7A093")  // Other

    /// Registry for the appearance test: every semantic color token, so the test can
    /// assert each resolves distinctly light vs dark and meets contrast on text.
    static let allColorTokens: [(name: String, color: Color)] = [
        ("canvas", canvas), ("card", card), ("hairline", hairline),
        ("ink", ink), ("body", body), ("micro", micro),
        ("dose", dose), ("timing", timing), ("why", why), ("overdue", overdue),
        ("catBlue", catBlue), ("catPurple", catPurple), ("catBrown", catBrown),
        ("catPink", catPink), ("catYellow", catYellow), ("catGray", catGray),
    ]

    // Radii
    static let rCard: CGFloat       = 20
    static let rFocusCard: CGFloat  = 24
    static let segmentCircle: CGFloat = 44

    // Spacing (4pt base)
    static let sCardPad: CGFloat = 20
    static let sCardGap: CGFloat = 14
    static let sSection: CGFloat = 24

    // Shadow (single layer; no border, no glow anywhere)
    static let shadowColor = Color(hex: "1A1A1A").opacity(0.06)
    static let shadowY: CGFloat = 8
    static let shadowBlur: CGFloat = 24
}

extension View {
    /// The one card shadow. In dark mode a soft shadow on a dark surface is invisible,
    /// so it's dropped there (the card surface + hairline border carry elevation).
    func vtCardShadow() -> some View { modifier(VTCardShadow()) }

    /// Standard card surface. Light: soft shadow. Dark: a 1px hairline border instead.
    func vtCard(radius: CGFloat = VT.rCard) -> some View { modifier(VTCardStyle(radius: radius)) }
}

private struct VTCardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.shadow(color: scheme == .dark ? .clear : VT.shadowColor,
                       radius: VT.shadowBlur / 2, x: 0, y: scheme == .dark ? 0 : VT.shadowY)
    }
}

private struct VTCardStyle: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background(VT.card, in: shape)
            .overlay { if scheme == .dark { shape.strokeBorder(VT.hairline, lineWidth: 1) } }
            .modifier(VTCardShadow())
    }
}
