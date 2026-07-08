import XCTest
import SwiftUI
import UIKit
@testable import Vita

final class AppearanceTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    // MARK: Mapping (pins the follows-system contract)

    func testColorSchemeMapping() {
        XCTAssertNil(AppAppearance.system.colorScheme)
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    // MARK: Parity — every token has a distinct dark variant

    func testEveryTokenHasDistinctDarkVariant() {
        for token in VT.allColorTokens {
            let l = UIColor(token.color).resolvedColor(with: light)
            let d = UIColor(token.color).resolvedColor(with: dark)
            XCTAssertNotEqual(l, d, "\(token.name) has no distinct dark variant")
        }
    }

    // MARK: Legibility — text tokens meet WCAG AA (>=4.5) on the dark surfaces

    func testTextTokensMeetContrastInDark() {
        let card = UIColor(VT.card).resolvedColor(with: dark)
        let canvas = UIColor(VT.canvas).resolvedColor(with: dark)
        for name in ["ink", "body", "micro", "why"] {
            let color = VT.allColorTokens.first { $0.name == name }!.color
            let fg = UIColor(color).resolvedColor(with: dark)
            XCTAssertGreaterThanOrEqual(contrastRatio(fg, card), 4.5, "\(name) vs card below AA")
            XCTAssertGreaterThanOrEqual(contrastRatio(fg, canvas), 4.5, "\(name) vs canvas below AA")
        }
    }

    // WCAG relative-luminance contrast ratio.
    private func contrastRatio(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    private func luminance(_ c: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
