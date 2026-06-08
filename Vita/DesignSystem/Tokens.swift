import SwiftUI

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
}

// MARK: - The vita ("fields"-family) design tokens — a closed, semantic set.
// A card is NEVER filled with an accent. Accent appears only as a lead word,
// a small dot, or a segment knob.

enum VT {

    // Surfaces
    static let canvas   = Color(hex: "F1EEE9") // app background (never a card)
    static let card     = Color(hex: "FFFFFF") // every card / sheet
    static let hairline = Color(hex: "EAE6DF") // divider inside the Dose card

    // Text
    static let ink   = Color(hex: "1A1A1A") // headlines, charcoal pill, bolded terms
    static let body  = Color(hex: "6E6E6E") // body copy
    static let micro = Color(hex: "9A958C") // disclaimers, captions, micro-caps

    // Accents (semantic — each does double duty as dimension + day-state)
    static let dose   = Color(hex: "2BB3F3") // Dose  + "due-now / action"
    static let timing = Color(hex: "FFC22E") // Timing + "upcoming"
    static let why    = Color(hex: "3E2B22") // Why   + "logged / done"
    static let overdue = Color(hex: "C0593F") // overdue ONLY (never iOS error-red)

    // Category tints — matched to the vial render hues (one per category, closed set)
    static let catBlue   = Color(hex: "3FA9E0")  // Weight Loss
    static let catPurple = Color(hex: "9B7FE0")  // Cognitive
    static let catBrown  = Color(hex: "8A7059")  // Muscle & Recovery
    static let catPink   = Color(hex: "EC9CB4")  // Sexual Health
    static let catYellow = Color(hex: "E8B43C")  // General Health
    static let catGray   = Color(hex: "9A958C")  // Other

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
    /// The one card shadow used everywhere. No borders, no glow.
    func vtCardShadow() -> some View {
        shadow(color: VT.shadowColor, radius: VT.shadowBlur / 2, x: 0, y: VT.shadowY)
    }

    /// Standard white card surface.
    func vtCard(radius: CGFloat = VT.rCard) -> some View {
        background(VT.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .vtCardShadow()
    }
}
