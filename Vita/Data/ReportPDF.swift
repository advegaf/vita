import SwiftUI
import UIKit

/// Renders the physician report to a paginated US-Letter PDF in the temp
/// directory (shared via ActivityShareSheet). ImageRenderer requires MainActor.
@MainActor
enum ReportPDF {
    enum WriteError: Error { case contextFailed }

    static func write(report: ReportBuilder.Report, now: Date = Date()) throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Vita report \(df.string(from: now)).pdf")

        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw WriteError.contextFailed
        }
        for page in ReportBuilder.pages(report) {
            let view = ReportPageView(page: page,
                                      generatedText: report.generatedText,
                                      profileLine: report.profileLine,
                                      disclaimer: report.disclaimer)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: 612, height: 792)
            ctx.beginPDFPage(nil)
            // SwiftUI renders y-down; PDF space is y-up — flip.
            ctx.translateBy(x: 0, y: 792)
            ctx.scaleBy(x: 1, y: -1)
            renderer.render { _, draw in draw(ctx) }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }
}
