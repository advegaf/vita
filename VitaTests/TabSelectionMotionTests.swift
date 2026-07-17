import XCTest

/// M44 tab-bar motion contract, pinned at source level because XCTest cannot
/// reliably observe the first animation frame of a SwiftUI state transaction:
/// the ink pill glides inside the bar, the app window never animates, and the
/// bar renders with real Liquid Glass.
final class TabSelectionMotionTests: XCTestCase {

    func testRootShellDoesNotAnimateTabSelection() throws {
        let source = try sourceFile("Vita/App/RootShell.swift")

        XCTAssertFalse(source.contains("value: selection"),
                       "The root container must not animate tab selection; only the bar's pill moves.")
    }

    func testTabBarUsesLiquidGlass() throws {
        let source = try sourceFile("Vita/DesignSystem/Components/FloatingTabBar.swift")

        XCTAssertTrue(source.contains("glassEffect"),
                      "The bar must render with Liquid Glass, not a material imitation.")
        XCTAssertFalse(source.contains(".regularMaterial"),
                       "The frosted-material background must not silently return.")
    }

    func testTabBarPillGlidesWithReduceMotionFallback() throws {
        let source = try sourceFile("Vita/DesignSystem/Components/FloatingTabBar.swift")

        XCTAssertTrue(source.contains("matchedGeometryEffect"),
                      "The selected pill must glide between items via matched geometry.")
        XCTAssertTrue(source.contains("VMotion.tabSelect"),
                      "The glide must use the shared tab-select motion token.")
        XCTAssertTrue(source.contains("accessibilityReduceMotion"),
                      "Reduce Motion must degrade the glide to a fade.")
    }

    func testTabBarIgnoresRemoteKeyboards() throws {
        let source = try sourceFile("Vita/DesignSystem/Components/FloatingTabBar.swift")

        XCTAssertTrue(source.contains("keyboardIsLocalUserInfoKey"),
                      "Remote keyboards (OAuth sign-in sheets) must never hide the bar (M47).")
        XCTAssertTrue(source.contains("scenePhase"),
                      "Returning to an active scene must always restore the bar.")
    }

    func testTabBarKeepsEqualFixedSlots() throws {
        let source = try sourceFile("Vita/DesignSystem/Components/FloatingTabBar.swift")

        XCTAssertTrue(source.contains("frame(width: 84, height: 44)"),
                      "Items keep fixed equal slots so the bar never reflows or re-centers.")
        XCTAssertFalse(source.contains("width: selected ? nil : 0"),
                       "The width-hugging label reveal must not return; end tabs translate with it.")
    }

    func testTabSelectMotionTokenStaysCalm() throws {
        let source = try sourceFile("Vita/DesignSystem/Motion.swift")

        XCTAssertTrue(source.contains("tabSelect = Animation.spring(duration: 0.3, bounce: 0)"),
                      "Tab selection stays a short, no-bounce spring (<= 320ms house rule).")
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
