#if DEBUG
import Foundation
import SwiftData

/// Debug-only: runs the real lab-interpret pipeline against a PDF placed in the app's
/// Documents container (so I can verify labs end-to-end in the simulator with the live
/// API, without bundling any PII). Trigger with `VITA_LAB_SELFTEST=1`; push the file with:
///   DIR=$(xcrun simctl get_app_container <sim> <bundleid> data)
///   cp some.pdf "$DIR/Documents/selftest.pdf"
/// Read the result in the log: `vita-labs-selftest: …`.
enum LabSelfTest {
    @MainActor
    static func run(context: ModelContext) async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = docs.appendingPathComponent("selftest.pdf")
        guard let data = try? Data(contentsOf: url) else {
            NSLog("vita-labs-selftest: no selftest.pdf in %@", docs.path); return
        }
        let prep = LabImageEncoder.prepare(data: data, mediaTypeHint: "application/pdf")
        let pages = LabImageEncoder.pdfPageCount(prep.data)
        let hasText = LabImageEncoder.pdfHasTextLayer(prep.data)
        NSLog("vita-labs-selftest: start bytes=%d pages=%d hasText=%d", data.count, pages, hasText ? 1 : 0)
        let t = Date()
        let result: String
        do {
            let dto = try await LabService(context: context).interpret(imageData: prep.data, mediaType: prep.mediaType)
            result = String(format: "OK values=%d date=%@ lab=%@ elapsed=%.0fs",
                            dto.values.count, dto.panelDate ?? "nil", dto.sourceLabName ?? "nil",
                            Date().timeIntervalSince(t))
        } catch {
            result = String(format: "ERROR %@ elapsed=%.0fs",
                            String(describing: error), Date().timeIntervalSince(t))
        }
        NSLog("vita-labs-selftest: %@", result)
        // Log streaming from the sim is flaky; a result file is deterministic.
        try? result.write(to: docs.appendingPathComponent("selftest-result.txt"),
                          atomically: true, encoding: .utf8)
    }
}
#endif
