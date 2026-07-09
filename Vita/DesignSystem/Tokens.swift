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

    // V2 (wellness redesign): airy near-white light surfaces; dark = neutral
    // graphite (the winner of the 4-variant screenshot experiment, user-picked).

    // Surfaces
    static let canvas   = Color(light: "F7F7F5", dark: "121214") // app background (never a card)
    static let card     = Color(light: "FFFFFF", dark: "1E1E20") // every card / sheet
    static let hairline = Color(light: "EFEEEB", dark: "33333A") // divider / dark card border

    // Text
    static let ink   = Color(light: "111111", dark: "F5F5F7") // headlines, charcoal pill, bolded terms
    /// Label/glyph color sitting ON a filled surface (the ink pill, a selected toggle,
    /// the done checkmark): white in light, near-black in dark — because every
    /// dark-mode fill (ink, accents) is a light tone, so a dark label reads on all.
    static let onInk = Color(light: "FFFFFF", dark: "121214")
    static let body  = Color(light: "6B6B6B", dark: "AEAEB4") // body copy
    static let micro = Color(light: "9A9A9A", dark: "8E8E96") // disclaimers, captions (>=4.5 on dark card)

    // Accents (semantic — each does double duty as dimension + day-state)
    static let dose   = Color(light: "2BB3F3", dark: "4FC3F7") // brand blue: actions, AI, links
    static let timing = Color(light: "F5B82E", dark: "FFCB4D") // Timing + "upcoming"
    static let why    = Color(light: "3E3630", dark: "D9CBBC") // Why + "logged / done" (flips light on dark)
    static let overdue = Color(light: "C0593F", dark: "D97E63") // overdue ONLY (never iOS error-red)

    // Biomarker status trio (reference language: optimal / normal / out of range)
    static let optimal    = Color(light: "2FBF71", dark: "4BD98A")
    static let normal     = Color(light: "CDC22E", dark: "D9CE4B")
    static let outOfRange = Color(light: "F05FA6", dark: "F27EB4")

    // Category tints — matched to the vial render hues (one per category, closed set)
    static let catBlue   = Color(light: "3FA9E0", dark: "5CB8ED")  // Weight Loss
    static let catPurple = Color(light: "9B7FE0", dark: "B29AEB")  // Cognitive
    static let catBrown  = Color(light: "8A7059", dark: "B0917A")  // Muscle & Recovery (lifts so it doesn't vanish)
    static let catPink   = Color(light: "EC9CB4", dark: "F0A9BE")  // Sexual Health
    static let catYellow = Color(light: "E8B43C", dark: "ECC05A")  // General Health
    static let catGray   = Color(light: "9A9A9A", dark: "A7A7AD")  // Other

    /// Registry for the appearance test: every semantic color token, so the test can
    /// assert each resolves distinctly light vs dark and meets contrast on text.
    static let allColorTokens: [(name: String, color: Color)] = [
        ("canvas", canvas), ("card", card), ("hairline", hairline),
        ("ink", ink), ("body", body), ("micro", micro),
        ("dose", dose), ("timing", timing), ("why", why), ("overdue", overdue),
        ("optimal", optimal), ("normal", normal), ("outOfRange", outOfRange),
        ("catBlue", catBlue), ("catPurple", catPurple), ("catBrown", catBrown),
        ("catPink", catPink), ("catYellow", catYellow), ("catGray", catGray),
    ]

    // Radii (V2: rounder, airier)
    static let rCard: CGFloat       = 24
    static let rFocusCard: CGFloat  = 28
    static let segmentCircle: CGFloat = 44

    // Spacing (4pt base)
    static let sCardPad: CGFloat = 20
    static let sCardGap: CGFloat = 14
    static let sSection: CGFloat = 24

    // Shadow (single layer; softer + larger for the airy language)
    static let shadowColor = Color(hex: "111111").opacity(0.05)
    static let shadowY: CGFloat = 10
    static let shadowBlur: CGFloat = 32
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
