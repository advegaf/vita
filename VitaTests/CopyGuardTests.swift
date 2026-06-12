import XCTest
@testable import Vita

/// Guards user-facing copy invariants.
final class CopyGuardTests: XCTestCase {

    /// No em dashes anywhere in the seeded catalog copy (the user banned them app-wide).
    @MainActor
    func testNoEmDashesInCatalog() throws {
        let seeds = try XCTUnwrap(CatalogStore.loadSeeds(), "catalog.json should load")
        for s in seeds {
            let fields: [String?] = [s.name, s.subcategory, s.rxRationale,
                                     s.mechanismBlurb, s.about, s.cycleGuidance, s.reconNote]
            for f in fields where f?.contains("—") == true {
                XCTFail("Em dash found in \(s.slug): \(f!)")
            }
        }
    }

    /// Every compound ships a descriptive About blurb for the add sheet.
    @MainActor
    func testEveryCompoundHasAbout() throws {
        let seeds = try XCTUnwrap(CatalogStore.loadSeeds())
        let missing = seeds.filter { ($0.about ?? "").isEmpty }.map(\.slug)
        XCTAssertTrue(missing.isEmpty, "Missing About text for: \(missing)")
    }

    /// No em dashes in ANY Swift source string (outside // comments). The catalog
    /// guard above missed UI copy for months (an em dash shipped in Settings).
    /// Allowlist: ClaudeSchemas.swift, whose prompt instruction quotes the banned
    /// character and whose sanitizer defines its replacement.
    func testNoEmDashesInSwiftSources() throws {
        let fm = FileManager.default
        // VitaTests/<this file> → repo root → Vita/
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Vita")
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw XCTSkip("source tree not available in this test environment")
        }
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            if url.lastPathComponent == "ClaudeSchemas.swift" { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (n, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                if code.contains("—") {
                    offenders.append("\(url.lastPathComponent):\(n + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Em dashes in code (not comments): \(offenders)")
    }
}
