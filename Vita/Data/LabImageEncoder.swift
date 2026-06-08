import UIKit
import PDFKit

/// Prepares a captured/imported lab source for both the Claude request and local
/// storage. Re-encoding through UIImage → JPEG inherently DROPS EXIF/GPS metadata
/// (only pixels are redrawn) and downscales to keep the request + the on-device
/// external store modest. PDFs pass through unchanged.
enum LabImageEncoder {
    static func prepare(data: Data, mediaTypeHint: String?) -> (data: Data, mediaType: String) {
        // PDF passthrough (by hint or %PDF magic bytes).
        if mediaTypeHint == "application/pdf" || data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return (data, "application/pdf")
        }
        if let img = UIImage(data: data) {
            let scaled = downscaled(img, maxLongEdge: 2000)
            if let jpeg = scaled.jpegData(compressionQuality: 0.8) {
                return (jpeg, "image/jpeg")          // EXIF/GPS gone
            }
        }
        return (data, mediaTypeHint ?? "image/jpeg")
    }

    static func pdfPageCount(_ data: Data) -> Int { PDFDocument(data: data)?.pageCount ?? 0 }

    /// Renders the first `maxPages` PDF pages to downscaled white-background JPEGs so a
    /// large / scanned / portal-"protected" PDF can be read through the proven image
    /// path instead of a raw `document` block. Empty if the PDF can't be opened.
    static func imagesFromPDF(_ data: Data, maxPages: Int = 5, maxLongEdge: CGFloat = 2000) -> [Data] {
        guard let doc = PDFDocument(data: data) else { return [] }
        var out: [Data] = []
        for i in 0..<min(doc.pageCount, maxPages) {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            let longest = max(b.width, b.height)
            guard longest > 0 else { continue }
            let s = min(2.5, maxLongEdge / longest)        // points→pixels; cap so small pages stay legible
            let px = CGSize(width: b.width * s, height: b.height * s)
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
            let img = UIGraphicsImageRenderer(size: px, format: fmt).image { ctx in
                UIColor.white.set(); ctx.fill(CGRect(origin: .zero, size: px))
                let cg = ctx.cgContext
                cg.translateBy(x: 0, y: px.height)
                cg.scaleBy(x: s, y: -s)
                page.draw(with: .mediaBox, to: cg)
            }
            if let jpeg = img.jpegData(compressionQuality: 0.8) { out.append(jpeg) }
        }
        return out
    }

    static func downscaled(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }
        let scale = maxLongEdge / longEdge
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
